import SwiftUI

/// the desk's palette: quiet warm-neutral darks, one white for the primary action, colour only where it means something
enum Theme {
    static let bg = Color(hex: 0x161616)        // window, sidebar
    static let main = Color(hex: 0x1c1c1c)      // the conversation
    static let side = Color(hex: 0x181818)      // diff and terminal
    static let raised = Color(hex: 0x252525)    // bubbles, composer, cards
    static let hover = Color.white.opacity(0.05)
    static let selected = Color.white.opacity(0.085)
    static let line = Color.white.opacity(0.07)
    static let line2 = Color.white.opacity(0.12)
    static let ink = Color(hex: 0xececec)
    static let ink2 = Color(hex: 0xbdbdbd)
    static let mute = Color(hex: 0x8a8a8a)
    static let dim = Color(hex: 0x616161)
    static let green = Color(hex: 0x7fd19b)
    static let amber = Color(hex: 0xe6c06a)
    static let red = Color(hex: 0xf08a8a)
    static let addBg = Color(hex: 0x7fd19b, alpha: 0.10)
    static let delBg = Color(hex: 0xf08a8a, alpha: 0.10)

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
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

func ago(_ d: Date) -> String {
    let s = Int(-d.timeIntervalSinceNow)
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    if s < 86400 * 7 { return "\(s / 86400)d" }
    let f = DateFormatter(); f.dateFormat = "d MMM"
    return f.string(from: d)
}
