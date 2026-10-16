import AppKit
import SwiftUI

/// regex colouring for the editor: keywords, strings, comments, numbers, types; enough to read code comfortably
enum Highlighter {
    struct Rule { let re: NSRegularExpression; let color: NSColor }
    static let base = NSColor(Color(hex: 0xd4d4d4))
    static let string = NSColor(Color(hex: 0xb5c9a3)), keyword = NSColor(Color(hex: 0xc3a6ff)), comment = NSColor(Color(hex: 0x6a6a6a)), number = NSColor(Color(hex: 0xe3b341)), type = NSColor(Color(hex: 0x8fc7d6)), punct = NSColor(Color(hex: 0x8a8a8a)), key = NSColor(Color(hex: 0x9fb8e8))
    static func rules(for ext: String) -> [Rule] {
        func r(_ p: String, _ c: NSColor, _ o: NSRegularExpression.Options = []) -> Rule? { (try? NSRegularExpression(pattern: p, options: o)).map { Rule(re: $0, color: c) } }
        switch ext {
        case "ts", "tsx", "js", "jsx", "mjs", "cjs":
            return [r(#"\b(import|export|from|default|const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|new|class|extends|implements|interface|type|enum|async|await|try|catch|finally|throw|typeof|instanceof|in|of|as|this|null|undefined|true|false|void|yield|static|readonly|public|private|protected|declare|namespace|keyof|satisfies)\b"#, keyword), r(#"\b[A-Z][A-Za-z0-9_]*\b"#, type), r(#"\b\d[\d_]*(\.\d+)?(e[+-]?\d+)?n?\b|\b0x[0-9a-fA-F_]+\b"#, number), r(#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`"#, string, [.dotMatchesLineSeparators]), r(#"//.*$"#, comment, [.anchorsMatchLines]), r(#"/\*[\s\S]*?\*/"#, comment)].compactMap { $0 }
        case "rs":
            return [r(#"\b(fn|let|mut|pub|use|mod|struct|enum|impl|trait|for|in|while|loop|if|else|match|return|where|as|ref|self|Self|super|crate|const|static|type|dyn|move|async|await|unsafe|true|false|break|continue)\b"#, keyword), r(#"#\[[^\]]*\]"#, key), r(#"\b[A-Z][A-Za-z0-9_]*\b"#, type), r(#"\b\d[\d_]*(\.\d+)?(u8|u16|u32|u64|u128|i8|i16|i32|i64|i128|usize|f32|f64)?\b"#, number), r(#""(?:[^"\\]|\\.)*""#, string, [.dotMatchesLineSeparators]), r(#"//.*$"#, comment, [.anchorsMatchLines]), r(#"/\*[\s\S]*?\*/"#, comment)].compactMap { $0 }
        case "json":
            return [r(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, key), r(#":\s*"(?:[^"\\]|\\.)*""#, string), r(#"\b-?\d+(\.\d+)?([eE][+-]?\d+)?\b"#, number), r(#"\b(true|false|null)\b"#, keyword)].compactMap { $0 }
        case "md":
            return [r(#"^#{1,6} .*$"#, type, [.anchorsMatchLines]), r(#"`[^`\n]+`"#, string), r(#"^```[\s\S]*?^```"#, string, [.anchorsMatchLines]), r(#"\*\*[^*]+\*\*"#, key), r(#"^\s*[-*] "#, punct, [.anchorsMatchLines]), r(#"\[[^\]]+\]\([^)]+\)"#, key)].compactMap { $0 }
        case "css", "scss":
            return [r(#"[.#]?[a-zA-Z_-][\w-]*(?=\s*\{)"#, type), r(#"[a-z-]+(?=\s*:)"#, key), r(#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#, string), r(#"\b\d+(\.\d+)?(px|em|rem|%|vh|vw|s|ms|deg)?\b|#[0-9a-fA-F]{3,8}\b"#, number), r(#"/\*[\s\S]*?\*/"#, comment)].compactMap { $0 }
        case "html", "htm", "svg", "xml":
            return [r(#"</?[a-zA-Z][\w:-]*|/?>"#, keyword), r(#"\b[a-zA-Z-]+(?==)"#, key), r(#""[^"]*"|'[^']*'"#, string), r(#"<!--[\s\S]*?-->"#, comment)].compactMap { $0 }
        case "toml", "yml", "yaml", "env":
            return [r(#"^\s*[\w.-]+(?=\s*[:=])"#, key, [.anchorsMatchLines]), r(#"^\[[^\]]+\]"#, type, [.anchorsMatchLines]), r(#""(?:[^"\\]|\\.)*"|'[^']*'"#, string), r(#"\b\d+(\.\d+)?\b"#, number), r(#"#.*$"#, comment, [.anchorsMatchLines])].compactMap { $0 }
        case "sh", "zsh", "bash":
            return [r(#"\b(if|then|else|fi|for|do|done|while|case|esac|function|export|local|return|echo|exit|set)\b"#, keyword), r(#"\$\{?[\w@#?]+\}?"#, key), r(#""(?:[^"\\]|\\.)*"|'[^']*'"#, string), r(#"#.*$"#, comment, [.anchorsMatchLines])].compactMap { $0 }
        case "swift", "py", "go":
            return [r(#"\b(func|let|var|struct|class|enum|protocol|extension|import|return|if|else|for|in|while|guard|switch|case|default|break|continue|def|async|await|try|catch|throw|throws|self|nil|None|true|false|True|False|pass|lambda|with|as|from|package|type|interface|map|range|go|defer|chan|select|const|static|private|public|override|init)\b"#, keyword), r(#"\b[A-Z][A-Za-z0-9_]*\b"#, type), r(#"\b\d[\d_]*(\.\d+)?\b"#, number), r(#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#, string), r(#"(//|#).*$"#, comment, [.anchorsMatchLines]), r(#"/\*[\s\S]*?\*/"#, comment)].compactMap { $0 }
        default: return []
        }
    }
    static func apply(_ storage: NSTextStorage, ext: String) {
        let text = storage.string as NSString
        guard text.length < 200_000 else { return }
        let full = NSRange(location: 0, length: text.length)
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.foregroundColor, value: base, range: full)
        for rule in rules(for: ext) { for m in rule.re.matches(in: storage.string, range: full) { storage.addAttribute(.foregroundColor, value: rule.color, range: m.range) } }
        storage.endEditing()
    }
}
