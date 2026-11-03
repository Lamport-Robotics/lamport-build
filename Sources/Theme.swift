import SwiftUI
import CoreText

/// the desk's palette: quiet warm-neutral darks, one white for the primary action, colour only where it means something
enum Theme {
    static let bg = Color(hex: 0x161616)        // window, sidebar
    static let main = Color(hex: 0x1c1c1c)      // the conversation
    static let side = Color(hex: 0x181818)      // diff and terminal
    static let raised = Color(hex: 0x252525)    // bubbles, composer, cards
    static let well = Color.black.opacity(0.28) // code, output, anything set into a card
    static let hover = Color.white.opacity(0.05)
    static let selected = Color.white.opacity(0.085)
    static let line = Color.white.opacity(0.07)
    static let line2 = Color.white.opacity(0.12)
    static let cream = Color(hex: 0xf5efe2)    // the logo's ink
    static let ink = Color(hex: 0xececec)
    static let ink2 = Color(hex: 0xbdbdbd)
    static let mute = Color(hex: 0x8a8a8a)
    static let dim = Color(hex: 0x616161)
    static let green = Color(hex: 0x7fd19b)
    static let amber = Color(hex: 0xe6c06a)
    static let red = Color(hex: 0xf08a8a)
    static let blue = Color(hex: 0x8ab4f8)
    static let addBg = Color(hex: 0x7fd19b, alpha: 0.10)
    static let delBg = Color(hex: 0xf08a8a, alpha: 0.10)
    static let addBg2 = Color(hex: 0x7fd19b, alpha: 0.22)
    static let delBg2 = Color(hex: 0xf08a8a, alpha: 0.22)

    /// the brand face, bundled with the app (Manrope, SIL Open Font License); the system face stands in for anything it lacks
    static let face = "Manrope"
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard fontsReady else { return .system(size: size, weight: weight) }
        switch weight {
        case .ultraLight, .thin, .light, .regular: return .custom("Manrope-Regular", size: size)
        case .medium: return .custom("Manrope-Medium", size: size)
        default: return .custom("Manrope-Bold", size: size)
        }
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static func nsMono(_ size: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }

    private static var fontsReady = false
    /// register the bundled faces once, before the first view draws
    static func registerFonts() {
        guard !fontsReady else { return }
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        var ok = 0
        for u in urls {
            var err: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(u as CFURL, .process, &err) { ok += 1 }
            else if let e = err?.takeRetainedValue(), CFErrorGetCode(e) != CTFontManagerError.alreadyRegistered.rawValue { Log.write("font \(u.lastPathComponent): \(e)") } else { ok += 1 }
        }
        fontsReady = ok > 0 && NSFont(name: "Manrope-Regular", size: 12) != nil
        Log.write("fonts \(ok)/\(urls.count)\(fontsReady ? "" : " (system face)")")
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// the flat button style the desk uses everywhere: no chrome, a soft fill on hover
struct Flat: ButtonStyle {
    var pad: CGFloat = 6
    func makeBody(configuration: Configuration) -> some View { FlatBody(configuration: configuration, pad: pad) }
    struct FlatBody: View {
        let configuration: Configuration; let pad: CGFloat
        @State private var hover = false
        var body: some View {
            configuration.label
                .padding(.horizontal, pad).padding(.vertical, pad * 0.6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover || configuration.isPressed ? Theme.hover : .clear))
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

struct Quiet: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.6 : 1).contentShape(Rectangle()) }
}

/// the white pill for the one thing you most likely want to press
struct Primary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(12.5, .medium))
            .foregroundStyle(Color(hex: 0x141414))
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(Color(hex: 0xededed).opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

struct Secondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(12.5))
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06)))
            .overlay(Capsule().strokeBorder(Theme.line))
    }
}

/// a small rounded tag: a keyboard hint, a file status, a count
struct Chip: View {
    var text: String; var color: Color = Theme.mute; var mono = false
    var body: some View {
        Text(text).font(mono ? Theme.mono(10.5) : Theme.sans(10.5, .medium)).foregroundStyle(color)
            .padding(.horizontal, 6).frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

/// a keyboard shortcut drawn like the menu bar draws it
struct Keys: View {
    var keys: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Text(String(k)).font(Theme.sans(10.5, .medium)).foregroundStyle(Theme.mute)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.line))
            }
        }
    }
}

func ago(_ d: Date) -> String {
    let s = Int(-d.timeIntervalSinceNow)
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    if s < 86400 * 7 { return "\(s / 86400)d" }
    let f = DateFormatter(); f.dateFormat = "d MMM"
    return f.string(from: d)
}

/// the file's kind, for icons and highlighting; the extension, or the name for the well-known extensionless ones
func fileKind(_ path: String) -> String {
    let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    if !ext.isEmpty { return ext }
    if name.hasPrefix(".env") { return "env" }
    switch name { case "makefile": return "make"; case "dockerfile": return "docker"; case "caddyfile": return "caddy"; default: return name }
}

func fileIcon(_ path: String, directory: Bool = false) -> String {
    if directory { return "folder" }
    switch fileKind(path) {
    case "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rs", "go", "rb", "java", "kt", "c", "cc", "cpp", "h", "hpp", "m", "mm", "cs", "php", "lua", "sh", "zsh", "bash": return "chevron.left.forwardslash.chevron.right"
    case "json", "yml", "yaml", "toml", "plist", "xml", "env", "ini", "cfg": return "curlybraces"
    case "md", "txt", "rst", "adoc": return "doc.text"
    case "png", "jpg", "jpeg", "gif", "webp", "svg", "icns", "heic", "tiff", "tif": return "photo"
    case "html", "htm", "css", "scss", "vue", "svelte": return "globe"
    case "lock", "lockb": return "lock"
    case "pdf": return "doc.richtext"
    case "zip", "gz", "tar", "dmg": return "archivebox"
    default: return "doc"
    }
}
