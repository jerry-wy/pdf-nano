import Foundation

@main struct ChatHistoryTests {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pdfnano-history-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("support/history.json")
        let store = ChatHistoryStore(url: url)
        var chat = ChatThread(documentID: "pdf:one", documentTitle: "One.pdf")
        chat.messages = [ChatEntry(role: "user", text: "解释这一段\nplease", pages: "3", model: "test-model"),
                         ChatEntry(role: "assistant", text: "A saved answer [p. 3]", pages: "3", model: "test-model")]
        try store.save(chat)
        let restored = ChatHistoryStore(url: url)
        let record = restored.records(for: "pdf:one").first!
        check(record.id == chat.id && record.messages.count == 2 && record.messages[0].model == "test-model",
              "Chat messages and model survive reloading from disk")
        check(record.title == "解释这一段 please" && record.turns.first?.answer == "A saved answer [p. 3]",
              "Unicode titles and question-answer context restore correctly")
        var other = ChatThread(documentID: "pdf:two", documentTitle: "Two.pdf")
        other.messages = [ChatEntry(role: "user", text: "Other PDF")]
        try restored.save(other)
        check(restored.records(for: "pdf:one").count == 1 && restored.records(for: "pdf:two").count == 1,
              "History is isolated by PDF")
        var continued = record
        continued.messages.append(ChatEntry(role: "user", text: "Follow up", pages: "4"))
        continued.messages.append(ChatEntry(role: "assistant", text: "More detail", pages: "4"))
        continued.updatedAt = Date()
        try restored.save(continued); try restored.save(continued)
        check(restored.records(for: "pdf:one").first?.messages.count == 4,
              "Continuing and saving a chat does not duplicate its messages")
        var secondWindow = record
        secondWindow.messages.append(ChatEntry(role: "user", text: "Another window", pages: "4"))
        try restored.save(secondWindow)
        check(restored.records(for: "pdf:one").first?.messages.count == 5,
              "A stale window cannot overwrite newly saved messages")
        try restored.delete(chat.id)
        do { try restored.save(chat); check(false, "A deleted chat must not be recreated by a stale window") }
        catch { check(restored.wasDeleted(chat.id), "Stale windows cannot resurrect deleted history") }
        let afterDelete = ChatHistoryStore(url: url)
        check(afterDelete.records(for: "pdf:one").isEmpty && afterDelete.records(for: "pdf:two").count == 1,
              "Deletion persists after reload and preserves other conversations")
        var unsaved = ChatThread(documentID: "untitled:one", documentTitle: "Untitled")
        unsaved.messages = [ChatEntry(role: "user", text: "Before saving")]
        try afterDelete.save(unsaved)
        try afterDelete.migrate(from: "untitled:one", to: "file:saved.pdf", title: "Saved.pdf")
        check(afterDelete.records(for: "untitled:one").isEmpty && afterDelete.records(for: "file:saved.pdf").first?.id == unsaved.id,
              "Saving an untitled PDF retains its conversation history")
        var interrupted = ChatThread(documentID: "pdf:one", documentTitle: "One.pdf")
        interrupted.messages = [ChatEntry(role: "user", text: "Failed"), ChatEntry(role: "error", text: "Stopped"),
                                ChatEntry(role: "user", text: "Retry"), ChatEntry(role: "assistant", text: "Success")]
        check(interrupted.turns.count == 1 && interrupted.turns[0].question == "Retry",
              "Failed answers are excluded from restored conversation context")
        let brokenURL = root.appendingPathComponent("broken.json")
        let broken = Data("unreadable original history".utf8)
        try broken.write(to: brokenURL)
        let damaged = ChatHistoryStore(url: brokenURL)
        check(damaged.loadError != nil, "Corrupt history produces a recoverable load error")
        do { try damaged.save(chat); check(false, "Corrupt history must not be overwritten") }
        catch { check(try Data(contentsOf: brokenURL) == broken, "Original corrupt history remains intact") }
        let fileParent = root.appendingPathComponent("not-a-directory")
        try Data().write(to: fileParent)
        let failing = ChatHistoryStore(url: fileParent.appendingPathComponent("history.json"))
        do { try failing.save(chat); check(false, "Expected write failure") }
        catch { check(failing.records(for: "pdf:one").isEmpty, "Failed writes do not falsely commit history") }
    }
}
