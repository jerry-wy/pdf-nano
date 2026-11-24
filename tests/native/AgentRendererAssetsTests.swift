import Foundation
import JavaScriptCore

@main struct AgentRendererAssetsTests {
    static func check(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func main() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("macos/AgentRenderer")
        let assets = try AgentRendererAssets(directory: directory)
        check(assets.html.components(separatedBy: "data:font/woff2;base64,").count - 1 == 20,
              "All 20 math fonts are embedded in the in-memory document")
        check(!assets.html.contains("url(fonts/") && !assets.html.contains("<script") && !assets.html.contains("<link"),
              "Initial rendering does not depend on file-origin script, stylesheet or font requests")
        let context = JSContext()!
        var exceptions: [String] = []
        context.exceptionHandler = { _, error in exceptions.append(error?.toString() ?? "Unknown script error") }
        // Exercise the exact packaged bootstrap and bridge contract without a
        // GUI. Timers and ResizeObserver intentionally do not run before render.
        context.evaluateScript(#"""
        var window = globalThis, timers = [], reports = [];
        function Element(tag) { this.tag = tag; this.children = []; this.style = {setProperty(){}}; }
        Element.prototype.append = function (...items) { this.children.push(...items); };
        Element.prototype.replaceChildren = function (fragment) { this.children = fragment.children; };
        Element.prototype.setAttribute = function () {};
        Element.prototype.getBoundingClientRect = function () { return {height: 100}; };
        var conversation = new Element('main');
        var document = {
          compatMode:'CSS1Compat', documentElement:new Element('html'),
          getElementById(){return conversation;}, addEventListener(){},
          createElement(tag){return new Element(tag);}, createDocumentFragment(){return new Element('fragment');},
          fonts:{ready:{then(callback){timers.push(callback);}}}
        };
        var console = {warn(){}, log(){}, error(){}};
        function setTimeout(callback) { timers.push(callback); }
        function ResizeObserver(callback) { this.observe = function () {}; }
        window.webkit = {messageHandlers:{readerHeight:{postMessage(value){reports.push(value);}}}};
        """#)
        context.evaluateScript(assets.script)
        check(exceptions.isEmpty, "Bundled engine, copy support and reader bridge initialize together")
        let value = context.evaluateScript(#"""
        window.readerRender([
          {isUser:true, text:'A short question'},
          {isUser:false, text:'The mean is \\(\\frac{1}{n}\\sum_i x_i\\).'}
        ], {dark:false,ink:'#222',muted:'#777',bubble:'#eee'}, 7)
        """#)?.toDictionary()
        check(exceptions.isEmpty, "The native render entry point completes without a script error")
        check(value?["revision"] as? Int == 7 && value?["count"] as? Int == 2 && value?["height"] as? Int == 108,
              "First render returns usable dimensions before timers or resize notifications run")
        check(context.evaluateScript("reports.length")?.toInt32() == 0,
              "First presentation no longer depends on a hidden-view message callback")
        check(context.evaluateScript("conversation.children[1].children[1].innerHTML.includes('class=\"katex\"')")?.toBool() == true,
              "LaTeX actually reaches the typesetter through the packaged reader bridge")
        context.evaluateScript("while (timers.length) timers.shift()();")
        check(context.evaluateScript("reports.length > 0 && reports[reports.length-1].revision === 7")?.toBool() == true,
              "Later font and resize updates still report the current render revision")
        do {
            _ = try AgentRendererAssets(directory: directory.appendingPathComponent("missing"))
            check(false, "Missing assets must be reported")
        } catch { check(true, "Missing resources fail explicitly instead of producing a half-loaded page") }
    }
}
