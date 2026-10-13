import SwiftUI

/// Coreplay's brand assets.
///
/// The logo artwork comes from `Design/Coreplay-logo-source.png` and is
/// exported as bitmaps (it isn't redrawn in code). The app icon in the app
/// target's asset catalog is built from the same source.
public enum Brand {
    public static let appName = "Coreplay"

    /// The app logo tile, with transparent rounded corners.
    public static var logo: Image {
        Image("AppLogo", bundle: .module)
    }
}

/// The logo at a given size, with the subtle shadow used for artwork.
public struct BrandLogo: View {
    private let size: CGFloat

    public init(size: CGFloat = 64) {
        self.size = size
    }

    public var body: some View {
        Brand.logo
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.04)
            .accessibilityLabel(Text(Brand.appName))
    }
}
