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
    var writes: Int { Set(turn.parts.compactMap { if case .tool(let r) = $0, r.name == "write_file" || r.name == "edit_file", r.status == .ok { return r.detail }; return nil }).count }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("●").font(Theme.mono(9)).foregroundStyle(Theme.green)
                Text((desk.currentModel?.label ?? desk.model).lowercased()).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x8c8c8c))
                Text(turn.at.formatted(date: .omitted, time: .shortened)).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x5e5e5e))
            }
            if turn.parts.isEmpty && !turn.text.isEmpty { MarkdownText(turn.text) }
            ForEach(turn.parts) { part in
                switch part {
                case .text(_, let s): MarkdownText(s)
                case .tool(let r): ToolRowView(row: r)
                }
            }
            if turn.pending {
                HStack(spacing: 8) {
                    Cursor()
                    Text(desk.doing()).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x9a9a9a))
                }.padding(.top, 2)
            } else if last {
                HStack(spacing: 8) {
                    Text("■").font(Theme.mono(9)).foregroundStyle(Theme.green)
                    Text("done" + (writes > 0 ? " · \(writes) file\(writes > 1 ? "s" : "")" : "")).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x8c8c8c))
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

struct ToolRowView: View {
    @EnvironmentObject var desk: DeskModel
    var row: ToolRow
    var mark: (String, Color) { switch row.status { case .running: ("[…]", Theme.amber); case .ok: ("[+]", Theme.green); case .fail: ("[!]", Theme.red) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(mark.0).foregroundStyle(mark.1)
                Text(row.label).foregroundStyle(Color(hex: 0xd0d0d0))
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
        .onTapGesture { let f = row.detail.replacingOccurrences(of: #":\d+$"#, with: "", options: .regularExpression); if row.name.hasSuffix("file"), desk.files[f] != nil { desk.selected = f; desk.sideTab = 0 } }
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
