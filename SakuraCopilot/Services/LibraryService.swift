import Foundation
import SwiftData

// MARK: - 笔记 / 代码库轻量操作
@MainActor
enum NotesLib {

    static func allNotes(context: ModelContext) -> [Note] {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func note(id: UUID, context: ModelContext) -> Note? {
        var d = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func notebooks(context: ModelContext) -> [Notebook] {
        (try? context.fetch(FetchDescriptor<Notebook>())) ?? []
    }

    @discardableResult
    static func ensureNotebook(named name: String, context: ModelContext) -> Notebook {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let found = notebooks(context: context).first(where: { $0.name == trimmed }) {
            return found
        }
        let book = Notebook(name: trimmed.isEmpty ? "默认笔记本" : trimmed)
        context.insert(book)
        try? context.save()
        return book
    }

    @discardableResult
    static func create(title: String, content: String, notebookName: String?,
                       research: Bool = false, context: ModelContext) -> Note {
        var notebookID: UUID?
        if let name = notebookName, !name.isBlank {
            notebookID = ensureNotebook(named: name, context: context).id
        }
        let note = Note(title: title, content: content,
                        notebookID: notebookID, isResearchReport: research)
        context.insert(note)
        try? context.save()
        return note
    }

    static func append(_ note: Note, content: String) {
        note.content += (note.content.hasSuffix("\n") ? "" : "\n") + content
        note.updatedAt = Date()
    }

    static func delete(_ note: Note, context: ModelContext) {
        context.delete(note)
        try? context.save()
    }
}

@MainActor
enum CodeLib {

    static func projects(context: ModelContext) -> [CodeProject] {
        let d = FetchDescriptor<CodeProject>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    static func project(id: UUID, context: ModelContext) -> CodeProject? {
        var d = FetchDescriptor<CodeProject>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func snippets(context: ModelContext) -> [CodeSnippet] {
        (try? context.fetch(FetchDescriptor<CodeSnippet>())) ?? []
    }

    @discardableResult
    static func createProject(name: String, desc: String, language: String,
                              context: ModelContext) -> CodeProject {
        let project = CodeProject(name: name, descText: desc, language: language)
        context.insert(project)
        try? context.save()
        return project
    }

    static func file(project: CodeProject, path: String) -> CodeFile? {
        project.files.first { $0.name.lowercased() == path.lowercased() }
    }

    @discardableResult
    static func writeFile(project: CodeProject, path: String, content: String,
                          language: String?, context: ModelContext) -> CodeFile {
        if let existing = file(project: project, path: path) {
            existing.content = content
            existing.updatedAt = Date()
            try? context.save()
            return existing
        }
        let file = CodeFile(name: path, language: language ?? project.language, content: content)
        context.insert(file)
        file.project = project
        project.updatedAt = Date()
        try? context.save()
        return file
    }

    static func deleteFile(project: CodeProject, path: String, context: ModelContext) -> Bool {
        guard let file = file(project: project, path: path) else { return false }
        context.delete(file)
        try? context.save()
        return true
    }

    @discardableResult
    static func createSnippet(title: String, language: String, code: String,
                              context: ModelContext) -> CodeSnippet {
        let snippet = CodeSnippet(title: title, language: language, code: code)
        context.insert(snippet)
        try? context.save()
        return snippet
    }
}
