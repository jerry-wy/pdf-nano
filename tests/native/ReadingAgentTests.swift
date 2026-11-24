import Foundation

@main struct ReadingAgentTests {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func response(_ action: String, answer: String = "", pages: [Int] = [], query: String = "", offset: Int = 0) -> String {
        let object: [String: Any] = ["action": action, "answer": answer, "pages": pages, "query": query, "offset": offset]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    static func main() {
        let catalog: [[String: Any]] = [
            ["slug": "second", "priority": 2], ["slug": "hidden", "priority": 0, "visibility": "hide"],
            ["slug": "first", "priority": 1], ["slug": "second", "priority": 3]
        ]
        check(CodexModels.orderedIDs(catalog) == ["first", "second"], "Default resolves to the highest-priority visible model without duplicates")
        check(CodexModels.orderedIDs(catalog + [["slug": "explicit", "priority": 9, "is_default": true]]).first == "explicit",
              "An explicit catalog default takes precedence")
        var reads: [Int] = [], calls = 0, result: Result<String, Error>?
        let direct = ReadingAgent(pageCount: 20, currentPage: 4, question: "Explain this", history: [], model: "chosen-model",
            pageText: { reads.append($0); return "Enough information" }, request: { prompt, model, callback in
                calls += 1; check(model == "chosen-model", "Selected model reaches request")
                callback(.success(response("answer", answer: "Answer [p. 4]")))
            }, cancel: {})
        direct.start { result = $0 }
        check(reads == [4] && calls == 1 && (try? result?.get()) == "Answer [p. 4]", "Sufficient context answers in one call without reading neighbors")

        reads = []; calls = 0; result = nil
        let targeted = ReadingAgent(pageCount: 20, currentPage: 4, question: "Compare page nine", history: [], model: nil,
            pageText: { reads.append($0); return "Page \($0) source" }, request: { prompt, _, callback in
                calls += 1
                if calls == 1 { callback(.success(response("read_pages", pages: [9]))) }
                else {
                    check(prompt.contains("Page 9 source") && !prompt.contains("Page 5 source"), "Only requested page text is added")
                    callback(.success(response("answer", answer: "Compared [p. 9]")))
                }
            }, cancel: {})
        targeted.start { result = $0 }
        check(reads == [4, 9] && calls == 2, "Model controls targeted expansion")

        reads = []; calls = 0; result = nil
        let search = ReadingAgent(pageCount: 3, currentPage: 1, question: "Find detail", history: [], model: nil,
            pageText: { reads.append($0); return $0 == 3 ? String(repeating: "x", count: 2000) + "needle detail" : "Irrelevant" }, request: { prompt, _, callback in
                calls += 1
                if calls == 1 { callback(.success(response("search", query: "needle"))) }
                else {
                    check(prompt.contains("needle detail") && !prompt.contains(String(repeating: "x", count: 1000)), "Search sends bounded excerpts rather than full pages")
                    callback(.success(response("answer", answer: "Found [p. 3]")))
                }
            }, cancel: {})
        search.start { result = $0 }
        check(calls == 2 && result != nil, "Requested local search completes")

        calls = 0; result = nil
        let bounded = ReadingAgent(pageCount: 1, currentPage: 1, question: "Read forever", history: [], model: nil,
            pageText: { _ in "source" }, request: { _, _, callback in
                calls += 1; callback(.success(response("read_pages", pages: [-1, 99, 1])))
            }, cancel: {})
        bounded.start { result = $0 }
        if case .failure = result { check(calls == 7, "Invalid or repeated requests cannot trigger unbounded retrieval") }
        else { check(false, "Reading limit enforced") }

        calls = 0; result = nil
        let scanned = ReadingAgent(pageCount: 1, currentPage: 1, question: "What is entropy?", history: [], model: nil,
            pageText: { _ in "" }, request: { _, _, callback in calls += 1; callback(.success(response("answer", answer: "A general explanation"))) }, cancel: {})
        scanned.start { result = $0 }
        check(calls == 1 && (try? result?.get()) == "A general explanation", "General questions are not blocked by a scanned page")

        var pending: ((Result<String, Error>) -> Void)?
        result = nil
        let cancelled = ReadingAgent(pageCount: 2, currentPage: 1, question: "Stop", history: [], model: nil,
            pageText: { _ in "source" }, request: { _, _, callback in pending = callback }, cancel: {})
        cancelled.start { result = $0 }; cancelled.cancel()
        check(result == nil, "Cancellation waits for active transport to finish")
        pending?(.success(response("read_pages", pages: [2])))
        if case .failure(let error) = result { check(error.localizedDescription.contains("Stopped"), "Cancelled response cannot start another page request") }
        else { check(false, "Cancellation reported") }
    }
}
