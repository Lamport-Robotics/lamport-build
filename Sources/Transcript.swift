import SwiftUI

struct Transcript: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(desk.turns.enumerated()), id: \.element.id) { i, t in
                        if t.role == .user { UserBubble(text: t.text) } else { AssistantTurn(turn: t, last: i == desk.turns.count - 1) }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 12)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { proxy.scrollTo("end") }
            .onChange(of: desk.turns.last?.parts.count) { _, _ in proxy.scrollTo("end") }
            .onChange(of: desk.turns.count) { _, _ in proxy.scrollTo("end") }
        }
    }
}

struct UserBubble: View {
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("›").font(Theme.mono(14, .semibold)).foregroundStyle(Color(hex: 0x8e8e8e))
            Text(text).font(Theme.sans(14)).foregroundStyle(Color(hex: 0xe6e6e6)).lineSpacing(3).textSelection(.enabled)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(UnevenRoundedRectangle(topLeadingRadius: 17, bottomLeadingRadius: 17, bottomTrailingRadius: 4, topTrailingRadius: 17, style: .continuous).fill(Color(hex: 0x2a2a2a)))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 17, bottomLeadingRadius: 17, bottomTrailingRadius: 4, topTrailingRadius: 17, style: .continuous).strokeBorder(Color(hex: 0x424242)))
    }
}

struct AssistantTurn: View {
    @EnvironmentObject var desk: DeskModel
    var turn: Turn; var last: Bool
    var writes: Int { Set(flat(turn.parts).compactMap { r in (r.name == "write_file" || r.name == "edit_file") && r.status == .ok ? r.detail : nil }).count }
    func flat(_ parts: [Part]) -> [ToolRow] { parts.flatMap { p -> [ToolRow] in switch p { case .tool(let r): return [r]; case .agent(let g): return flat(g.parts); default: return [] } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("●").font(Theme.mono(9)).foregroundStyle(Theme.green)
                Text((desk.currentModel?.label ?? desk.model).lowercased()).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x8c8c8c))
                Text(turn.at.formatted(date: .omitted, time: .shortened)).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x5e5e5e))
            }
            if turn.parts.isEmpty && !turn.text.isEmpty { MarkdownText(turn.text) }
            ForEach(turn.parts) { part in PartView(part: part) }
            if turn.pending {
                HStack(spacing: 8) {
                    Cursor()
                    Text(desk.doing()).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x9a9a9a))
                }.padding(.top, 2)
            } else if last {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("■").font(Theme.mono(9)).foregroundStyle(Theme.green)
                        Text("done" + (desk.changes.isEmpty ? "" : " · \(desk.changes.count) file\(desk.changes.count > 1 ? "s" : "") changed")).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x8c8c8c))
                        Spacer()
                        if desk.canUndo { Button { desk.undoLastTurn() } label: { HStack(spacing: 5) { Image(systemName: "arrow.uturn.backward").font(.system(size: 9, weight: .semibold)); Text("undo turn") }.font(Theme.mono(10.5)).foregroundStyle(Color(hex: 0x9a9a9a)).padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(Color.white.opacity(0.05))).overlay(Capsule().strokeBorder(Color.white.opacity(0.07))) }.buttonStyle(Quiet()).help("Put the files back the way they were before this turn (⇧⌘Z)") }
                    }
                    if !desk.changes.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(desk.changes.prefix(12), id: \.path) { c in
                                Button { if desk.has(c.path) { desk.select(c.path); desk.sideTab = 0 } } label: {
                                    HStack(spacing: 10) {
                                        Text(c.before == nil ? "A" : c.after == nil ? "D" : "M").font(Theme.mono(10, .bold)).foregroundStyle(c.before == nil ? Theme.add : c.after == nil ? Theme.red : Theme.amber).frame(width: 10)
                                        Text(c.path).font(Theme.mono(11)).foregroundStyle(Color(hex: 0xc0c0c0)).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        if let b = c.before, let a = c.after { Text(a >= b ? "+\(a - b)" : "−\(b - a)").font(Theme.mono(10)).foregroundStyle(a >= b ? Theme.add : Theme.red) } else if let a = c.after { Text("\(a) lines").font(Theme.mono(10)).foregroundStyle(Color(hex: 0x7a7a7a)) }
                                    }.contentShape(Rectangle())
                                }.buttonStyle(Quiet())
                            }
                            if desk.changes.count > 12 { Text("… \(desk.changes.count - 12) more").font(Theme.mono(10)).foregroundStyle(Color(hex: 0x6a6a6a)) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.02)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
                    }
                }.padding(.top, 2)
            }
        }
        .padding(.horizontal, 3).padding(.vertical, 4)
    }
}

/// chat markdown: paragraphs, inline styles, and fenced code as blocks
struct MarkdownText: View {
    var text: String
    init(_ t: String) { text = t }
    var blocks: [(code: Bool, body: String)] {
        var out: [(Bool, String)] = []; var inCode = false; var cur = ""
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") { out.append((inCode, cur)); cur = ""; inCode.toggle(); continue }
            cur += (cur.isEmpty ? "" : "\n") + line
        }
        out.append((inCode, cur))
        return out.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                if b.code {
                    Text(b.body).font(Theme.mono(11.5)).foregroundStyle(Color(hex: 0xd0d0d0)).lineSpacing(3).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
                } else {
                    Text((try? AttributedString(markdown: b.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(b.body))
                        .font(Theme.sans(13)).foregroundStyle(Color(hex: 0xc9c9c9)).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct PartView: View {
    var part: Part
    var body: some View {
        switch part {
        case .text(_, let s): MarkdownText(s)
        case .tool(let r): ToolRowView(row: r)
        case .todo(_, let items): TodoCard(items: items)
        case .agent(let g): AgentCard(group: g)
        }
    }
}
struct TodoCard: View {
    var items: [TodoItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) { Text("PLAN").font(Theme.mono(10, .medium)).tracking(1.4).foregroundStyle(Color(hex: 0x7a7a7a)); Spacer(); Text("\(items.filter { $0.status == "done" }.count)/\(items.count)").font(Theme.mono(10)).foregroundStyle(Color(hex: 0x6a6a6a)) }
            ForEach(items) { it in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(it.status == "done" ? "■" : it.status == "doing" ? "▸" : "□").font(Theme.mono(10)).foregroundStyle(it.status == "done" ? Theme.green : it.status == "doing" ? Theme.amber : Color(hex: 0x5a5a5a)).frame(width: 10)
                    Text(it.text).font(Theme.sans(12.5)).foregroundStyle(it.status == "done" ? Color(hex: 0x8a8a8a) : Color(hex: 0xd4d4d4)).strikethrough(it.status == "done", color: Color(hex: 0x5a5a5a))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
    }
}
struct AgentCard: View {
    var group: AgentGroup
    @State private var open: Bool? = nil
    var isOpen: Bool { open ?? (group.status == "running") }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { open = !isOpen } label: {
                HStack(spacing: 10) {
                    Text(group.status == "running" ? "[…]" : "[+]").font(Theme.mono(11, .medium)).foregroundStyle(group.status == "running" ? Theme.amber : Theme.green)
                    Text("Agent").font(Theme.mono(11, .medium)).foregroundStyle(Color(hex: 0xd0d0d0))
                    Text(group.mode).font(Theme.mono(10)).foregroundStyle(Color(hex: 0x8a8a8a)).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.white.opacity(0.06)))
                    Text(group.brief).font(Theme.sans(12)).foregroundStyle(Color(hex: 0x9a9a9a)).lineLimit(1)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color(hex: 0x6a6a6a))
                }.contentShape(Rectangle())
            }.buttonStyle(Quiet())
            if isOpen {
                VStack(alignment: .leading, spacing: 8) { ForEach(group.parts) { p in PartView(part: p) } }
                    .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: 0x1c1c1e)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }
}
struct ToolRowView: View {
    @EnvironmentObject var desk: DeskModel
    var row: ToolRow
    var mark: (String, Color) { if row.approval && row.decision == nil && row.status == .running { return ("[?]", Theme.amber) }; switch row.status { case .running: return ("[…]", Theme.amber); case .ok: return ("[+]", Theme.green); case .fail: return ("[!]", Theme.red) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(mark.0).foregroundStyle(mark.1)
                Text(row.name == "web_fetch" ? "Fetch" : row.name == "web_search" ? "Search web" : row.name == "spawn_agent" ? "Delegate" : row.name == "job_status" ? "Job" : row.name == "job_stop" ? "Stop job" : row.label).foregroundStyle(Color(hex: 0xd0d0d0))
                Text(row.detail).foregroundStyle(Color(hex: 0x9a9a9a)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let n = row.note { Text(n).foregroundStyle(Color(hex: 0x6a6a6a)) }
            }
            .font(Theme.mono(11, .medium))
            if let d = row.diff {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(d.old.enumerated()), id: \.offset) { _, l in DiffLine(sign: "-", text: l, color: Theme.red, bg: Color(hex: 0xff5050).opacity(0.08)) }
                    ForEach(Array(d.new.enumerated()), id: \.offset) { _, l in DiffLine(sign: "+", text: l, color: Theme.add, bg: Color(hex: 0x50ff8c).opacity(0.07)) }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
                .padding(.leading, 24)
            }
            if row.approval && row.decision == nil && row.status == .running {
                HStack(spacing: 8) {
                    Text("This command can delete, publish, deploy or touch secrets. Run it?").font(Theme.sans(12)).foregroundStyle(Color(hex: 0xd8c9a0))
                    Spacer()
                    Button { desk.decide(row.id, true) } label: { Text("Allow").font(Theme.sans(12, .medium)).foregroundStyle(Color(hex: 0x111111)).padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(Color(hex: 0xe6e6e6))) }.buttonStyle(Quiet()).keyboardShortcut(.return, modifiers: [])
                    Button { desk.decide(row.id, true, always: true) } label: { Text("Always this session").font(Theme.sans(12)).foregroundStyle(Color(hex: 0xcfcfcf)).padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(Color.white.opacity(0.08))) }.buttonStyle(Quiet())
                    Button { desk.decide(row.id, false) } label: { Text("Deny").font(Theme.sans(12)).foregroundStyle(Color(hex: 0xe0a0a0)).padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(Color.white.opacity(0.06))) }.buttonStyle(Quiet()).keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0xe2c36b).opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(hex: 0xe2c36b).opacity(0.25)))
                .padding(.leading, 24)
            }
            if !row.out.isEmpty {
                Text(row.out.joined(separator: "\n")).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x9e9e9e)).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
                    .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture { let f = row.detail.replacingOccurrences(of: #":\d+$"#, with: "", options: .regularExpression); if row.name.hasSuffix("file"), desk.has(f) { desk.select(f); desk.sideTab = 0 } }
    }
}
struct DiffLine: View {
    var sign: String; var text: String; var color: Color; var bg: Color
    var body: some View {
        HStack(spacing: 8) { Text(sign).frame(width: 8); Text(text).lineLimit(1).truncationMode(.tail); Spacer(minLength: 0) }
            .font(Theme.mono(11)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(bg)
    }
}
struct Cursor: View {
    @State private var on = true
    var body: some View {
        Rectangle().fill(Theme.green).frame(width: 7, height: 12).opacity(on ? 1 : 0.15)
            .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on.toggle() } }
    }
}
