import Foundation

struct ChatEntry: Codable, Identifiable {
    let id: UUID
    let role: String
    let text: String
    let pages: String
    let model: String?
    let createdAt: Date
    init(role: String, text: String, pages: String = "", model: String? = nil) {
        id = UUID(); self.role = role; self.text = text; self.pages = pages
        self.model = model; createdAt = Date()
    }
}

struct ChatThread: Codable, Identifiable {
    let id: UUID
    var documentID: String
    var documentTitle: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatEntry]
    init(documentID: String, documentTitle: String) {
        id = UUID(); self.documentID = documentID; self.documentTitle = documentTitle
        createdAt = Date(); updatedAt = createdAt; messages = []
    }
    var title: String {
        String((messages.first(where: { $0.role == "user" })?.text ?? "New chat")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(100))
    }
    var turns: [AgentTurn] {
        var result: [AgentTurn] = [], question: ChatEntry?
        for message in messages {
            if message.role == "user" { question = message }
            else if message.role == "assistant", let previous = question {
                result.append(AgentTurn(question: previous.text, answer: message.text, pages: previous.pages)); question = nil
            } else if message.role == "error" { question = nil }
        }
        return result
    }
}

// Shared by document windows on the main thread. Commit only after an atomic
// write succeeds; an unreadable existing store must never be silently replaced.
final class ChatHistoryStore {
    static let shared = ChatHistoryStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PDF Nano/ChatHistory.json"))
    private let url: URL
    private var threads: [ChatThread] = []
    private var deletedIDs = Set<UUID>()
    private(set) var loadError: Error?
    init(url: URL) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                threads = try JSONDecoder().decode([ChatThread].self, from: Data(contentsOf: url))
            }
        } catch { loadError = error }
    }
    func records(for documentID: String) -> [ChatThread] {
        threads.filter { $0.documentID == documentID }.sorted { $0.updatedAt > $1.updatedAt }
    }
    func wasDeleted(_ id: UUID) -> Bool { deletedIDs.contains(id) }
    func save(_ thread: ChatThread) throws {
        guard !deletedIDs.contains(thread.id) else {
            throw NSError(domain: "PDFNanoChatHistory", code: 1, userInfo: [NSLocalizedDescriptionKey: "This conversation was deleted."])
        }
        var next = threads
        if let index = next.firstIndex(where: { $0.id == thread.id }) {
            var merged = thread
            let known = Set(thread.messages.map(\.id))
            merged.messages += next[index].messages.filter { !known.contains($0.id) }
            merged.messages.sort { $0.createdAt < $1.createdAt }
            merged.updatedAt = max(thread.updatedAt, next[index].updatedAt, merged.messages.last?.createdAt ?? thread.updatedAt)
            next[index] = merged
        } else { next.append(thread) }
        try commit(next)
    }
    func delete(_ id: UUID) throws {
        try commit(threads.filter { $0.id != id }); deletedIDs.insert(id)
    }
    func migrate(from oldID: String, to newID: String, title: String) throws {
        let updated = threads.map { thread -> ChatThread in
            var thread = thread
            if thread.documentID == oldID { thread.documentID = newID; thread.documentTitle = title }
            return thread
        }
        try commit(updated)
    }
    private func commit(_ next: [ChatThread]) throws {
        if let loadError { throw loadError }
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        threads = next
        // The parent directory is private even if changing file attributes fails.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
