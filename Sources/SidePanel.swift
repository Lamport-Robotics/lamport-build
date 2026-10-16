import SwiftUI
import WebKit

struct SidePanel: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                SideTab(label: "Files", count: desk.files.isEmpty ? nil : desk.files.count, on: desk.sideTab == 0) { desk.sideTab = 0 }
                SideTab(label: "Preview", count: nil, on: desk.sideTab == 1) { desk.sideTab = 1 }.disabled(!desk.canPreview).opacity(desk.canPreview ? 1 : 0.4)
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 8)
            Divider().overlay(Color.white.opacity(0.05))
            if desk.sideTab == 0 { FilesPane() } else { PreviewPane(rt: desk.runtime) }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x1b1b1b)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
struct SideTab: View {
    var label: String; var count: Int?; var on: Bool; var tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 6) {
                Text(label).font(Theme.sans(12, .medium))
                if let c = count { Text("\(c)").font(Theme.mono(10)).foregroundStyle(Color(hex: 0x7a7a7a)) }
            }
            .foregroundStyle(on ? Theme.ink : Color(hex: 0x8c8c8c))
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(on ? Color.white.opacity(0.07) : .clear))
        }.buttonStyle(Quiet())
    }
}

struct FilesPane: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(desk.folderName ?? "project").font(Theme.mono(10, .semibold)).foregroundStyle(Color(hex: 0x9a9a9a)).padding(.horizontal, 10).padding(.vertical, 9)
                    if desk.tree.isEmpty { Text(desk.busy ? "the agent is working…" : "empty folder; the agent creates files here").font(Theme.mono(10)).foregroundStyle(Color(hex: 0x6a6a6a)).padding(10) }
                    ForEach(desk.tree) { n in
                        HStack(spacing: 6) {
                            if n.depth > 0 { Text(n.isLast ? "└─" : "├─").foregroundStyle(Color(hex: 0x4d4d4d)) }
                            if n.isDir { Image(systemName: n.open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: 0x6a6a6a)).frame(width: 8) }
                            Text(n.path.split(separator: "/").last.map(String.init) ?? n.path).foregroundStyle(n.isDir ? Color(hex: 0xc9c9c9) : desk.selected == n.path ? Theme.ink : Color(hex: 0xa6a6a6)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(Theme.mono(10.5, n.isDir ? .semibold : .regular))
                        .padding(.leading, 8 + CGFloat(n.depth) * 14).padding(.trailing, 8).padding(.vertical, 5)
                        .background(desk.selected == n.path ? Color(hex: 0x323232) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { if n.isDir { desk.toggle(n.path) } else { desk.select(n.path) } }
                        .help(n.path)
                    }
                }
            }
            .frame(width: 160)
            .background(Color(hex: 0x1d1d1d))
            VStack(alignment: .leading, spacing: 0) {
                if let s = desk.selected, let body = desk.content(s) {
                    HStack {
                        Text(s).font(Theme.mono(10)).foregroundStyle(Color(hex: 0xa0a0a0)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(body.components(separatedBy: "\n").count) lines · edits save").font(Theme.mono(10)).foregroundStyle(Color(hex: 0x6a6a6a))
                    }.padding(.horizontal, 12).padding(.vertical, 10)
                    Divider().overlay(Color.white.opacity(0.05))
                    CodeEditor(path: s, text: Binding(get: { desk.files[s] ?? "" }, set: { desk.saveFile(s, $0) }))
                } else {
                    Text(desk.busy ? "The agent is working…" : desk.files.isEmpty ? "Nothing here yet." : "Pick a file.").font(Theme.sans(13)).foregroundStyle(Color(hex: 0x888888)).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
        }
    }
}

/// a plain monospaced editor with a line gutter; edits save to disk after a short pause
struct CodeEditor: NSViewRepresentable {
    var path: String
    @Binding var text: String
    func makeCoordinator() -> Coord { Coord(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        tv.textColor = NSColor(Color(hex: 0xd4d4d4)); tv.backgroundColor = NSColor(Theme.bg); tv.insertionPointColor = .white
        tv.isAutomaticQuoteSubstitutionEnabled = false; tv.isAutomaticDashSubstitutionEnabled = false; tv.isAutomaticTextReplacementEnabled = false; tv.isAutomaticSpellingCorrectionEnabled = false; tv.isContinuousSpellCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.isRichText = false; tv.allowsUndo = true; tv.usesFindBar = true
        tv.defaultParagraphStyle = { let p = NSMutableParagraphStyle(); p.lineHeightMultiple = 1.25; return p }()
        tv.typingAttributes = [.font: tv.font!, .foregroundColor: tv.textColor!, .paragraphStyle: tv.defaultParagraphStyle!]
        scroll.drawsBackground = true; scroll.backgroundColor = NSColor(Theme.bg)
        scroll.hasVerticalRuler = true; scroll.rulersVisible = true
        let ruler = LineGutter(scrollView: scroll, orientation: .verticalRuler); ruler.clientView = tv; scroll.verticalRulerView = ruler
        tv.string = text; context.coordinator.path = path
        Highlighter.apply(tv.textStorage!, ext: (path as NSString).pathExtension.lowercased())
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        let ext = (path as NSString).pathExtension.lowercased()
        if context.coordinator.path != path { context.coordinator.path = path; tv.string = text; Highlighter.apply(tv.textStorage!, ext: ext); tv.scrollToBeginningOfDocument(nil); scroll.verticalRulerView?.needsDisplay = true; return }
        if tv.string != text && !context.coordinator.editing { tv.string = text; Highlighter.apply(tv.textStorage!, ext: ext); scroll.verticalRulerView?.needsDisplay = true }
    }
    final class Coord: NSObject, NSTextViewDelegate {
        var parent: CodeEditor; var path = ""; var editing = false; var pending: DispatchWorkItem?
        init(_ p: CodeEditor) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            editing = true; let s = tv.string; pending?.cancel()
            let ext = (path as NSString).pathExtension.lowercased()
            let w = DispatchWorkItem { [weak self] in self?.parent.text = s; self?.editing = false; if let ts = tv.textStorage { let sel = tv.selectedRanges; Highlighter.apply(ts, ext: ext); tv.selectedRanges = sel } }
            pending = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}
final class LineGutter: NSRulerView {
    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) { super.init(scrollView: scrollView, orientation: orientation); ruleThickness = 40 }
    required init(coder: NSCoder) { fatalError() }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = clientView as? NSTextView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        NSColor(Color(hex: 0x1b1b1b)).setFill(); rect.fill()
        let visible = tv.visibleRect; let text = tv.string as NSString
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var line = 1; var idx = 0
        while idx < charRange.location { if text.character(at: idx) == 10 { line += 1 }; idx += 1 }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor(Color(hex: 0x555555))]
        var i = charRange.location
        while i <= NSMaxRange(charRange) && i <= text.length {
            let lineRange = text.lineRange(for: NSRange(location: min(i, max(0, text.length - 1)), length: 0))
            let gr = lm.glyphRange(forCharacterRange: NSRange(location: lineRange.location, length: 0), actualCharacterRange: nil)
            let r = lm.lineFragmentRect(forGlyphAt: min(gr.location, max(0, lm.numberOfGlyphs - 1)), effectiveRange: nil)
            let y = r.minY - visible.minY + tv.textContainerInset.height
            let s = NSAttributedString(string: "\(line)", attributes: attrs)
            s.draw(at: NSPoint(x: ruleThickness - s.size().width - 8, y: y + (r.height - s.size().height) / 2))
            line += 1; i = NSMaxRange(lineRange); if lineRange.length == 0 || i >= text.length { if text.length == 0 || text.character(at: text.length - 1) == 10 { let s2 = NSAttributedString(string: "\(line)", attributes: attrs); s2.draw(at: NSPoint(x: ruleThickness - s2.size().width - 8, y: y + r.height + (r.height - s2.size().height) / 2)) }; break }
        }
    }
}

struct WebView: NSViewRepresentable {
    var url: URL?
    var html: String?
    func makeNSView(context: Context) -> WKWebView { let c = WKWebViewConfiguration(); c.preferences.setValue(true, forKey: "developerExtrasEnabled"); let w = WKWebView(frame: .zero, configuration: c); w.setValue(false, forKey: "drawsBackground"); return w }
    func updateNSView(_ w: WKWebView, context: Context) {
        if let html { if context.coordinator.last != html { context.coordinator.last = html; w.loadHTMLString(html, baseURL: nil) } }
        else if let url, context.coordinator.last != url.absoluteString { context.coordinator.last = url.absoluteString; w.load(URLRequest(url: url)) }
    }
    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var last: String? }
}

struct PreviewPane: View {
    @EnvironmentObject var desk: DeskModel
    @ObservedObject var rt: LocalRuntime
    init(rt: LocalRuntime) { self.rt = rt }
    var statusText: String {
        switch rt.status { case .idle: "not running"; case .installing: "npm install"; case .starting: "starting · \(rt.command ?? "")"; case .running: "running · \(rt.command ?? "")"; case .exited: rt.exitCode == 0 ? "finished" : "exited \(rt.exitCode ?? 0)"; case .failed: rt.error ?? "failed" }
    }
    var dot: Color { switch rt.status { case .running: Theme.green; case .failed: Theme.red; case .idle, .exited: Color(hex: 0x5a5a5a); default: Theme.amber } }
    var body: some View {
        VStack(spacing: 0) {
            if desk.isStatic, let doc = desk.staticDoc {
                WebView(url: nil, html: doc)
                HStack { Text("Rendered here from the files, live as they change. Nothing is deployed.").font(Theme.mono(10)).foregroundStyle(Color(hex: 0x7a7a7a)); Spacer() }.padding(10)
            } else if !desk.canPreview {
                Text(desk.kind == "program" ? "Programs build with anchor in your folder: ask the agent to run `anchor build` and `anchor test`." : "The run starts once the project has a package.json.").font(Theme.sans(13)).foregroundStyle(Color(hex: 0x888888)).multilineTextAlignment(.center).padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    Circle().fill(dot).frame(width: 7, height: 7)
                    Text(statusText).font(Theme.mono(11)).foregroundStyle(Color(hex: 0xa0a0a0)).lineLimit(1)
                    Spacer()
                    if let u = rt.url { Button { NSWorkspace.shared.open(u) } label: { HStack(spacing: 4) { Text("open"); Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)) }.font(Theme.mono(11)).foregroundStyle(Color(hex: 0x9a9a9a)) }.buttonStyle(Quiet()) }
                    Button { desk.termOpen.toggle() } label: { Text("terminal").font(Theme.mono(11)).foregroundStyle(Color(hex: 0xcfcfcf)).padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Color.white.opacity(desk.termOpen ? 0.12 : 0.06))) }.buttonStyle(Quiet())
                    Button { Task { await desk.startRun("installing and starting the project") } } label: { Text(rt.status == .idle ? "run" : "restart").font(Theme.mono(11)).foregroundStyle(Color(hex: 0x111111)).padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Color(hex: 0xdcdcdc))) }.buttonStyle(Quiet()).disabled(rt.status == .installing)
                }.padding(.horizontal, 12).padding(.vertical, 10)
                ZStack {
                    if let u = rt.url { WebView(url: u, html: nil) }
                    else {
                        VStack(spacing: 10) {
                            switch rt.status {
                            case .idle:
                                Text("Run the project here.").font(Theme.sans(14, .medium)).foregroundStyle(Theme.ink)
                                Text("npm install and the dev script run in your folder; the page appears when the server is up.").font(Theme.sans(12)).foregroundStyle(Color(hex: 0x8a8a8a)).multilineTextAlignment(.center)
                                Button { Task { await desk.startRun("installing and starting the project") } } label: { Text("Run").pill(height: 36, primary: true) }.buttonStyle(Quiet()).padding(.top, 6)
                            case .exited where rt.exitCode == 0:
                                Text("The script finished.").font(Theme.sans(14, .medium)).foregroundStyle(Theme.ink)
                                Text("Its output is in the terminal below.").font(Theme.sans(12)).foregroundStyle(Color(hex: 0x8a8a8a))
                            case .failed, .exited:
                                Text(rt.error ?? "failed").font(Theme.sans(13, .medium)).foregroundStyle(Color(hex: 0xe0a0a0)).multilineTextAlignment(.center)
                                Text(desk.busy ? "Handing the error to the agent…" : "Read the terminal, then tell the agent what to change.").font(Theme.sans(12)).foregroundStyle(Color(hex: 0x8a8a8a))
                                if !desk.busy { Button { desk.fixIt() } label: { Text("Ask the agent to fix it").pill(height: 36, primary: true) }.buttonStyle(Quiet()).padding(.top, 6) }
                            default:
                                ProgressView().controlSize(.small)
                                Text(statusText).font(Theme.sans(13, .medium)).foregroundStyle(Theme.ink)
                                Text("Installing packages; a minute is normal.").font(Theme.sans(12)).foregroundStyle(Color(hex: 0x8a8a8a))
                            }
                        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x111111)))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
                if desk.termOpen || rt.url == nil {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(rt.log.isEmpty ? "terminal output appears here" : rt.log.joined(separator: "\n")).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x9a9a9a)).lineSpacing(2).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            Color.clear.frame(height: 1).id("tail")
                        }
                        .onChange(of: rt.log.count) { _, _ in proxy.scrollTo("tail") }
                    }
                    .frame(height: 160).background(Color.black.opacity(0.4)).padding(.top, 10)
                    ShellInput()
                }
            }
        }
    }
}

/// a command line into the project folder, under the terminal output
struct ShellInput: View {
    @EnvironmentObject var desk: DeskModel
    @State private var cmd = ""
    @State private var history: [String] = []
    @State private var cursor = 0
    var body: some View {
        HStack(spacing: 8) {
            Text("$").font(Theme.mono(11, .semibold)).foregroundStyle(Theme.green)
            TextField("", text: $cmd, prompt: Text(desk.shellBusy ? "running…" : "run a command in \(desk.folderName ?? "the folder")").foregroundStyle(Color(hex: 0x5a5a5a)))
                .textFieldStyle(.plain).font(Theme.mono(11)).foregroundStyle(Color(hex: 0xdcdcdc)).disabled(desk.shellBusy)
                .onSubmit { let c = cmd.trimmingCharacters(in: .whitespaces); guard !c.isEmpty else { return }; history.append(c); cursor = history.count; desk.runShell(c); cmd = "" }
                .onKeyPress(.upArrow) { guard cursor > 0 else { return .ignored }; cursor -= 1; cmd = history[cursor]; return .handled }
                .onKeyPress(.downArrow) { guard cursor < history.count else { return .ignored }; cursor += 1; cmd = cursor < history.count ? history[cursor] : ""; return .handled }
        }
        .padding(.horizontal, 12).frame(height: 32).background(Color.black.opacity(0.55))
    }
}
