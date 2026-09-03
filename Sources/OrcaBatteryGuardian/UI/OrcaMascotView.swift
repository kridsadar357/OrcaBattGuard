import AppKit
import SwiftUI

enum OrcaArtwork {
    static let image: NSImage = {
        guard let url = Bundle.module.url(forResource: "orca-mascot", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: "Orca") ?? NSImage()
        }
        return image
    }()

    static let menuBarImage: NSImage = {
        guard let image = image.copy() as? NSImage else { return NSImage() }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

public struct OrcaMascotView: View {
    private let size: CGFloat

    public init(size: CGFloat = 88) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.055))
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

            Image(nsImage: OrcaArtwork.image)
                .resizable()
                .scaledToFit()
                .padding(size * 0.03)
                .accessibilityLabel("Orca using a MacBook")
        }
        .frame(width: size, height: size)
    }
}

public struct OrcaMenuBarIconView: View {
    public init() {}

    public var body: some View {
        Image(nsImage: OrcaArtwork.menuBarImage)
            .frame(width: 18, height: 18)
            .accessibilityLabel("Orca Battery Guardian")
    }
}
