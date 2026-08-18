import Foundation
import SwiftData

// MARK: - 知识库

@Model
final class KnowledgeItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var folder: String?
    var kindRaw: String            // doc / digest / web
    @Attribute(.externalStorage) var textContent: String
    var charCount: Int
    var createdAt: Date
    var updatedAt: Date

    @Attribute(.externalStorage) var tagsData: Data?

    init(id: UUID = UUID(), title: String, folder: String? = nil,
         kind: String = "doc", textContent: String = "", tags: [String] = []) {
        self.id = id
        self.title = title
        self.folder = folder
        self.kindRaw = kind
        self.textContent = textContent
        self.charCount = textContent.count
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tagsData = try? JSONEncoder().encode(tags)
    }

    var tags: [String] {
        get { (try? JSONDecoder().decode([String].self, from: tagsData ?? Data())) ?? [] }
        set { tagsData = try? JSONEncoder().encode(newValue); updatedAt = Date() }
    }

    var kind: String { kindRaw }
}
