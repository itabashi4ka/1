import Foundation

/// HTMLテンプレートへの差し込み。
///
/// - `{{key}}` を値に置き換える（値はHTMLエスケープする）。未知のキーはそのまま残す。
/// - `<!-- ROW_START -->` 〜 `<!-- ROW_END -->` の間を1行分のひな形として、回数分複製する。
/// - `data-show="<section>"` を持つ要素は、そのセクションが非表示のとき要素ごと取り除く。
///   - `interest`: 利息を表示しないとき（`{{total_interest}}` も空にする）
///   - `bonus`: ボーナス払いが無いとき
public enum TemplateRenderer {
    public static let rowStartMarker = "<!-- ROW_START -->"
    public static let rowEndMarker = "<!-- ROW_END -->"

    public static func render(_ template: String, context: TemplateContext) -> String {
        var html = template
        for section in context.hiddenSections.sorted() {
            html = removeElements(showing: section, in: html)
        }
        html = expandRows(in: html, rows: context.rows)
        return replacePlaceholders(in: html, values: context.values)
    }

    // MARK: - 繰り返し行

    static func expandRows(in html: String, rows: [[String: String]]) -> String {
        var output = ""
        var rest = Substring(html)
        while let start = rest.range(of: rowStartMarker),
              let end = rest.range(of: rowEndMarker, range: start.upperBound..<rest.endIndex) {
            output += rest[..<start.lowerBound]
            let rowTemplate = String(rest[start.upperBound..<end.lowerBound])
            for row in rows {
                output += replacePlaceholders(in: rowTemplate, values: row)
            }
            rest = rest[end.upperBound...]
        }
        output += rest
        return output
    }

    // MARK: - プレースホルダー

    static func replacePlaceholders(in html: String, values: [String: String]) -> String {
        var output = ""
        var rest = Substring(html)
        while let open = rest.range(of: "{{"),
              let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            output += rest[..<open.lowerBound]
            let key = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if let value = values[key] {
                output += escapeHTML(value)
            } else {
                output += rest[open.lowerBound..<close.upperBound]
            }
            rest = rest[close.upperBound...]
        }
        output += rest
        return output
    }

    public static func escapeHTML(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: - 要素の除去

    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr",
    ]

    /// `data-show="<section>"` を持つ要素を、閉じタグまで含めて取り除く。
    static func removeElements(showing section: String, in html: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: section)
        let pattern = #"<([A-Za-z][A-Za-z0-9-]*)\b[^>]*\bdata-show\s*=\s*["']"# + escaped + #"["'][^>]*>"#
        guard let openTag = try? NSRegularExpression(pattern: pattern) else { return html }

        var result = html
        var searchFrom = 0
        while true {
            let ns = result as NSString
            guard let match = openTag.firstMatch(in: result, range: NSRange(location: searchFrom, length: ns.length - searchFrom)) else {
                break
            }
            let tagName = ns.substring(with: match.range(at: 1)).lowercased()
            let openText = ns.substring(with: match.range)
            var removeEnd = match.range.location + match.range.length
            if !openText.hasSuffix("/>"), !voidElements.contains(tagName),
               let closeEnd = findClosingTag(tagName, in: ns, from: removeEnd) {
                removeEnd = closeEnd
            }
            result = ns.replacingCharacters(in: NSRange(location: match.range.location,
                                                        length: removeEnd - match.range.location), with: "")
            searchFrom = match.range.location
        }
        return result
    }

    /// 入れ子を数えながら対応する閉じタグを探し、その終端位置を返す。
    private static func findClosingTag(_ tagName: String, in html: NSString, from start: Int) -> Int? {
        let name = NSRegularExpression.escapedPattern(for: tagName)
        guard let regex = try? NSRegularExpression(pattern: "<(/?)" + name + #"\b[^>]*?(/?)>"#,
                                                   options: [.caseInsensitive]) else { return nil }
        var depth = 1
        for match in regex.matches(in: html as String, range: NSRange(location: start, length: html.length - start)) {
            let isClose = match.range(at: 1).length > 0
            let isSelfClosing = match.range(at: 2).length > 0
            if isClose {
                depth -= 1
                if depth == 0 { return match.range.location + match.range.length }
            } else if !isSelfClosing {
                depth += 1
            }
        }
        return nil
    }
}
