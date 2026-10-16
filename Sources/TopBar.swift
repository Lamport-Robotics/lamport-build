import SwiftUI

struct TopBar: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(desk.models) { m in
                    Button { if m.available { desk.model = m.id } else { desk.say("Lamport SI, our own crypto-trained model, comes with Pro. The open models are free.") } } label: {
                        Text("\(m.label)  ·  \(m.pro ? (m.available ? "Pro" : "Pro · soon") : "free")")
                        Text(m.note)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("L").font(.system(size: 13, weight: .bold)).italic().foregroundStyle(Color(hex: 0xd0d0d0)).frame(width: 22, height: 22)
                        .background(Circle().fill(Color(hex: 0x3a3a3a))).overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
                    Text(desk.currentModel?.label ?? desk.model).font(Theme.sans(13)).foregroundStyle(Color(hex: 0xc5c5c5))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0x8a8a8a))
                }
                .padding(.horizontal, 17).frame(height: 44)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x303030), Color(hex: 0x292929)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.03)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            if let f = desk.folder {
                Button { desk.pickFolder() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder").font(.system(size: 11, weight: .medium))
                        Text(f.lastPathComponent).font(Theme.mono(12, .medium))
                    }
                    .foregroundStyle(Color(hex: 0xc7c7c7))
                    .padding(.horizontal, 13).frame(height: 32)
                    .background(Capsule().fill(Color.white.opacity(0.04))).overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                }.buttonStyle(Quiet()).help(f.path)
            }
            Spacer()
            Button { NSWorkspace.shared.open(API.siteURL("/app")) } label: { Image(systemName: "globe").font(.system(size: 15)).circle43() }.buttonStyle(Quiet()).help("Open the workspace on lamport.si")
            if desk.folder != nil && desk.canPreview {
                Button { desk.sideTab = 1; if !desk.isStatic { Task { await desk.startRun("installing and starting the project") } } } label: {
                    HStack(spacing: 9) { Image(systemName: "play.fill").font(.system(size: 9)); Text("Run") }.pill(primary: true)
                }.buttonStyle(Quiet()).help("Run (⌘R)")
            }
            if desk.signedIn {
                Text(String((desk.who ?? "L").prefix(1)).uppercased()).font(Theme.sans(14, .medium)).foregroundStyle(Color(hex: 0xdddddd))
                    .frame(width: 43, height: 43).background(Circle().fill(Color(hex: 0x2c2c2c))).overlay(Circle().strokeBorder(Color.white.opacity(0.04))).help(desk.who ?? "")
            } else {
                Button { desk.signIn() } label: { Text(desk.signingIn ? "Waiting…" : "Sign in").pill(primary: true) }.buttonStyle(Quiet())
            }
        }
        .padding(.horizontal, 26)
    }
}
