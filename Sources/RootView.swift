import SwiftUI

/// the desk: rail on the left, the main glass card with the top bar, the transcript, the side panel and the status line
struct RootView: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Rail().frame(width: 232)
            ZStack {
                RoundedRectangle(cornerRadius: 29, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x222222), Color(hex: 0x1e1e1e)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).fill(RadialGradient(colors: [Color.white.opacity(0.055), .clear], center: UnitPoint(x: 0.48, y: -0.08), startRadius: 0, endRadius: 760)))
                    .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).strokeBorder(Color.white.opacity(0.03)))
                VStack(spacing: 0) {
                    TopBar().frame(height: 84)
                    HStack(spacing: 0) {
                        CenterPane().frame(maxWidth: .infinity)
                        if desk.folder != nil { SidePanel().frame(width: 460).padding([.trailing, .bottom], 14) }
                    }
                    StatusBar().frame(height: 34)
                }
                .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                if let t = desk.toast {
                    Text(t).font(Theme.sans(12.5)).foregroundStyle(Color(hex: 0xe6e6e6)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color(hex: 0x2c2c2c))).overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 52)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: desk.toast)
        }
        .padding(18)
        .background(Theme.bg)
        .ignoresSafeArea()
    }
}

struct CenterPane: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        VStack(spacing: 0) {
            if desk.turns.isEmpty { Welcome() } else {
                Transcript()
                Composer().padding(.horizontal, 26).padding(.bottom, 16)
            }
        }
    }
}
