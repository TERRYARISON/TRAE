import Foundation
import SwiftData

// MARK: - 笔记

@Model
final class Notebook {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, icon: String = "📗") {
        self.id = id
        self.name = name
        self.icon = icon
        self.createdAt = Date()
    }
}

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    @Attribute(.externalStorage) var content: String
    var notebookID: UUID?
    var pinned: Bool
    var isResearchReport: Bool
    var createdAt: Date
    var updatedAt: Date

    @Attribute(.externalStorage) var tagsData: Data?

    init(id: UUID = UUID(), title: String, content: String = "",
         notebookID: UUID? = nil, pinned: Bool = false,
         isResearchReport: Bool = false, tags: [String] = []) {
        self.id = id
        self.title = title
        self.content = content
        self.notebookID = notebookID
        self.pinned = pinned
        self.isResearchReport = isResearchReport
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tagsData = try? JSONEncoder().encode(tags)
    }

    var tags: [String] {
        get { (try? JSONDecoder().decode([String].self, from: tagsData ?? Data())) ?? [] }
        set { tagsData = try? JSONEncoder().encode(newValue); updatedAt = Date() }
    }
}
