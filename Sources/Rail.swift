import SwiftUI

struct Rail: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("L").font(.system(size: 24, weight: .bold)).italic().foregroundStyle(Color(hex: 0xefefef))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x292929), Color(hex: 0x3b3b3b)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [Color(hex: 0x747474), Color(hex: 0x414141)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                Text("Lamport").font(.system(size: 24, weight: .semibold)).tracking(-0.8).foregroundStyle(Color(hex: 0xefefef))
                Spacer()
            }
            .padding(.top, 44).padding(.horizontal, 8).padding(.bottom, 26)

            VStack(spacing: 8) {
                NavItem(icon: "folder", label: desk.folderName ?? "Open folder", on: false) { desk.pickFolder() }
                NavItem(icon: "sparkle", label: "Build", on: true) { }
                NavItem(icon: "square.grid.2x2", label: "Workspace", on: false) { NSWorkspace.shared.open(API.siteURL("/app")) }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("SESSIONS").font(Theme.mono(10, .medium)).tracking(1.6).foregroundStyle(Color(hex: 0x6e6e6e))
                    Spacer()
                    Button { desk.newSession() } label: { Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: 0x9a9a9a)).frame(width: 22, height: 22) }.buttonStyle(Quiet()).help("New session (⌘N)")
                }.padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 6)
                if !desk.signedIn {
                    Text("Sign in and your builds are kept here.").font(Theme.sans(12)).foregroundStyle(Color(hex: 0x7c7c7c)).padding(.horizontal, 20).padding(.top, 6)
                } else if desk.sessions.isEmpty {
                    Text("No builds yet.").font(Theme.sans(12)).foregroundStyle(Color(hex: 0x7c7c7c)).padding(.horizontal, 20).padding(.top, 6)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(desk.sessions) { s in SessionRow(s: s) }
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            MemberCard()
        }
        .padding(.horizontal, 4)
    }
}

struct SessionRow: View {
    @EnvironmentObject var desk: DeskModel
    var s: Session
    @State private var hover = false
    var on: Bool { desk.projectId == s.id }
    var body: some View {
        HStack(spacing: 6) {
            Button { desk.checkOut(s) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(Theme.sans(13, .medium)).foregroundStyle(on ? Theme.ink : Color(hex: 0xc9c9c9)).lineLimit(1)
                    HStack(spacing: 4) {
                        if s.root == nil { Image(systemName: "icloud").font(.system(size: 9)) }
                        Text("\(KIND_LABEL[s.kind] ?? s.kind) · \(ago(s.updated))").lineLimit(1)
                    }.font(Theme.sans(11)).foregroundStyle(Color(hex: 0x7c7c7c))
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(Quiet())
            if hover { Button { desk.deleteSession(s) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0x8a8a8a)).frame(width: 20, height: 20) }.buttonStyle(Quiet()).help("Delete") }
        }
        .padding(.leading, 20).padding(.trailing, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Color.white.opacity(0.05) : hover ? Color.white.opacity(0.025) : .clear))
        .onHover { hover = $0 }
    }
}
func ago(_ d: Date) -> String {
    let s = Int(-d.timeIntervalSinceNow)
    if s < 60 { return "now" }; if s < 3600 { return "\(s / 60)m" }; if s < 86400 { return "\(s / 3600)h" }; return "\(s / 86400)d"
}

struct NavItem: View {
    var icon: String; var label: String; var on: Bool; var tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 18)
                Text(label).font(Theme.sans(14)).lineLimit(1)
                Spacer()
            }
            .foregroundStyle(on ? Theme.ink : Color(hex: 0xababab))
            .padding(.horizontal, 20).frame(height: 48)
            .background(Capsule().fill(on ? LinearGradient(colors: [Color(hex: 0x333333), Color(hex: 0x262626)], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0.06 : 0)))
            .overlay(alignment: .trailing) { if on { Capsule().fill(LinearGradient(colors: [.clear, Color.white.opacity(0.10)], startPoint: .leading, endPoint: .trailing)).frame(width: 90).blur(radius: 10).padding(.trailing, -10) } }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }.buttonStyle(Quiet())
    }
}

struct MemberCard: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 20)).foregroundStyle(Color(hex: 0xbdbdbd)).frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.04))).overlay(Circle().strokeBorder(Color.white.opacity(0.06)))
            Text(desk.signedIn ? "Your next project." : "Sign in to build.").font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
            Text("Open models, free.\nLamport SI, our own crypto-trained model, with Pro.").font(Theme.sans(11.5)).foregroundStyle(Color(hex: 0x8e8e8e)).multilineTextAlignment(.center).lineSpacing(2)
            Button { if desk.signedIn { desk.newSession() } else { desk.signIn() } } label: { Text(desk.signedIn ? "New build" : desk.signingIn ? "Waiting for the browser…" : "Sign in").pill(height: 38, primary: !desk.signedIn).frame(maxWidth: .infinity) }.buttonStyle(Quiet()).padding(.top, 4)
            if desk.signedIn { Text("\(desk.turnsLeft ?? desk.freeTurns) free turns remaining").font(Theme.sans(10)).foregroundStyle(Color(hex: 0x6a6a6a)) }
            else if let e = desk.authError { Text(e).font(Theme.sans(10)).foregroundStyle(Color(hex: 0xd09a9a)).multilineTextAlignment(.center) }
            else { Text("Free for members · Lamport SI with Pro").font(Theme.sans(10)).foregroundStyle(Color(hex: 0x6a6a6a)) }
            if desk.signedIn { Button("Sign out") { desk.signOut() }.buttonStyle(Quiet()).font(Theme.sans(11)).foregroundStyle(Color(hex: 0x7a7a7a)) }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
        .padding(.bottom, 2)
    }
}
