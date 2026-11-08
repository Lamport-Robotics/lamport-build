import SwiftUI

/// the markdown an agent writes: paragraphs, headings, nested and numbered lists, task items, tables, quotes, rules, fenced code with colour, inline styles and links
struct Markdown: View {
    var text: String
    var size: CGFloat = 13.5

    enum Part: Hashable {
        case para(String)
        case heading(Int, String)
        case item(mark: String, depth: Int, text: String, task: Bool?)
        case code(String, String)
        case quote([String])
        case rule
        case table(header: [String], aligns: [Alignment], rows: [[String]])
        enum Alignment: Hashable { case left, center, right }
    }

    var body: some View {
        let parts = Markdown.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                switch p {
                case .para(let s): inline(s).lineSpacing(3.5)
                case .heading(let n, let s):
                    inline(s, size: n == 1 ? 18 : n == 2 ? 15.5 : 14, weight: .medium).padding(.top, i == 0 ? 0 : 6)
                case .item(let mark, let depth, let s, let task):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let task {
                            Image(systemName: task ? "checkmark.square.fill" : "square").font(.system(size: 11.5)).foregroundStyle(task ? Theme.green : Theme.dim).frame(minWidth: 14)
                        } else {
                            Text(mark).font(Theme.sans(size)).foregroundStyle(Theme.mute).frame(minWidth: 14, alignment: .trailing).monospacedDigit()
                        }
                        inline(s).lineSpacing(3.5)
                    }
                    .padding(.leading, CGFloat(depth) * 18)
                case .code(let lang, let s): CodeBlock(lang: lang, code: s)
                case .quote(let lines):
                    VStack(alignment: .leading, spacing: 4) { ForEach(Array(lines.enumerated()), id: \.offset) { _, l in inline(l, color: Theme.ink2).lineSpacing(3) } }
                        .padding(.leading, 12).padding(.vertical, 2)
                        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(Theme.line2).frame(width: 2) }
                case .rule: Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)
                case .table(let header, let aligns, let rows): TableView(header: header, aligns: aligns, rows: rows, inline: inline)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// inline styles: bold, italics, code spans, links, strikethrough
    func inline(_ s: String, size: CGFloat? = nil, weight: Font.Weight = .regular, color: Color = Theme.ink) -> Text {
        let size = size ?? self.size
        guard var a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return Text(s).font(Theme.sans(size, weight)).foregroundStyle(color)
        }
        a.font = Theme.sans(size, weight)
        a.foregroundColor = color
        for run in a.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                a[run.range].font = Theme.mono(size - 1)
                a[run.range].foregroundColor = Theme.cream
                a[run.range].backgroundColor = Color.white.opacity(0.08)
            } else if intent.contains(.stronglyEmphasized) {
                a[run.range].font = Theme.sans(size, .medium)
                a[run.range].foregroundColor = color == Theme.ink ? Color.white : color
            } else if intent.contains(.emphasized) {
                a[run.range].foregroundColor = Theme.cream
            }
            if intent.contains(.strikethrough) { a[run.range].strikethroughStyle = .single }
            if run.link != nil { a[run.range].foregroundColor = Theme.blue; a[run.range].underlineStyle = .single }
        }
        return Text(a)
    }

    // MARK: parsing

    static func parse(_ text: String) -> [Part] {
        var out: [Part] = []
        var para: [String] = []
        var quote: [String] = []
        var code: [String]? = nil
        var fence = "```"
        var lang = ""
        let lines = text.components(separatedBy: "\n")
        func flush() {
            if !para.isEmpty { out.append(.para(para.joined(separator: "\n"))); para = [] }
            if !quote.isEmpty { out.append(.quote(quote)); quote = [] }
        }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            i += 1
            if code != nil {
                // only a bare run of the same character, at least as long, closes: ```` can hold ``` and ```python is content
                if let run = fenceRun(t), run.first == fence.first, run.count >= fence.count, run.count == t.count { out.append(.code(lang, code!.joined(separator: "\n"))); code = nil } else { code!.append(line) }
                continue
            }
            if let run = fenceRun(t) {
                flush()
                fence = run
                code = []
                lang = String(t.dropFirst(run.count)).trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
                continue
            }
            if t.isEmpty { flush(); continue }
            if t.count >= 3, Set(t.replacingOccurrences(of: " ", with: "")).count == 1, "-*_".contains(t.first!) { flush(); out.append(.rule); continue }
            if t.hasPrefix("#"), let h = t.firstIndex(where: { $0 != "#" }), t[h] == " ", t.distance(from: t.startIndex, to: h) <= 6 {
                flush(); out.append(.heading(t.distance(from: t.startIndex, to: h), String(t[h...]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces))); continue
            }
            if t.hasPrefix(">") {
                if !para.isEmpty { out.append(.para(para.joined(separator: "\n"))); para = [] }
                quote.append(String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces)); continue
            }
            // a table: a row of cells, then a separator row of dashes
            if t.hasPrefix("|"), i < lines.count, isSeparator(lines[i]) {
                flush()
                let header = cells(t)
                let aligns = cells(lines[i]).map { c -> Part.Alignment in
                    let l = c.hasPrefix(":"), r = c.hasSuffix(":")
                    return l && r ? .center : r ? .right : .left
                }
                i += 1
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") { rows.append(cells(lines[i])); i += 1 }
                out.append(.table(header: header, aligns: aligns, rows: rows)); continue
            }
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let depth = indent / 2
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                flush()
                var body = String(t.dropFirst(2))
                var task: Bool? = nil
                if body.hasPrefix("[ ] ") { task = false; body = String(body.dropFirst(4)) }
                else if body.lowercased().hasPrefix("[x] ") { task = true; body = String(body.dropFirst(4)) }
                out.append(.item(mark: "•", depth: min(depth, 4), text: body, task: task)); continue
            }
            if let dot = t.firstIndex(where: { $0 == "." || $0 == ")" }), !t[..<dot].isEmpty, t[..<dot].allSatisfy(\.isNumber), t[t.index(after: dot)...].hasPrefix(" ") {
                flush(); out.append(.item(mark: String(t[..<dot]) + ".", depth: min(depth, 4), text: String(t[t.index(dot, offsetBy: 2)...]), task: nil)); continue
            }
            // a line that continues a list item
            if indent >= 2, case .item(let m, let d, let s, let task)? = out.last, para.isEmpty, quote.isEmpty {
                out[out.count - 1] = .item(mark: m, depth: d, text: s + "\n" + t, task: task); continue
            }
            if !quote.isEmpty { out.append(.quote(quote)); quote = [] }
            para.append(t)
        }
        if let code { out.append(.code(lang, code.joined(separator: "\n"))) }
        flush()
        return out
    }

    /// the backticks or tildes a code fence starts with, three or more of one kind; a backtick fence's info has no backticks
    static func fenceRun(_ t: String) -> String? {
        guard let c = t.first, c == "`" || c == "~" else { return nil }
        let run = t.prefix(while: { $0 == c })
        guard run.count >= 3, c == "~" || !t.dropFirst(run.count).contains("`") else { return nil }
        return String(run)
    }

    static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|"), t.contains("-") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }
    static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.replacingOccurrences(of: "\\|", with: "\u{1}").components(separatedBy: "|").map { $0.replacingOccurrences(of: "\u{1}", with: "|").trimmingCharacters(in: .whitespaces) }
    }
}

struct TableView: View {
    var header: [String]; var aligns: [Markdown.Part.Alignment]; var rows: [[String]]
    var inline: (String, CGFloat?, Font.Weight, Color) -> Text
    var body: some View {
        let cols = max(header.count, rows.map(\.count).max() ?? 0)
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<cols, id: \.self) { c in
                        cell(c < header.count ? header[c] : "", c, weight: .medium, color: Theme.ink).background(Color.white.opacity(0.04))
                    }
                }
                Rectangle().fill(Theme.line2).frame(height: 1).gridCellColumns(cols)
                ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                    GridRow {
                        ForEach(0..<cols, id: \.self) { c in cell(c < row.count ? row[c] : "", c, weight: .regular, color: Theme.ink2) }
                    }
                    if ri < rows.count - 1 { Rectangle().fill(Theme.line).frame(height: 1).gridCellColumns(cols) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.02)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
        }
    }
    func cell(_ s: String, _ c: Int, weight: Font.Weight, color: Color) -> some View {
        let a = c < aligns.count ? aligns[c] : .left
        return inline(s, 12.5, weight, color)
            .multilineTextAlignment(a == .center ? .center : a == .right ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: a == .center ? .center : a == .right ? .trailing : .leading)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .gridColumnAlignment(a == .center ? .center : a == .right ? .trailing : .leading)
    }
}

struct CodeBlock: View {
    var lang: String; var code: String
    @State private var copied = false
    @State private var hover = false
    var label: String {
        let k = Highlighter.kind(lang)
        if !lang.isEmpty { return lang.lowercased() }
        return k.isEmpty ? "text" : k
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label).font(Theme.mono(10.5)).foregroundStyle(Theme.dim)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                    copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 9.5, weight: .medium))
                        Text(copied ? "Copied" : "Copy").font(Theme.sans(11))
                    }
                    .foregroundStyle(copied ? Theme.green : Theme.mute)
                }
                .buttonStyle(Flat(pad: 5)).opacity(hover || copied ? 1 : 0.55)
            }
            .padding(.leading, 12).padding(.trailing, 6).frame(height: 30)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Highlighter.attributed(code, lang: lang, font: Theme.mono(12)))
                    .lineSpacing(3).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
        .onHover { hover = $0 }
    }
}
