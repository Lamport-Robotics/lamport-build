import SwiftUI

/// the desk's dark chrome sphere, lit from above, a slow drift in the highlight
struct Orb: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let dx = CGFloat(sin(t * 0.6)) * 0.04, dy = CGFloat(cos(t * 0.45)) * 0.03
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(hex: 0x4a4a4a), Color(hex: 0x1a1a1a), Color(hex: 0x080808)], center: UnitPoint(x: 0.38 + dx, y: 0.3 + dy), startRadius: 2, endRadius: 70))
                Circle().fill(AngularGradient(colors: [.clear, Color.white.opacity(0.10), .clear, Color.white.opacity(0.05), .clear], center: .center, angle: .degrees(t * 12))).blur(radius: 6).blendMode(.screen)
                Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), .clear, Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                Ellipse().fill(RadialGradient(colors: [Color.white.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 18)).frame(width: 36, height: 22).offset(x: -14 + dx * 60, y: -26 + dy * 40).blur(radius: 2)
                Circle().fill(RadialGradient(colors: [.clear, Color.white.opacity(0.06)], center: UnitPoint(x: 0.6, y: 1.0), startRadius: 20, endRadius: 60))
            }
            .shadow(color: .black.opacity(0.6), radius: 18, y: 12)
        }
    }
}
