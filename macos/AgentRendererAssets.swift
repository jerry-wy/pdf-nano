import Foundation

// Supply the renderer as an in-memory document. No file-origin script or font
// requests are needed, so App Translocation and WebKit file-origin policy cannot
// leave a partially loaded renderer that silently displays raw TeX.
struct AgentRendererAssets {
    let html: String
    let script: String

    init(directory: URL) throws {
        func read(_ path: String) throws -> String {
            try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
        }
        var css = try read("vendor/katex/katex.min.css")
        let sources = try NSRegularExpression(pattern: #"src:([^;}]+)"#)
        let woff2 = try NSRegularExpression(pattern: #"url\((fonts/[^)]+\.woff2)\)"#)
        let matches = sources.matches(in: css, range: NSRange(css.startIndex..., in: css))
        for match in matches.reversed() {
            let source = (css as NSString).substring(with: match.range)
            guard let font = woff2.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else {
                throw NSError(domain: "AgentRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "A bundled formula font is missing."])
            }
            let name = (source as NSString).substring(with: font.range(at: 1))
            let data = try Data(contentsOf: directory.appendingPathComponent("vendor/katex/" + name))
            let replacement = "src:url(data:font/woff2;base64,\(data.base64EncodedString())) format(\"woff2\")"
            css = (css as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        css += "\n" + (try read("reader.css"))
        html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; font-src data:; connect-src 'none'; img-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>\(css)</style></head><body><main id="messages" aria-label="Agent conversation"></main></body></html>
        """
        // WKUserScript is trusted application code, independent of the document's
        // CSP. Replies still enter only through structured arguments/text nodes.
        script = try ["vendor/katex/katex.min.js", "vendor/katex/copy-tex.min.js", "vendor/markdown-it/markdown-it.min.js", "math-renderer.js", "reader.js"]
            .map { try read($0) }.joined(separator: "\n;\n")
    }
}
