import RumbleServices
import SwiftUI
import UIKit

/// Loads a photo through `ImageCache` and shows `placeholder` until it arrives or when it fails.
struct RemoteImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                placeholder()
            }
        }
        .animation(.easeOut(duration: 0.2), value: image == nil)
        .task(id: url) {
            guard let data = try? await ImageCache.shared.data(for: url),
                  let decoded = UIImage(data: data)
            else { return }
            image = await decoded.byPreparingForDisplay() ?? decoded
        }
    }
}
