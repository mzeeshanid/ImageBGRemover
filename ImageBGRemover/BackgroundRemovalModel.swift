import CoreImage
import Foundation
import Observation

/// Loads the bundled photo, removes its background, and keeps what the screen shows.
@Observable
final class BackgroundRemovalModel {
    /// The image on screen: the photo, or the photo with its background removed.
    private(set) var displayedImage: CGImage?
    /// Whether the image on screen has its background removed.
    private(set) var removesBackground = false
    /// Whether Vision or Core Image is busy.
    private(set) var isWorking = false
    /// The full-size result as a PNG file, ready to share.
    private(set) var exportedFile: URL?
    /// The pixel size of the original photo.
    private(set) var originalSize: CGSize?
    /// The pixel size of the exported result.
    private(set) var resultSize: CGSize?
    var error: BackgroundRemovalError?

    /// The photo's file in the app bundle.
    private var sourceURL: URL?
    /// The photo at full size.
    private var source: CIImage?
    /// The photo scaled down for the screen.
    private var previewSource: CIImage?
    private var originalPreview: CGImage?
    private var cutOutPreview: CGImage?

    /// Loads `input.jpg` from the app bundle.
    func load() async {
        guard source == nil else { return }
        isWorking = true
        defer { isWorking = false }
        guard let url = Bundle.main.url(forResource: "input", withExtension: "jpg") else { return }
        sourceURL = url
        let loaded = await Task.detached(priority: .userInitiated) { () -> (CIImage, CIImage, CGImage)? in
            guard let source = ImageRendering.image(at: url) else { return nil }
            let preview = ImageRendering.scaled(source, toFit: 1600)
            guard let rendered = ImageRendering.cgImage(from: preview) else { return nil }
            return (source, preview, rendered)
        }.value
        guard let loaded else { return }
        (source, previewSource, originalPreview) = loaded
        originalSize = loaded.0.extent.size
        displayedImage = loaded.2
    }

    /// Finds the subjects with Vision, then shows the cut-out and exports it at full size.
    func removeBackground() async {
        guard !isWorking, let source, let sourceURL, let previewSource else { return }
        // Vision has already run for this photo; show its result again.
        if let cutOutPreview {
            displayedImage = cutOutPreview
            removesBackground = true
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) { () -> (CGImage, URL, CGSize) in
                // Vision runs once, on the photo's file.
                let mask = try ImageBackgroundRemover.subjectMask(forImageAt: sourceURL)
                // The same mask is then fitted to the small preview and to the full-size export.
                let preview = ImageBackgroundRemover.removeBackground(from: previewSource, using: mask)
                let full = ImageBackgroundRemover.removeBackground(from: source, using: mask)
                guard let rendered = ImageRendering.cgImage(from: preview) else {
                    // Vision already found a subject here; only the preview failed to render.
                    throw BackgroundRemovalError.renderingFailed
                }
                let file = try ImageRendering.writePNG(full, named: "output")
                return (rendered, file, full.extent.size)
            }.value
            (cutOutPreview, exportedFile, resultSize) = result
            displayedImage = result.0
            removesBackground = true
        } catch let error as BackgroundRemovalError {
            self.error = error
        } catch {
            self.error = .analysisFailed(reason: error.localizedDescription)
        }
    }

    /// Shows the original photo again.
    func restoreBackground() {
        displayedImage = originalPreview
        removesBackground = false
    }
}

/// Core Image helpers for loading, scaling and saving images.
nonisolated enum ImageRendering {
    /// The image file at `url`, turned upright.
    static func image(at url: URL) -> CIImage? {
        CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
    }

    /// `image` scaled down so its longer side is at most `maxSide`. Smaller images are returned as they are.
    static func scaled(_ image: CIImage, toFit maxSide: CGFloat) -> CIImage {
        let longerSide = max(image.extent.width, image.extent.height)
        guard longerSide > maxSide else { return image }
        let scale = maxSide / longerSide
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    static func cgImage(from image: CIImage) -> CGImage? {
        CIContext().createCGImage(image, from: image.extent)
    }

    /// Writes `image` as a PNG in the temporary directory. PNG keeps the transparent background,
    /// which JPEG can't.
    static func writePNG(_ image: CIImage, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        try CIContext().writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: space)
        return url
    }
}
