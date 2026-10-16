import SwiftUI

struct Composer: View {
    @EnvironmentObject var desk: DeskModel
    @FocusState private var focused: Bool
    var word: String { desk.prompt.split(separator: " ").first.map(String.init) ?? desk.prompt }
    var palette: [Slash] { desk.prompt.hasPrefix("/") && !desk.prompt.contains("\n") ? SLASH.filter { $0.cmd.hasPrefix(word) } : [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !palette.isEmpty {
                VStack(spacing: 2) {
                    ForEach(palette, id: \.cmd) { c in
                        Button { desk.prompt = c.cmd == "/clear" ? c.cmd : "\(c.cmd) " } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(c.cmd).font(Theme.mono(12.5, .semibold)).frame(width: 72, alignment: .leading)
                                Text(c.hint).font(Theme.sans(12)).foregroundStyle(Color(hex: 0x8c8c8c)).lineLimit(1)
                                Spacer()
                            }.padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(word == c.cmd ? Color.white.opacity(0.07) : .clear))
                            .contentShape(Rectangle())
                        }.buttonStyle(Quiet())
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x1a1a1c)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkle").font(.system(size: 15)).foregroundStyle(Color(hex: 0x8d8d8d)).padding(.top, 3)
                TextField("", text: $desk.prompt, prompt: Text(desk.turns.isEmpty ? (desk.kind == "program" ? "Describe your Solana program…" : desk.kind == "script" ? "What should your script do?" : "Describe what you want to build…") : "What should we change next?").foregroundStyle(Color(hex: 0x8a8a8a)), axis: .vertical)
                    .textFieldStyle(.plain).font(Theme.sans(14)).foregroundStyle(Color(hex: 0xe2e2e2)).lineLimit(2...8)
                    .focused($focused)
                    .onSubmit { if NSEvent.modifierFlags.contains(.shift) { desk.prompt += "\n" } else { desk.send(desk.prompt) } }
                    .onKeyPress(.tab) { if let c = palette.first, desk.prompt.hasPrefix("/"), !desk.prompt.contains(" ") { desk.prompt = "\(c.cmd) "; return .handled }; return .ignored }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(["dapp", "program", "script"], id: \.self) { k in Button(KIND_LABEL[k] ?? k) { desk.kind = k } }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: desk.kind == "dapp" ? "square.grid.2x2" : desk.kind == "program" ? "chevron.left.forwardslash.chevron.right" : "square.3.layers.3d").font(.system(size: 10, weight: .medium))
                        Text(KIND_LABEL[desk.kind] ?? desk.kind).font(Theme.sans(11))
                    }
                    .foregroundStyle(Color(hex: 0x9c9c9c)).padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.04))).overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Spacer()
                if desk.busy {
                    Button { desk.stop() } label: { Text("Stop").font(Theme.sans(12)).foregroundStyle(Color(hex: 0xdddddd)).padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(Color.white.opacity(0.08))) }.buttonStyle(Quiet())
                } else {
                    Button { desk.send(desk.prompt) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x111111))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xf0f0f0), Color(hex: 0xcacaca)], startPoint: .top, endPoint: .bottom)))
                            .opacity(desk.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                    }.buttonStyle(Quiet()).disabled(desk.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x262626)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(focused ? 0.12 : 0.05)))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear { focused = true }
    }
}

struct Welcome: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Orb().frame(width: 104, height: 104)
            Text(desk.folder == nil ? "Pick a folder on your Mac." : "Working in \(desk.folderName ?? "")").font(Theme.sans(23)).foregroundStyle(Color(hex: 0xaaaaaa)).padding(.top, 18).padding(.bottom, 8)
            Text(desk.folder == nil ? "Where should we work?" : "What would you like to build?")
                .font(Theme.sans(29, .medium)).tracking(-0.5)
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xe7e7e7), Color(hex: 0x969696)], startPoint: .leading, endPoint: .trailing))
            if desk.folder == nil {
                Button { desk.pickFolder() } label: { Text("Open a folder").pill(primary: true) }.buttonStyle(Quiet()).padding(.top, 26)
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT").font(Theme.mono(10, .medium)).tracking(1.6).foregroundStyle(Color(hex: 0x6e6e6e)).padding(.leading, 2).padding(.top, 8)
                    ForEach(desk.recent, id: \.self) { f in
                        Button { Task { await desk.openFolder(URL(fileURLWithPath: f)) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.split(separator: "/").last.map(String.init) ?? f).font(Theme.sans(13, .semibold)).foregroundStyle(Theme.ink)
                                Text(f.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x7a7a7a)).lineLimit(1).truncationMode(.middle)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
                            .contentShape(Rectangle())
                        }.buttonStyle(Quiet())
                    }
                }.frame(width: 420).padding(.top, 10).opacity(desk.recent.isEmpty ? 0 : 1)
                Text("The agent reads and writes the files in that folder and runs its commands there, the way a terminal would.\nNothing leaves your Mac except the conversation and the files the model asks to read.")
                    .font(Theme.sans(12)).foregroundStyle(Color(hex: 0x7a7a7a)).multilineTextAlignment(.center).lineSpacing(3).frame(width: 520).padding(.top, 18)
            } else {
                Composer().frame(width: 640).padding(.top, 30)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
