import SwiftUI
import AppKit

/// the right side of the window: what changed in the folder, the files in it, and a real shell
struct SidePane: View {
    @EnvironmentObject var store: Store
    /// folders whose shell has been opened once; it then stays alive behind the other tabs
    @State private var shells: Set<String> = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Tab(title: "Diff", icon: "plusminus", on: store.sideTab == .diff, badge: store.diffs.isEmpty ? nil : "\(store.diffs.count)") { store.sideTab = .diff }
                Tab(title: "Files", icon: "doc.text", on: store.sideTab == .files, badge: nil) { store.sideTab = .files }
                Tab(title: "Terminal", icon: "terminal", on: store.sideTab == .terminal, badge: nil) { store.sideTab = .terminal }
                Spacer()
                if store.sideTab == .diff {
                    if !store.diffs.isEmpty {
                        Menu {
                            Button("Revert all changes…") { confirmRevertAll() }
                        } label: { Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Theme.mute).frame(width: 24, height: 24) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                    Button { Task { await store.refreshSide() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)).foregroundStyle(Theme.mute) }
                        .buttonStyle(Flat(pad: 6)).help("Refresh")
                }
                if store.sideTab == .files, let dir = store.directory {
                    Button { store.openInTerminal(dir) } label: { Image(systemName: "apple.terminal").font(.system(size: 11.5)).foregroundStyle(Theme.mute) }
                        .buttonStyle(Flat(pad: 6)).help("Open in Terminal")
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: dir)]) } label: { Image(systemName: "folder").font(.system(size: 11.5)).foregroundStyle(Theme.mute) }
                        .buttonStyle(Flat(pad: 6)).help("Show in Finder")
                }
                Button { store.sideOpen = false } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.mute) }
                    .buttonStyle(Flat(pad: 6)).help("Close  ⌥⌘B")
            }
            .padding(.horizontal, 10)
            .frame(height: 44).padding(.top, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            ZStack {
                DiffView().opacity(store.sideTab == .diff ? 1 : 0).allowsHitTesting(store.sideTab == .diff)
                if store.sideTab == .files { FilesView() }
                if let dir = store.directory, store.sideTab == .terminal || shells.contains(dir) {
                    TerminalHost(directory: dir, focused: store.sideTab == .terminal).id(dir).opacity(store.sideTab == .terminal ? 1 : 0).allowsHitTesting(store.sideTab == .terminal)
                }
            }
        }
        .background(Theme.side)
        .onChange(of: store.sideTab) { _, t in if t == .terminal, let d = store.directory { shells.insert(d) } }
        .onAppear { if store.sideTab == .terminal, let d = store.directory { shells.insert(d) } }
    }
    func confirmRevertAll() {
        let a = NSAlert()
        a.messageText = "Revert all changes?"
        a.informativeText = "Every modified file goes back to what git has. New files go to the Trash."
        a.alertStyle = .warning
        a.addButton(withTitle: "Revert"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { store.revertAll() }
    }
}

struct Tab: View {
    var title: String; var icon: String; var on: Bool; var badge: String?; var tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(Theme.sans(12.5, on ? .medium : .regular))
                if let badge { Text(badge).font(Theme.sans(10, .medium)).foregroundStyle(on ? Theme.ink : Theme.mute).padding(.horizontal, 5).frame(height: 16).background(Capsule().fill(Color.white.opacity(0.08))) }
            }
            .foregroundStyle(on ? Theme.ink : Theme.mute)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Theme.selected : .clear))
        }.buttonStyle(Quiet())
    }
}

/// an empty tab: a symbol, a line, a quieter line under it
struct Empty: View {
    var icon: String; var title: String; var text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Theme.dim)
            Text(title).font(Theme.sans(13, .medium)).foregroundStyle(Theme.ink2)
            Text(text).font(Theme.sans(12)).foregroundStyle(Theme.dim).multilineTextAlignment(.center).frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: diff

struct DiffView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let note = store.diffNote {
            Empty(icon: "arrow.triangle.branch", title: "Not a git repository", text: note)
        } else if store.diffs.isEmpty {
            Empty(icon: "plusminus", title: "No changes yet", text: "Edits the agent makes show up here, file by file, with the lines that changed.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let t = store.diffTotals
                    HStack(spacing: 6) {
                        Text("\(store.diffs.count) file\(store.diffs.count == 1 ? "" : "s") changed").foregroundStyle(Theme.mute)
                        Text("+\(t.add)").foregroundStyle(Theme.green)
                        Text("−\(t.del)").foregroundStyle(Theme.red)
                        Spacer()
                        if let b = store.branch { Text(b).foregroundStyle(Theme.dim) }
                    }
                    .font(Theme.sans(12)).monospacedDigit().padding(.horizontal, 4)
                    ForEach(store.diffs) { FileDiffView(diff: $0) }
                }
                .padding(12)
            }
        }
    }
}

/// one line of a patch with where it sits in the old and the new file
struct PatchLine: Identifiable {
    enum Kind { case add, del, ctx, hunk }
    let id: Int
    let kind: Kind
    let text: String
    let old: Int?
    let new: Int?

    static func parse(_ patch: String) -> [PatchLine] {
        var out: [PatchLine] = []
        var o = 0, n = 0
        for (i, raw) in patch.components(separatedBy: "\n").enumerated() {
            if raw.hasPrefix("diff --git") || raw.hasPrefix("index ") || raw.hasPrefix("--- ") || raw.hasPrefix("+++ ") || raw.hasPrefix("new file mode") || raw.hasPrefix("deleted file mode") || raw.hasPrefix("\\ No newline") || raw.hasPrefix("similarity") || raw.hasPrefix("rename ") || raw.hasPrefix("old mode") || raw.hasPrefix("new mode") { continue }
            if raw.hasPrefix("@@") {
                // @@ -12,7 +12,8 @@
                let parts = raw.components(separatedBy: " ")
                if parts.count >= 3 { o = Int(parts[1].dropFirst().components(separatedBy: ",")[0]) ?? 0; n = Int(parts[2].dropFirst().components(separatedBy: ",")[0]) ?? 0 }
                out.append(PatchLine(id: i, kind: .hunk, text: raw, old: nil, new: nil)); continue
            }
            if raw.hasPrefix("+") { out.append(PatchLine(id: i, kind: .add, text: String(raw.dropFirst()), old: nil, new: n)); n += 1 }
            else if raw.hasPrefix("-") { out.append(PatchLine(id: i, kind: .del, text: String(raw.dropFirst()), old: o, new: nil)); o += 1 }
            else if raw.isEmpty && i == patch.components(separatedBy: "\n").count - 1 { continue }
            else { out.append(PatchLine(id: i, kind: .ctx, text: String(raw.dropFirst(raw.hasPrefix(" ") ? 1 : 0)), old: o, new: n)); o += 1; n += 1 }
        }
        return out
    }
}

struct FileDiffView: View {
    @EnvironmentObject var store: Store
    var diff: FileDiff
    @State private var open = true
    @State private var hover = false
    var lines: [PatchLine] { PatchLine.parse(diff.patch) }
    var body: some View {
        let lang = fileKind(diff.file)
        let dir = (diff.file as NSString).deletingLastPathComponent
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 10).rotationEffect(.degrees(open ? 90 : 0))
                        Chip(text: diff.status == "added" ? "A" : diff.status == "deleted" ? "D" : "M", color: diff.status == "added" ? Theme.green : diff.status == "deleted" ? Theme.red : Theme.amber, mono: true)
                        HStack(spacing: 0) {
                            if !dir.isEmpty { Text(dir + "/").foregroundStyle(Theme.dim) }
                            Text((diff.file as NSString).lastPathComponent).foregroundStyle(Theme.ink)
                        }
                        .font(Theme.mono(12)).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 6)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(Quiet())
                if hover {
                    Button { store.openFile(diff.file) } label: { Image(systemName: "arrow.up.forward.square").font(.system(size: 11)).foregroundStyle(Theme.mute) }.buttonStyle(Flat(pad: 4)).help("Open")
                    Button { store.revert(diff) } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 11)).foregroundStyle(Theme.mute) }.buttonStyle(Flat(pad: 4)).help("Revert this file")
                }
                Text("+\(diff.additions)").font(Theme.mono(11)).foregroundStyle(Theme.green)
                Text("−\(diff.deletions)").font(Theme.mono(11)).foregroundStyle(Theme.red)
            }
            .padding(.horizontal, 10).frame(height: 34)
            .onHover { hover = $0 }
            .contextMenu {
                Button("Open") { store.openFile(diff.file) }
                Button("Show in Finder") { store.revealFile(diff.file) }
                Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(diff.file, forType: .string) }
                Divider()
                Button("Revert this file") { store.revert(diff) }
            }
            if open {
                Rectangle().fill(Theme.line).frame(height: 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines.prefix(1500)) { l in DiffLine(kind: l.kind, text: l.text, lang: lang, old: l.old, new: l.new) }
                        if lines.count > 1500 { Text("… \(lines.count - 1500) more lines").font(Theme.mono(11)).foregroundStyle(Theme.dim).padding(10) }
                    }
                    .padding(.vertical, 4)
                    .frame(minWidth: 0, alignment: .leading)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}

struct DiffLine: View {
    var kind: PatchLine.Kind
    var text: String
    var lang: String = ""
    var old: Int? = nil
    var new: Int? = nil
    var body: some View {
        let bg: Color = kind == .add ? Theme.addBg : kind == .del ? Theme.delBg : .clear
        HStack(spacing: 0) {
            if kind == .hunk {
                Text(text).font(Theme.mono(10.5)).foregroundStyle(Theme.dim).padding(.horizontal, 10).padding(.vertical, 3)
            } else {
                Text(old.map(String.init) ?? "").font(Theme.mono(10.5)).foregroundStyle(Theme.dim).frame(width: 34, alignment: .trailing)
                Text(new.map(String.init) ?? "").font(Theme.mono(10.5)).foregroundStyle(Theme.dim).frame(width: 34, alignment: .trailing)
                Text(kind == .add ? "+" : kind == .del ? "−" : " ").font(Theme.mono(11.5)).foregroundStyle(kind == .add ? Theme.green : kind == .del ? Theme.red : Theme.dim).frame(width: 18)
                Text(Highlighter.attributed(text.isEmpty ? " " : text, lang: lang, font: Theme.mono(11.5)))
                    .opacity(kind == .ctx ? 0.75 : 1)
                    .padding(.trailing, 12)
            }
        }
        .padding(.vertical, 0.5)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(bg)
    }
}

// MARK: files

struct FilesView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let dir = store.directory {
            if let p = store.preview { Preview(path: p, root: dir) } else {
                let nodes = FileNode.children(of: dir)
                if nodes.isEmpty {
                    Empty(icon: "folder", title: "Nothing here yet", text: "The folder is empty. Files the agent writes show up here.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(nodes) { TreeRow(node: $0, depth: 0) }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        } else {
            Empty(icon: "folder", title: "No folder", text: "Open a folder and its files show up here.")
        }
    }
}

struct TreeRow: View {
    @EnvironmentObject var store: Store
    var node: FileNode; var depth: Int
    @State private var open = false
    @State private var hover = false
    var body: some View {
        Button {
            if node.isDir { withAnimation(.easeOut(duration: 0.12)) { open.toggle() } } else { store.preview = node.path }
        } label: {
            HStack(spacing: 6) {
                if node.isDir { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 10).rotationEffect(.degrees(open ? 90 : 0)) }
                else { Color.clear.frame(width: 10) }
                Image(systemName: fileIcon(node.path, directory: node.isDir)).font(.system(size: 11)).foregroundStyle(node.isDir ? Theme.amber.opacity(0.8) : Theme.dim).frame(width: 14)
                Text(node.name).font(Theme.sans(12.5)).foregroundStyle(node.isDir ? Theme.ink : Theme.ink2).lineLimit(1)
                Spacer()
            }
            .padding(.leading, 12 + CGFloat(depth) * 14).padding(.trailing, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? Theme.hover : .clear).padding(.horizontal, 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(Quiet())
        .onHover { hover = $0 }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: node.path)) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }
            Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(node.path, forType: .string) }
            if !node.isDir { Button("Mention in the composer") { store.draftText = "@" + Store.short(node.path, root: store.directory) + " " } }
        }
        if node.isDir, open {
            ForEach(FileNode.children(of: node.path)) { TreeRow(node: $0, depth: depth + 1) }
        }
    }
}

/// one file, read-only, coloured by its kind; images show as images
struct Preview: View {
    @EnvironmentObject var store: Store
    var path: String; var root: String
    var body: some View {
        let rel = Store.short(path, root: root)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { store.preview = nil } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.mute) }.buttonStyle(Flat(pad: 5)).help("Back to the files")
                Image(systemName: fileIcon(path)).font(.system(size: 11)).foregroundStyle(Theme.dim)
                Text(rel).font(Theme.mono(11.5)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.head)
                Spacer()
                Button { store.draftText = "@" + rel + " " } label: { Image(systemName: "at").font(.system(size: 11.5)).foregroundStyle(Theme.mute) }.buttonStyle(Flat(pad: 5)).help("Mention in the composer")
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: { Image(systemName: "arrow.up.forward.square").font(.system(size: 11.5)).foregroundStyle(Theme.mute) }.buttonStyle(Flat(pad: 5)).help("Open in the default app")
            }
            .padding(.horizontal, 8).frame(height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            let kind = fileKind(path)
            if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "icns", "bmp"].contains(kind), let img = NSImage(contentsOfFile: path) {
                ScrollView([.horizontal, .vertical]) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 1200).padding(16) }
            } else if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int, size > 1_500_000 {
                Empty(icon: "doc", title: "Too big to show", text: "\(size / 1024) KB. Open it in another app instead.")
            } else if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                CodeText(text: text, lang: kind)
            } else {
                Empty(icon: "doc", title: "Not a text file", text: "Open it in another app instead.")
            }
        }
    }
}

/// a read-only view of a file, coloured by its kind, with a line gutter
struct CodeText: View {
    var text: String; var lang: String
    var body: some View {
        let lines = text.components(separatedBy: "\n")
        let width = CGFloat(String(lines.count).count) * 7 + 14
        GeometryReader { g in
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(i + 1)").font(Theme.mono(10.5)).foregroundStyle(Theme.dim).frame(width: width, alignment: .trailing).padding(.trailing, 12)
                        Text(Highlighter.attributed(line.isEmpty ? " " : line, lang: lang, font: Theme.mono(11.5))).lineLimit(1).fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                    }
                    .padding(.vertical, 1.5)
                }
            }
            .padding(.vertical, 8).padding(.trailing, 16)
            .frame(minWidth: g.size.width, minHeight: g.size.height, alignment: .topLeading)
        }
        }
    }
}
