import SwiftUI

/// enough markdown for an agent's answer: paragraphs, headings, lists, quotes, fenced code, inline styles
struct Markdown: View {
    var text: String
    enum Part: Hashable { case para(String), heading(Int, String), bullet(String, Int, String), code(String, String), quote(String), rule }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(Markdown.parse(text).enumerated()), id: \.offset) { _, p in
                switch p {
                case .para(let s): inline(s).font(Theme.sans(13.5)).foregroundStyle(Theme.ink).lineSpacing(3.5)
                case .heading(let n, let s): inline(s).font(Theme.sans(n == 1 ? 17 : n == 2 ? 15 : 13.5, .semibold)).foregroundStyle(Theme.ink).padding(.top, 4)
                case .bullet(let mark, let depth, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(mark).font(Theme.sans(13.5)).foregroundStyle(Theme.mute).frame(minWidth: 12, alignment: .trailing)
                        inline(s).font(Theme.sans(13.5)).foregroundStyle(Theme.ink).lineSpacing(3.5)
                    }
                    .padding(.leading, CGFloat(depth) * 16)
                case .code(let lang, let s): CodeBlock(lang: lang, code: s)
                case .quote(let s): inline(s).font(Theme.sans(13.5)).foregroundStyle(Theme.ink2).padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Theme.line2).frame(width: 2) }
                case .rule: Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            var out = a
            for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
                out[run.range].font = Theme.mono(12.5)
                out[run.range].backgroundColor = Color.white.opacity(0.07)
            }
            return Text(out)
        }
        return Text(s)
    }

    static func parse(_ text: String) -> [Part] {
        var out: [Part] = []
        var para: [String] = []
        var code: [String]? = nil
        var lang = ""
        func flush() { if !para.isEmpty { out.append(.para(para.joined(separator: "\n"))); para = [] } }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if t.hasPrefix("```") { out.append(.code(lang, code!.joined(separator: "\n"))); code = nil } else { code!.append(line) }
                continue
            }
            if t.hasPrefix("```") { flush(); code = []; lang = String(t.dropFirst(3)); continue }
            if t.isEmpty { flush(); continue }
            if t == "---" || t == "***" { flush(); out.append(.rule); continue }
            if let h = t.firstIndex(where: { $0 != "#" }), t.hasPrefix("#"), t[h] == " " {
                flush(); out.append(.heading(t.distance(from: t.startIndex, to: h), String(t[h...]).trimmingCharacters(in: .whitespaces))); continue
            }
            let depth = (line.prefix(while: { $0 == " " }).count) / 2
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { flush(); out.append(.bullet("•", depth, String(t.dropFirst(2)))); continue }
            if let dot = t.firstIndex(of: "."), t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty, t[t.index(after: dot)...].hasPrefix(" ") {
                flush(); out.append(.bullet(String(t[...dot]), depth, String(t[t.index(dot, offsetBy: 2)...]))); continue
            }
            if t.hasPrefix("> ") { flush(); out.append(.quote(String(t.dropFirst(2)))); continue }
            para.append(line)
        }
        if let code { out.append(.code(lang, code.joined(separator: "\n"))) }
        flush()
        return out
    }
}

struct CodeBlock: View {
    var lang: String; var code: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang).font(Theme.mono(10.5)).foregroundStyle(Theme.dim)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                    copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }.buttonStyle(Quiet()).font(Theme.sans(11)).foregroundStyle(Theme.mute)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(Theme.mono(12)).foregroundStyle(Theme.ink2).lineSpacing(2.5).fixedSize().padding(.horizontal, 12).padding(.bottom, 11).padding(.top, 4)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}
