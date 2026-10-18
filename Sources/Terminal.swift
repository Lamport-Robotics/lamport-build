import SwiftUI
import AppKit
import SwiftTerm

/// one live shell per folder, kept alive while you switch sessions and tabs
@MainActor
final class TermBox: NSObject, TerminalViewDelegate {
    private static var boxes: [String: TermBox] = [:]
    static func box(_ directory: String, engine: Engine) -> TermBox {
        if let b = boxes[directory] { return b }
        let b = TermBox(directory: directory, engine: engine)
        boxes[directory] = b
        return b
    }

    let directory: String
    let view: TerminalView
    private weak var engine: Engine?
    private var ptyID: String?
    private var socket: URLSessionWebSocketTask?
    private var started = false
    private var resize: Task<Void, Never>?

    private init(directory: String, engine: Engine) {
        self.directory = directory
        self.engine = engine
        view = TerminalView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        super.init()
        view.terminalDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = NSColor(Theme.side)
        view.nativeForegroundColor = NSColor(Theme.ink2)
        view.caretColor = NSColor(Theme.ink)
        view.optionAsMetaKey = true
        let click = NSClickGestureRecognizer(target: self, action: #selector(grabFocus))
        click.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(click)
    }

    /// a click in the shell, or opening its tab, puts the keyboard in the shell rather than the composer
    @objc func grabFocus() { view.window?.makeFirstResponder(view) }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        Task { await connect() }
    }

    private func connect() async {
        guard let engine else { return }
        let t = view.terminal!
        do {
            let (id, url) = try await engine.openTerminal(in: directory, cols: t.cols, rows: t.rows)
            ptyID = id
            let ws = URLSession.shared.webSocketTask(with: url)
            socket = ws
            ws.resume()
            receive(ws)
        } catch {
            view.feed(text: "\r\n\u{1b}[2mcould not open a terminal: \(error.localizedDescription)\u{1b}[0m\r\n")
            started = false
        }
    }

    private func receive(_ ws: URLSessionWebSocketTask) {
        ws.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(.string(let s)): self.view.feed(text: s)
                case .success(.data(let d)):
                    // frames that start with a zero byte are the engine's own bookkeeping, not output
                    if d.first != 0 { self.view.feed(byteArray: ArraySlice([UInt8](d))) }
                case .failure:
                    if self.socket === ws {
                        self.view.feed(text: "\r\n\u{1b}[2mterminal closed, click to start a new one\u{1b}[0m\r\n")
                        self.socket = nil; self.ptyID = nil; self.started = false
                    }
                    return
                @unknown default: break
                }
                self.receive(ws)
            }
        }
    }

    // MARK: TerminalViewDelegate

    /// keystrokes go out in the order they were typed: SwiftTerm calls this on the main thread, so send right here
    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let s = String(decoding: data, as: UTF8.self)
        MainActor.assumeIsolated {
            if socket == nil { startIfNeeded(); return }
            socket?.send(.string(s)) { _ in }
        }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        Task { @MainActor in
            self.resize?.cancel()
            self.resize = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, let id = self.ptyID, let engine = self.engine else { return }
                try? await engine.resizeTerminal(id, directory: self.directory, cols: newCols, rows: newRows)
            }
        }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let u = URL(string: link) { DispatchQueue.main.async { NSWorkspace.shared.open(u) } }
    }
    nonisolated func bell(source: TerminalView) {}
    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        guard let s = String(data: content, encoding: .utf8) else { return }
        DispatchQueue.main.async { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
    }
    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

struct TerminalHost: View {
    @EnvironmentObject var engine: Engine
    var directory: String
    var focused: Bool
    var body: some View {
        let box = TermBox.box(directory, engine: engine)
        TermRep(box: box)
            .padding(.leading, 10).padding(.top, 8).padding(.bottom, 4)
            .background(Theme.side)
            .onAppear { if focused { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { box.grabFocus() } } }
            .onChange(of: focused) { _, f in if f { DispatchQueue.main.async { box.grabFocus() } } }
    }
}

struct TermRep: NSViewRepresentable {
    let box: TermBox
    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        attach(host)
        return host
    }
    func updateNSView(_ host: NSView, context: Context) { attach(host) }
    private func attach(_ host: NSView) {
        let v = box.view
        if v.superview !== host {
            v.removeFromSuperview()
            v.frame = host.bounds
            v.autoresizingMask = [.width, .height]
            host.addSubview(v)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { box.startIfNeeded() }
    }
}
