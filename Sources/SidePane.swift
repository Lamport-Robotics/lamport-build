import SwiftUI

/// the right side of the window: what changed in the folder, and a real shell in it
struct SidePane: View {
    @EnvironmentObject var store: Store
    /// folders whose shell has been opened once; it then stays alive behind the diff tab
    @State private var shells: Set<String> = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Tab(title: "Diff", icon: "plusminus", on: store.sideTab == .diff) { store.sideTab = .diff }
                Tab(title: "Terminal", icon: "terminal", on: store.sideTab == .terminal) { store.sideTab = .terminal }
                Spacer()
                if store.sideTab == .diff {
                    Button { Task { await store.refreshSide() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)).foregroundStyle(Theme.mute) }
                        .buttonStyle(Flat(pad: 6)).help("Refresh")
                }
                Button { store.sideOpen = false } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.mute) }
                    .buttonStyle(Flat(pad: 6)).help("Close")
            }
            .padding(.horizontal, 10)
            .frame(height: 44).padding(.top, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            ZStack {
                DiffView().opacity(store.sideTab == .diff ? 1 : 0).allowsHitTesting(store.sideTab == .diff)
                if let dir = store.directory, store.sideTab == .terminal || shells.contains(dir) {
                    TerminalHost(directory: dir, focused: store.sideTab == .terminal).id(dir).opacity(store.sideTab == .terminal ? 1 : 0).allowsHitTesting(store.sideTab == .terminal)
                }
            }
        }
        .background(Theme.side)
        .onChange(of: store.sideTab) { _, t in if t == .terminal, let d = store.directory { shells.insert(d) } }
        .onAppear { if store.sideTab == .terminal, let d = store.directory { shells.insert(d) } }
    }
}

struct Tab: View {
    var title: String; var icon: String; var on: Bool; var tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(Theme.sans(12.5, on ? .medium : .regular))
            }
            .foregroundStyle(on ? Theme.ink : Theme.mute)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Theme.selected : .clear))
        }.buttonStyle(Quiet())
    }
}

// MARK: diff

struct DiffView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let note = store.diffNote {
            Empty(text: note)
        } else if store.diffs.isEmpty {
            Empty(text: "No changes yet. Edits the agent makes show up here, file by file.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let t = store.diffTotals
                    HStack(spacing: 6) {
                        Text("\(store.diffs.count) file\(store.diffs.count == 1 ? "" : "s") changed").foregroundStyle(Theme.mute)
                        Text("+\(t.add)").foregroundStyle(Theme.green)
                        Text("−\(t.del)").foregroundStyle(Theme.red)
                    }
                    .font(Theme.sans(12)).padding(.horizontal, 4)
                    ForEach(store.diffs) { FileDiffView(diff: $0) }
                }
                .padding(12)
            }
        }
    }
}

struct Empty: View {
    var text: String
    var body: some View {
        Text(text).font(Theme.sans(12.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center).frame(maxWidth: 280).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileDiffView: View {
    var diff: FileDiff
    @State private var open = true
    var lines: [String] {
        diff.patch.components(separatedBy: "\n").filter { l in !(l.hasPrefix("diff --git") || l.hasPrefix("index ") || l.hasPrefix("--- ") || l.hasPrefix("+++ ") || l.hasPrefix("new file mode") || l.hasPrefix("deleted file mode") || l.hasPrefix("\\ No newline")) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 10)
                    Text(diff.status == "added" ? "A" : diff.status == "deleted" ? "D" : "M").font(Theme.mono(10.5, .semibold))
                        .foregroundStyle(diff.status == "added" ? Theme.green : diff.status == "deleted" ? Theme.red : Theme.amber)
                    Text(diff.file).font(Theme.mono(12)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.head)
                    Spacer(minLength: 6)
                    Text("+\(diff.additions)").font(Theme.mono(11)).foregroundStyle(Theme.green)
                    Text("−\(diff.deletions)").font(Theme.mono(11)).foregroundStyle(Theme.red)
                }
                .padding(.horizontal, 10).frame(height: 32)
            }.buttonStyle(Quiet())
            if open {
                Rectangle().fill(Theme.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.prefix(1500).enumerated()), id: \.offset) { DiffLine(text: $0.element) }
                }
                .padding(.vertical, 6)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}

struct DiffLine: View {
    var text: String
    var body: some View {
        let hunk = text.hasPrefix("@@"), add = text.hasPrefix("+"), del = text.hasPrefix("-")
        Text(text.isEmpty ? " " : text)
            .font(Theme.mono(11.5))
            .foregroundStyle(hunk ? Theme.dim : add ? Theme.green : del ? Theme.red : Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 0.5)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(add ? Theme.addBg : del ? Theme.delBg : .clear)
    }
}
