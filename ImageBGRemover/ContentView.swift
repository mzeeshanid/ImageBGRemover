import SwiftUI

struct ContentView: View {
    @State private var model = BackgroundRemovalModel()

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                if let image = model.displayedImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        // Shows through wherever the image is transparent.
                        .background(Checkerboard())
                }
                if model.isWorking {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                if model.removesBackground {
                    Button("Restore Background", systemImage: "arrow.uturn.backward") {
                        model.restoreBackground()
                    }
                    if let file = model.exportedFile {
                        ShareLink("Share PNG", item: file)
                    }
                } else {
                    Button("Remove Background", systemImage: "person.and.background.dotted") {
                        Task { await model.removeBackground() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .disabled(model.isWorking)
        }
        .padding()
        .task { await model.load() }
        .alert(isPresented: isShowingError, error: model.error) {
            Button("OK", role: .cancel) {}
        }
    }

    /// The pixel size of the photo and, once the background is removed, of the result.
    private var caption: String {
        guard let original = model.originalSize else { return "" }
        guard model.removesBackground, let result = model.resultSize else {
            return "Original: \(pixels(original))"
        }
        return "Original: \(pixels(original)) · Result: \(pixels(result))"
    }

    private func pixels(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height)) px"
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            model.error != nil
        } set: { isPresented in
            if !isPresented {
                model.error = nil
            }
        }
    }
}

/// A grey checkerboard, the usual way to show transparency.
private struct Checkerboard: View {
    var squareSize: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let columns = Int((size.width / squareSize).rounded(.up))
            let rows = Int((size.height / squareSize).rounded(.up))
            var squares = Path()
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    squares.addRect(CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    ))
                }
            }
            context.fill(squares, with: .color(Color(white: 0.85)))
        }
    }
}

#Preview {
    ContentView()
}
