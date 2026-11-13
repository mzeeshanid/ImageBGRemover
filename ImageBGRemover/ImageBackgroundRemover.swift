import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// What can go wrong while removing a background.
nonisolated enum BackgroundRemovalError: LocalizedError {
    /// Vision found nothing in the image that it treats as a foreground subject.
    case noSubjectFound
    /// Vision couldn't analyse the image, as happens in the iOS Simulator.
    case analysisFailed(reason: String)
    /// Vision found a subject, but Core Image couldn't render the mask or the masked image.
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .noSubjectFound:
            "No subject was found in this image."
        case .analysisFailed(let reason):
            "The image couldn't be analysed. \(reason)"
        case .renderingFailed:
            "The result couldn't be rendered."
        }
    }
}

/// Separates the foreground subjects of an image from its background with Vision.
///
/// Vision's foreground instance mask finds each separate subject in the image, such as people,
/// pets and objects, and all of them are kept rather than only the most prominent. The mask is
/// scaled to the image, so masking keeps the image's pixel size and every subject's position.
nonisolated enum ImageBackgroundRemover {
    /// A greyscale mask for the image file at `url`: white over every subject Vision finds,
    /// black over the background. The mask has the pixel size of the upright image.
    ///
    /// Vision reads the file itself here. On the sample photo this found both subjects, where
    /// the same image handed over already decoded found only one. That is an observation from
    /// one scene, not a rule: `subjectMask(for:)` is an equally supported input.
    static func subjectMask(forImageAt url: URL) throws -> CGImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw BackgroundRemovalError.analysisFailed(reason: "The image file couldn't be read.")
        }
        return try subjectMask(with: VNImageRequestHandler(url: url), size: image.extent.size)
    }

    /// A greyscale mask the size of `image`: white over every subject Vision finds, black over
    /// the background.
    static func subjectMask(for image: CIImage) throws -> CGImage {
        let input = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        return try subjectMask(with: VNImageRequestHandler(ciImage: input), size: input.extent.size)
    }

    /// Runs Vision with `handler` and renders its mask as a greyscale image of `size`.
    private static func subjectMask(with handler: VNImageRequestHandler, size: CGSize) throws -> CGImage {
        let mask = try foregroundMask(with: handler, size: size)
        // Linear grey saves the mask's values exactly as Vision produced them.
        guard let space = CGColorSpace(name: CGColorSpace.linearGray),
              let result = CIContext().createCGImage(
                  mask, from: CGRect(origin: .zero, size: size), format: .L8, colorSpace: space
              ) else {
            // Vision already found a subject here; the mask itself just failed to render.
            throw BackgroundRemovalError.renderingFailed
        }
        return result
    }

    /// Removes the background of `image` with a mask made by `subjectMask(for:)`.
    ///
    /// The mask is stretched over the image, so one mask serves a small preview and the
    /// full-size original alike. The result has the same extent as `image`.
    static func removeBackground(from image: CIImage, using mask: CGImage) -> CIImage {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty, mask.width > 0, mask.height > 0 else { return image }
        let scale = CGAffineTransform(
            scaleX: extent.width / CGFloat(mask.width),
            y: extent.height / CGFloat(mask.height)
        )
        let fitted = CIImage(cgImage: mask)
            .transformed(by: scale.concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
        return applyMask(fitted, to: image)
    }

    /// Keeps `image` where `mask` is white and makes it transparent where the mask is black.
    static func applyMask(_ mask: CIImage, to image: CIImage) -> CIImage {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = image
        filter.maskImage = mask
        filter.backgroundImage = CIImage.empty()
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    /// One mask covering every foreground subject Vision finds in the handler's image, at `size`.
    private static func foregroundMask(with handler: VNImageRequestHandler, size: CGSize) throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
        } catch {
            throw BackgroundRemovalError.analysisFailed(reason: error.localizedDescription)
        }

        // Each observation lists the separate subjects it found as instances. Every instance of
        // every observation is kept, so no subject is dropped along with the background.
        let masks = try (request.results ?? []).compactMap { observation -> CIImage? in
            guard !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            return CIImage(cvPixelBuffer: buffer)
        }
        guard let first = masks.first else {
            throw BackgroundRemovalError.noSubjectFound
        }
        let mask = masks.dropFirst().reduce(first) { combined, next in
            next.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: combined])
        }

        // The scaled mask already matches the image; this only guards against rounding.
        guard mask.extent.size != size, mask.extent.width > 0, mask.extent.height > 0 else {
            return mask
        }
        return mask.transformed(by: CGAffineTransform(
            scaleX: size.width / mask.extent.width,
            y: size.height / mask.extent.height
        ))
    }
}
