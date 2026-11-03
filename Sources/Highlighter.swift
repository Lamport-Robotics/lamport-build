import AppKit
import SwiftUI

/// regex colouring for code in answers, diffs and file previews: keywords, strings, comments, numbers, types; enough to read comfortably
enum Highlighter {
    struct Rule { let re: NSRegularExpression; let color: NSColor }
    static let base = NSColor(Theme.ink2)
    static let string = NSColor(Color(hex: 0xb5c9a3)), keyword = NSColor(Color(hex: 0xc3a6ff)), comment = NSColor(Color(hex: 0x6f6f6f)), number = NSColor(Color(hex: 0xe3b341)), type = NSColor(Color(hex: 0x8fc7d6)), punct = NSColor(Color(hex: 0x8a8a8a)), key = NSColor(Color(hex: 0x9fb8e8)), fn = NSColor(Color(hex: 0xe0c7a0))

    /// what a fence label or a file extension means
    static func kind(_ lang: String) -> String {
        switch lang.lowercased().trimmingCharacters(in: .whitespaces) {
        case "typescript", "ts", "tsx", "javascript", "js", "jsx", "mjs", "cjs", "node": return "ts"
        case "python", "py", "py3": return "py"
        case "rust", "rs": return "rs"
        case "go", "golang": return "go"
        case "swift": return "swift"
        case "bash", "sh", "shell", "zsh", "console", "terminal", "fish": return "sh"
        case "json", "jsonc", "json5": return "json"
        case "yaml", "yml": return "yaml"
        case "toml", "ini", "cfg", "env", "dotenv", "properties", "conf": return "toml"
        case "html", "htm", "xml", "svg", "vue", "svelte", "plist", "xhtml": return "html"
        case "css", "scss", "less": return "css"
        case "md", "markdown", "mdx": return "md"
        case "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "objc", "m", "mm", "java", "kt", "kotlin", "cs", "csharp", "scala", "dart": return "c"
        case "ruby", "rb", "php", "lua", "perl", "pl", "r": return "script"
        case "sql", "psql", "mysql": return "sql"
        case "diff", "patch": return "diff"
        case "make", "makefile", "docker", "dockerfile", "caddy", "nginx": return "toml"
        default: return ""
        }
    }

    private static var cache: [String: [Rule]] = [:]
    static func rules(for lang: String) -> [Rule] {
        let k = kind(lang)
        if let c = cache[k] { return c }
        let r = make(k)
        cache[k] = r
        return r
    }

    /// order matters: later rules paint over earlier ones, so strings and comments go last
    private static func make(_ k: String) -> [Rule] {
        func r(_ p: String, _ c: NSColor, _ o: NSRegularExpression.Options = []) -> Rule? { (try? NSRegularExpression(pattern: p, options: o)).map { Rule(re: $0, color: c) } }
        let call = r(#"\b[a-z_][A-Za-z0-9_]*(?=\()"#, fn)
        let typeName = r(#"\b[A-Z][A-Za-z0-9_]*\b"#, type)
        let num = r(#"\b\d[\d_]*(\.\d+)?([eE][+-]?\d+)?[a-zA-Z]*\b|\b0[xob][0-9a-fA-F_]+\b"#, number)
        let dq = r(#""(?:[^"\\\n]|\\.)*""#, string), sq = r(#"'(?:[^'\\\n]|\\.)*'"#, string), bq = r(#"`(?:[^`\\]|\\.)*`"#, string, [.dotMatchesLineSeparators])
        let slashLine = r(#"//.*$"#, comment, [.anchorsMatchLines]), hashLine = r(#"#.*$"#, comment, [.anchorsMatchLines]), block = r(#"/\*[\s\S]*?\*/"#, comment)
        switch k {
        case "ts":
            return [r(#"\b(import|export|from|default|const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|new|class|extends|implements|interface|type|enum|async|await|try|catch|finally|throw|typeof|instanceof|in|of|as|this|null|undefined|true|false|void|yield|static|readonly|public|private|protected|declare|namespace|keyof|satisfies|delete|super)\b"#, keyword), call, typeName, num, dq, sq, bq, slashLine, block].compactMap { $0 }
        case "py":
            return [r(#"\b(def|class|return|if|elif|else|for|while|in|not|and|or|is|import|from|as|with|try|except|finally|raise|pass|break|continue|lambda|yield|async|await|global|nonlocal|del|assert|None|True|False|self|match|case)\b"#, keyword), call, typeName, r(#"@\w+"#, key), num, r(#"[rbfu]*"""[\s\S]*?""""#, string), r(#"[rbfu]*'''[\s\S]*?'''"#, string), r(#"[rbfu]*"(?:[^"\\\n]|\\.)*""#, string), r(#"[rbfu]*'(?:[^'\\\n]|\\.)*'"#, string), hashLine].compactMap { $0 }
        case "rs":
            return [r(#"\b(fn|let|mut|pub|use|mod|struct|enum|impl|trait|for|in|while|loop|if|else|match|return|where|as|ref|self|Self|super|crate|const|static|type|dyn|move|async|await|unsafe|true|false|break|continue|extern|macro_rules)\b"#, keyword), r(#"#!?\[[^\]]*\]"#, key), r(#"\b\w+!(?=\()"#, fn), call, typeName, r(#"'[a-z_]+\b"#, key), num, dq, slashLine, block].compactMap { $0 }
        case "go":
            return [r(#"\b(package|import|func|return|if|else|for|range|switch|case|default|break|continue|go|defer|chan|select|const|var|type|struct|interface|map|nil|true|false|make|new|len|cap|append|error|string|int|int64|int32|float64|bool|byte|any)\b"#, keyword), call, typeName, num, dq, sq, bq, slashLine, block].compactMap { $0 }
        case "swift":
            return [r(#"\b(func|let|var|struct|class|enum|protocol|extension|import|return|if|else|for|in|while|guard|switch|case|default|break|continue|async|await|try|catch|throw|throws|self|Self|nil|true|false|as|is|where|some|any|static|private|public|internal|fileprivate|override|init|deinit|mutating|final|lazy|weak|unowned|inout|defer|repeat|do|typealias|associatedtype|subscript|convenience|required|indirect|rethrows|actor|nonisolated|isolated)\b"#, keyword), r(#"@\w+"#, key), r(#"#\w+"#, key), call, typeName, num, r(#"\"\"\"[\s\S]*?\"\"\""#, string), r(#""(?:[^"\\\n]|\\.)*""#, string), slashLine, block].compactMap { $0 }
        case "c":
            return [r(#"\b(if|else|for|while|do|switch|case|default|break|continue|return|goto|struct|union|enum|typedef|class|public|private|protected|virtual|override|static|const|constexpr|inline|extern|volatile|auto|new|delete|this|nullptr|null|true|false|void|int|char|short|long|unsigned|signed|float|double|bool|template|typename|namespace|using|try|catch|throw|import|package|interface|implements|extends|final|abstract|synchronized|instanceof|var|val|fun|when|object|data|sealed|lateinit|override|open|internal|suspend)\b"#, keyword), r(#"^\s*#\s*\w+"#, key, [.anchorsMatchLines]), r(#"@\w+"#, key), call, typeName, num, dq, sq, slashLine, block].compactMap { $0 }
        case "script":
            return [r(#"\b(def|end|if|elsif|else|unless|while|until|for|in|do|return|class|module|require|include|attr_accessor|self|nil|true|false|function|local|then|elseif|repeat|echo|foreach|as|use|namespace|public|private|protected|static|new|null|my|our|sub|print|and|or|not|yield|begin|rescue|ensure|lambda|library|NULL|TRUE|FALSE)\b"#, keyword), call, r(#"[$@]\w+"#, key), num, dq, sq, hashLine, slashLine, block].compactMap { $0 }
        case "sql":
            return [r(#"\b(select|from|where|insert|into|values|update|set|delete|create|table|index|drop|alter|add|primary|key|foreign|references|join|left|right|inner|outer|on|group|by|order|asc|desc|limit|offset|having|union|all|distinct|as|and|or|not|null|is|in|exists|between|like|case|when|then|else|end|begin|commit|rollback|with|returning|if|text|integer|real|blob|boolean|varchar|timestamp|default|unique|check|constraint)\b"#, keyword, [.caseInsensitive]), call, num, sq, dq, r(#"--.*$"#, comment, [.anchorsMatchLines]), block].compactMap { $0 }
        case "json":
            return [r(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, key), r(#":\s*"(?:[^"\\]|\\.)*""#, string), r(#"\b-?\d+(\.\d+)?([eE][+-]?\d+)?\b"#, number), r(#"\b(true|false|null)\b"#, keyword), slashLine].compactMap { $0 }
        case "yaml":
            return [r(#"^\s*-?\s*[\w.\-/]+(?=\s*:)"#, key, [.anchorsMatchLines]), r(#"\b(true|false|null|yes|no|on|off)\b"#, keyword), r(#"&\w+|\*\w+|!!\w+"#, type), num, dq, sq, hashLine].compactMap { $0 }
        case "toml":
            return [r(#"^\s*[\w.\-]+(?=\s*[:=])"#, key, [.anchorsMatchLines]), r(#"^\[[^\]]+\]"#, type, [.anchorsMatchLines]), r(#"\b(true|false|FROM|RUN|CMD|COPY|ADD|ENV|EXPOSE|WORKDIR|ENTRYPOINT|ARG|VOLUME|USER|LABEL)\b"#, keyword), r(#"\$\{?[\w@#?]+\}?"#, key), num, dq, sq, hashLine].compactMap { $0 }
        case "sh":
            return [r(#"\b(if|then|else|elif|fi|for|do|done|while|until|case|esac|in|function|export|local|return|echo|exit|set|source|alias|unset|shift|read|printf|test|cd|ls|cat|grep|sed|awk|curl|git|npm|pnpm|yarn|bun|node|python3?|pip|brew|sudo|rm|cp|mv|mkdir|chmod|chown|ssh|rsync|docker|make|cargo|go|swift|xcodebuild)\b"#, keyword), r(#"\$\{?[\w@#?*]+\}?|\$\(|\)"#, key), r(#"(?<=\s)--?[a-zA-Z][\w-]*"#, type), num, dq, sq, hashLine].compactMap { $0 }
        case "css":
            return [r(#"[.#]?[a-zA-Z_-][\w-]*(?=[^{}]*\{)"#, type), r(#"[a-z-]+(?=\s*:)"#, key), r(#"@[\w-]+"#, keyword), r(#"\b\d+(\.\d+)?(px|em|rem|%|vh|vw|s|ms|deg|fr)?\b|#[0-9a-fA-F]{3,8}\b"#, number), dq, sq, block].compactMap { $0 }
        case "html":
            return [r(#"</?[a-zA-Z][\w:.-]*|/?>"#, keyword), r(#"\b[a-zA-Z-:]+(?==)"#, key), r(#""[^"]*"|'[^']*'"#, string), r(#"<!--[\s\S]*?-->"#, comment)].compactMap { $0 }
        case "md":
            return [r(#"^#{1,6} .*$"#, type, [.anchorsMatchLines]), r(#"`[^`\n]+`"#, string), r(#"\*\*[^*\n]+\*\*"#, key), r(#"^\s*([-*+]|\d+\.) "#, punct, [.anchorsMatchLines]), r(#"\[[^\]\n]+\]\([^)\n]+\)"#, key), r(#"^>.*$"#, comment, [.anchorsMatchLines])].compactMap { $0 }
        case "diff":
            return [r(#"^\+.*$"#, NSColor(Theme.green), [.anchorsMatchLines]), r(#"^-.*$"#, NSColor(Theme.red), [.anchorsMatchLines]), r(#"^@@.*$"#, key, [.anchorsMatchLines]), r(#"^(diff|index|---|\+\+\+) .*$"#, comment, [.anchorsMatchLines])].compactMap { $0 }
        default: return []
        }
    }

    /// colour `code` as `lang`, ready for a SwiftUI Text; plain text comes back in the base colour when the language is unknown
    static func attributed(_ code: String, lang: String, font: Font? = nil) -> AttributedString {
        let ns = NSMutableAttributedString(string: code)
        let full = NSRange(location: 0, length: ns.length)
        ns.addAttribute(.foregroundColor, value: base, range: full)
        if ns.length < 120_000 {
            for rule in rules(for: lang) { for m in rule.re.matches(in: code, range: full) { ns.addAttribute(.foregroundColor, value: rule.color, range: m.range) } }
        }
        var out = AttributedString(ns)
        if let font { out.font = font }
        return out
    }

    /// the same colouring on an NSTextStorage, for the file preview
    static func apply(_ storage: NSTextStorage, lang: String) {
        let text = storage.string as NSString
        guard text.length < 300_000 else { return }
        let full = NSRange(location: 0, length: text.length)
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.foregroundColor, value: base, range: full)
        for rule in rules(for: lang) { for m in rule.re.matches(in: storage.string, range: full) { storage.addAttribute(.foregroundColor, value: rule.color, range: m.range) } }
        storage.endEditing()
    }
}
