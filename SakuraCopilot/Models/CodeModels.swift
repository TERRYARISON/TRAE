import Foundation
import SwiftData

// MARK: - 代码库

@Model
final class CodeProject {
    @Attribute(.unique) var id: UUID
    var name: String
    var descText: String
    var language: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CodeFile.project)
    var files: [CodeFile]

    init(id: UUID = UUID(), name: String, descText: String = "", language: String = "Swift") {
        self.id = id
        self.name = name
        self.descText = descText
        self.language = language
        self.createdAt = Date()
        self.updatedAt = Date()
        self.files = []
    }
}

@Model
final class CodeFile {
    @Attribute(.unique) var id: UUID
    var name: String
    var language: String
    @Attribute(.externalStorage) var content: String
    var updatedAt: Date
    var project: CodeProject?

    init(id: UUID = UUID(), name: String, language: String = "Swift", content: String = "") {
        self.id = id
        self.name = name
        self.language = language
        self.content = content
        self.updatedAt = Date()
        self.project = nil
    }
}

@Model
final class CodeSnippet {
    @Attribute(.unique) var id: UUID
    var title: String
    var language: String
    var code: String
    var createdAt: Date
    var updatedAt: Date

    @Attribute(.externalStorage) var tagsData: Data?

    init(id: UUID = UUID(), title: String, language: String = "Swift", code: String = "", tags: [String] = []) {
        self.id = id
        self.title = title
        self.language = language
        self.code = code
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tagsData = try? JSONEncoder().encode(tags)
    }

    var tags: [String] {
        get { (try? JSONDecoder().decode([String].self, from: tagsData ?? Data())) ?? [] }
        set { tagsData = try? JSONEncoder().encode(newValue); updatedAt = Date() }
    }
}
