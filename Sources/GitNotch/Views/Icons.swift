import SwiftUI

/// The GitHub "mark" logo, embedded as SVG and loaded as a tintable template
/// image. macOS renders SVG natively via NSImage.
enum Icons {
    static let github: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">\
        <path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 \
        0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 \
        0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 \
        1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 \
        1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 \
        1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 \
        8c0-4.42 3.58-8 8-8Z"/></svg>
        """
        let img = NSImage(data: Data(svg.utf8)) ?? NSImage()
        img.isTemplate = true
        return img
    }()
}

extension Color {
    /// Accent palette from the notch animation design spec.
    static let notchRed = Color(red: 1.0, green: 0.271, blue: 0.227)    // #FF453A
    static let notchGreen = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let notchBlue = Color(red: 0.039, green: 0.518, blue: 1.0)   // #0A84FF

    /// A 6-char hex string as GitHub returns it (no '#'); falls back to grey.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

/// SwiftUI wrapper that renders the mark tinted to `color`.
struct GitHubMark: View {
    var color: Color
    var size: CGFloat = 17
    var body: some View {
        Image(nsImage: Icons.github)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: size, height: size)
            .foregroundStyle(color)
    }
}
