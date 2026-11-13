# ImageBGRemover

A small SwiftUI sample that removes the background of an image with Apple's Vision framework and Core Image.

It uses a mask-based approach, so the result keeps the original image's dimensions and every subject stays in its original position. Only the pixels around the subjects become transparent.

This is the sample project for **[this article](https://mzeeshan.me/blog/remove-image-background-vision-framework-swift)**, which explains the code step by step.

## What it does

- Loads `input.jpg` from the app bundle.
- Asks Vision for a mask covering every foreground subject in the image.
- Blends the image with that mask in Core Image, so the background becomes transparent.
- Shows the result over a checkerboard and exports it as a full-size PNG.

## Requirements

- iOS 17 or later
- Xcode with the iOS SDK
- A real device. The Vision request fails in the iOS Simulator with "Could not create inference context".

## Running it

1. Open `ImageBGRemover.xcodeproj` in Xcode.
2. Select your own team under **Signing & Capabilities**.
3. Run on an iPhone or iPad and tap **Remove Background**.

To try another image, replace `ImageBGRemover/input.jpg`.

## Where to look

| File | Purpose |
| --- | --- |
| `ImageBackgroundRemover.swift` | Makes the subject mask with Vision and applies it with Core Image |
| `BackgroundRemovalModel.swift` | Loads the image, runs the removal off the main thread, writes the PNG |
| `ContentView.swift` | The screen: image, checkerboard, buttons |

## License

MIT. See [LICENSE](LICENSE).
