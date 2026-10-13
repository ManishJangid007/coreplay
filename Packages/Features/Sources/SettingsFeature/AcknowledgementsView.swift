import PlaybackEngine
import SwiftUI

/// Licences and the LGPL source offer for VLCKit and libVLC.
///
/// VLCKit and libVLC are LGPL 2.1 or later. Coreplay links VLCKit
/// dynamically and unmodified, as published by VideoLAN, and doesn't use code
/// from the GPL-licensed VLC apps.
public struct AcknowledgementsView: View {
    @State private var licenseText = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("VLCKit and libVLC")
                    .font(.title2.bold())
                Text("Coreplay plays media with VLCKit \(EngineVersions.vlcKit) and libVLC by VideoLAN, licensed under the GNU Lesser General Public License, version 2.1 or later. VLCKit is used unmodified and linked dynamically.")
                Text("Source code")
                    .font(.headline)
                Text("The complete source code for VLCKit and libVLC, including the exact version used in this app, is available from VideoLAN at code.videolan.org/videolan/VLCKit and code.videolan.org/videolan/vlc. If you received this app from someone and need the source for the version it contains, ask them and they must provide it, as the LGPL requires.")
                Link("VLCKit on code.videolan.org", destination: URL(string: "https://code.videolan.org/videolan/VLCKit")!)
                Link("VLC on code.videolan.org", destination: URL(string: "https://code.videolan.org/videolan/vlc")!)
                Divider()
                Text("GNU Lesser General Public License, version 2.1")
                    .font(.headline)
                Text(licenseText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Acknowledgements")
        .task {
            licenseText = Self.loadLicense()
        }
    }

    private static func loadLicense() -> String {
        guard let url = Bundle.module.url(forResource: "LGPL-2.1", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The licence text is available at https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html"
        }
        return text
    }
}
