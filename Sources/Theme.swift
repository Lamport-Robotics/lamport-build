import SwiftUI

/// the build desk's studio palette, the same tokens the web desk uses
enum Theme {
    static let bg = Color(hex: 0x191919)
    static let bg2 = Color(hex: 0x242424)
    static let bg3 = Color(hex: 0x2d2d2d)
    static let line = Color(hex: 0x303030)
    static let line2 = Color(hex: 0x424242)
    static let ink = Color(hex: 0xededed)
    static let ink2 = Color(hex: 0xb7b7b7)
    static let mute = Color(hex: 0x8c8c8c)
    static let dim = Color(hex: 0x686868)
    static let green = Color(hex: 0xb8c3ae)
    static let amber = Color(hex: 0xe2c36b)
    static let red = Color(hex: 0xff8a8a)
    static let add = Color(hex: 0x8fe3a8)

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// a pill with the desk's soft metal gradient
struct Pill: ViewModifier {
    var height: CGFloat = 43
    var primary = false
    func body(content: Content) -> some View {
        content
            .font(Theme.sans(13))
            .foregroundStyle(primary ? Color(hex: 0x111111) : Color(hex: 0xd6d6d6))
            .padding(.horizontal, 20)
            .frame(height: height)
            .background(
                Capsule().fill(primary
                    ? LinearGradient(colors: [Color(hex: 0xf0f0f0), Color(hex: 0xcfcfcf)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color(hex: 0x303030), Color(hex: 0x282828)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(primary ? 0 : 0.03)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(primary ? 0.25 : 0.06), .clear], startPoint: .top, endPoint: .bottom)).padding(0.5))
    }
}

struct Circle43: ViewModifier {
    var size: CGFloat = 43
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color(hex: 0xbbbbbb))
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x343434).opacity(0.67), Color(hex: 0x272727).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.07)))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom)).padding(0.5))
    }
}

extension View {
    func pill(height: CGFloat = 43, primary: Bool = false) -> some View { modifier(Pill(height: height, primary: primary)) }
    func circle43(_ size: CGFloat = 43) -> some View { modifier(Circle43(size: size)) }
}

/// the hover-free flat button style the desk uses everywhere
struct Quiet: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.7 : 1) }
}
