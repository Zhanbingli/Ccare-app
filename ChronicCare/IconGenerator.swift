import SwiftUI
import UIKit

struct AppIconView: View {
    var body: some View {
        ZStack {
            // Light green background
            LinearGradient(colors: [Color(red: 0.82, green: 0.98, blue: 0.90), Color(red: 0.52, green: 0.94, blue: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(gradient: Gradient(colors: [Color.white.opacity(0.18), .clear]), center: .init(x: 0.35, y: 0.25), startRadius: 0, endRadius: 600)

            // Central record card
            RoundedRectangle(cornerRadius: 96, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .frame(width: 704, height: 704)
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)

            // Plus badge
            Circle()
                .fill(Color(red: 0.73, green: 0.97, blue: 0.82))
                .frame(width: 128, height: 128)
                .position(x: 320, y: 320)
            Capsule()
                .fill(Color(red: 0.09, green: 0.64, blue: 0.29))
                .frame(width: 16, height: 64)
                .position(x: 320, y: 320)
            Capsule()
                .fill(Color(red: 0.09, green: 0.64, blue: 0.29))
                .frame(width: 64, height: 16)
                .position(x: 320, y: 320)

            // Record lines
            Capsule()
                .fill(Color(red: 0.65, green: 0.95, blue: 0.82))
                .frame(width: 384, height: 20)
                .position(x: 512, y: 450)
            Capsule()
                .fill(Color(red: 0.65, green: 0.95, blue: 0.82))
                .frame(width: 320, height: 20)
                .position(x: 480, y: 510)
            Capsule()
                .fill(Color(red: 0.65, green: 0.95, blue: 0.82))
                .frame(width: 440, height: 20)
                .position(x: 540, y: 570)
            Capsule()
                .fill(Color(red: 0.86, green: 0.99, blue: 0.91))
                .frame(width: 300, height: 14)
                .position(x: 470, y: 687)
        }
        .clipped()
    }
}

enum IconGenerator {
    @MainActor
    static func exportAppIconPNG() throws -> URL {
        let size = CGSize(width: 1024, height: 1024)
        let content = AppIconView()
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()

        // Primary: SwiftUI ImageRenderer
        let renderer = ImageRenderer(content: content)
        renderer.isOpaque = true
        renderer.scale = 1.0
        if let uiImage = renderer.uiImage, let data = uiImage.pngData() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ccare_AppIcon_\(Int(Date().timeIntervalSince1970)).png")
            try data.write(to: url, options: .atomic)
            return url
        }

        // Fallback: snapshot via UIHostingController
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1.0
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let host = UIHostingController(rootView: content)
            host.view.bounds = CGRect(origin: .zero, size: size)
            host.view.backgroundColor = .clear
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            throw NSError(domain: "IconGenerator", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to render icon image (fallback)"])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ccare_AppIcon_\(Int(Date().timeIntervalSince1970)).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
