import Foundation
import SwiftData

// MARK: - 对话 / 消息

@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var modelKey: String?
    var reasoningLevel: Int
    var webSearch: Bool
    var deepResearch: Bool
    var pinned: Bool

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(id: UUID = UUID(), title: String = "新对话",
         modelKey: String? = nil, reasoningLevel: Int = 0,
         webSearch: Bool = false, deepResearch: Bool = false, pinned: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelKey = modelKey
        self.reasoningLevel = reasoningLevel
        self.webSearch = webSearch
        self.deepResearch = deepResearch
        self.pinned = pinned
        self.messages = []
    }

    var visibleMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}

enum MessageRole: String, Codable { case user, assistant, system, tool }
enum MessageKind: String, Codable { case text, task, summary, pending, error }

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var kindRaw: String
    var content: String
    var reasoning: String?
    var createdAt: Date
    var compressedOut: Bool

    @Attribute(.externalStorage) var attachmentsData: Data?
    @Attribute(.externalStorage) var citationsData: Data?
    @Attribute(.externalStorage) var toolTraceData: Data?
    @Attribute(.externalStorage) var archivedData: Data?
    @Attribute(.externalStorage) var pendingData: Data?
    @Attribute(.externalStorage) var skillsData: Data?

    var taskID: UUID?

    var conversation: Conversation?

    init(id: UUID = UUID(), role: MessageRole, kind: MessageKind = .text,
         content: String, reasoning: String? = nil, taskID: UUID? = nil) {
        self.id = id
        self.roleRaw = role.rawValue
        self.kindRaw = kind.rawValue
        self.content = content
        self.reasoning = reasoning
        self.createdAt = Date()
        self.compressedOut = false
        self.taskID = taskID
        self.conversation = nil
    }

    var role: MessageRole { MessageRole(rawValue: roleRaw) ?? .assistant }
    var kind: MessageKind { MessageKind(rawValue: kindRaw) ?? .text }

    var attachments: [AttachmentRef] {
        get { Self.decode(attachmentsData) ?? [] }
        set { attachmentsData = Self.encode(newValue) }
    }
    var citations: [Citation] {
        get { Self.decode(citationsData) ?? [] }
        set { citationsData = Self.encode(newValue) }
    }
    var toolTrace: [String] {
        get { Self.decode(toolTraceData) ?? [] }
        set { toolTraceData = Self.encode(newValue) }
    }
    var archived: [ArchivedMessage] {
        get { Self.decode(archivedData) ?? [] }
        set { archivedData = Self.encode(newValue) }
    }
    var pending: PendingAction? {
        get { Self.decode(pendingData) }
        set { pendingData = Self.encode(newValue) }
    }
    var appliedSkills: [String] {
        get { Self.decode(skillsData) ?? [] }
        set { skillsData = Self.encode(newValue) }
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }
}

// MARK: - 传输结构

struct AttachmentRef: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: String          // text / image / file
    var textContent: String?

    static func text(_ name: String, _ content: String) -> AttachmentRef {
        AttachmentRef(name: name, kind: "text", textContent: content)
    }
}

struct Citation: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var snippet: String
    var kind: String          // knowledge / note / web / code / artifact
    var itemID: String
    var url: String?
    var chunkIndex: Int = 0
}

struct PendingAction: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var toolName: String
    var argumentsJSON: String
    var createdAt: Date = Date()
}

struct ArchivedMessage: Codable, Identifiable, Hashable {
    var id: UUID
    var role: String
    var content: String
    var createdAt: Date
}
