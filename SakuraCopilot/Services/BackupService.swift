import Foundation
import SwiftData
import CryptoKit

// MARK: - 全量备份 / 恢复（JSON 单文件，密钥可选加密导出）
@MainActor
final class BackupService {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: 快照结构
    struct Bundle: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var conversations: [Conv] = []
        var knowledge: [Knowledge] = []
        var notes: [NoteS] = []
        var codeProjects: [Project] = []
        var codeSnippets: [Snippet] = []
        var skills: [SkillS] = []
        var memoryPersona: String = ""
        var memoryEntries: [MemoryS] = []
        var providers: [ProviderS] = []
        var tasks: [TaskS] = []
        var artifacts: [ArtifactS] = []

        struct Conv: Codable {
            var title: String; var createdAt: Date; var updatedAt: Date
            var modelKey: String?; var reasoningLevel: Int; var webSearch: Bool; var deepResearch: Bool; var pinned: Bool
            var messages: [Msg] = []
            struct Msg: Codable {
                var role: String; var kind: String; var content: String; var reasoning: String?
                var createdAt: Date; var citations: [Cit] = []; var trace: [String] = []
                var archived: [Arch] = []; var taskID: String?
                struct Cit: Codable { var id: Int; var title: String; var snippet: String; var kind: String; var itemID: String; var url: String?; var chunkIndex: Int }
                struct Arch: Codable { var id: String; var role: String; var content: String; var createdAt: Date }
            }
        }
        struct Knowledge: Codable { var title: String; var folder: String?; var kind: String; var text: String; var tags: [String]; var createdAt: Date; var updatedAt: Date }
        struct NoteS: Codable { var title: String; var content: String; var notebookID: String?; var research: Bool; var pinned: Bool; var tags: [String]; var createdAt: Date; var updatedAt: Date }
        struct Project: Codable { var name: String; var desc: String; var language: String; var files: [File] = []
            struct File: Codable { var name: String; var language: String; var content: String } }
        struct Snippet: Codable { var title: String; var language: String; var code: String; var tags: [String] }
        struct SkillS: Codable { var name: String; var desc: String; var triggers: [String]; var prompt: String; var steps: [String]; var enabled: Bool; var isBuiltin: Bool }
        struct MemoryS: Codable { var kind: String; var content: String; var createdAt: Date }
        struct ProviderS: Codable { var name: String; var baseURL: String; var isLocal: Bool; var models: [ModelInfo]; var keyEncryptedBase64: String? }
        struct TaskS: Codable { var title: String; var goal: String; var state: String; var percent: Double; var isResearch: Bool; var plan: TaskPlan? }
        struct ArtifactS: Codable { var taskID: String; var name: String; var text: String }
    }

    // MARK: 导出
    func export(includeKeys: Bool, passphrase: String) throws -> URL {
        var bundle = Bundle()

        for conv in (try? context.fetch(FetchDescriptor<Conversation>())) ?? [] {
            var msgs: [Bundle.Conv.Msg] = []
            for m in conv.visibleMessages {
                msgs.append(.init(role: m.roleRaw, kind: m.kindRaw, content: m.content,
                                  reasoning: m.reasoning, createdAt: m.createdAt,
                                  citations: m.citations.map { .init(id: $0.id, title: $0.title, snippet: $0.snippet, kind: $0.kind, itemID: $0.itemID, url: $0.url, chunkIndex: $0.chunkIndex) },
                                  trace: m.toolTrace,
                                  archived: m.archived.map { .init(id: $0.id.uuidString, role: $0.role, content: $0.content, createdAt: $0.createdAt) },
                                  taskID: m.taskID?.uuidString))
            }
            bundle.conversations.append(.init(title: conv.title, createdAt: conv.createdAt, updatedAt: conv.updatedAt,
                                              modelKey: conv.modelKey, reasoningLevel: conv.reasoningLevel,
                                              webSearch: conv.webSearch, deepResearch: conv.deepResearch, pinned: conv.pinned,
                                              messages: msgs))
        }
        for item in (try? context.fetch(FetchDescriptor<KnowledgeItem>())) ?? [] {
            bundle.knowledge.append(.init(title: item.title, folder: item.folder, kind: item.kindRaw,
                                          text: item.textContent, tags: item.tags,
                                          createdAt: item.createdAt, updatedAt: item.updatedAt))
        }
        for note in (try? context.fetch(FetchDescriptor<Note>())) ?? [] {
            bundle.notes.append(.init(title: note.title, content: note.content,
                                      notebookID: note.notebookID?.uuidString, research: note.isResearchReport,
                                      pinned: note.pinned, tags: note.tags,
                                      createdAt: note.createdAt, updatedAt: note.updatedAt))
        }
        for project in (try? context.fetch(FetchDescriptor<CodeProject>())) ?? [] {
            bundle.codeProjects.append(.init(name: project.name, desc: project.descText,
                                             language: project.language,
                                             files: project.files.map { .init(name: $0.name, language: $0.language, content: $0.content) }))
        }
        for s in (try? context.fetch(FetchDescriptor<CodeSnippet>())) ?? [] {
            bundle.codeSnippets.append(.init(title: s.title, language: s.language, code: s.code, tags: s.tags))
        }
        for skill in (try? context.fetch(FetchDescriptor<Skill>())) ?? [] {
            bundle.skills.append(.init(name: skill.name, desc: skill.descText, triggers: skill.triggers,
                                       prompt: skill.promptTemplate, steps: skill.steps,
                                       enabled: skill.enabled, isBuiltin: skill.isBuiltin))
        }
        if let persona = (try? context.fetch(FetchDescriptor<MemoryCard>()))?.first(where: { $0.kindRaw == MemoryCardKind.persona.rawValue }) {
            bundle.memoryPersona = persona.personaText ?? ""
        }
        for entry in (try? context.fetch(FetchDescriptor<MemoryEntry>())) ?? [] {
            bundle.memoryEntries.append(.init(kind: entry.card?.kindRaw ?? "", content: entry.content, createdAt: entry.createdAt))
        }
        for provider in (try? context.fetch(FetchDescriptor<LLMProviderEntity>())) ?? [] {
            var keyEncrypted: String?
            if includeKeys, !passphrase.isEmpty, !provider.apiKey.isEmpty {
                keyEncrypted = Self.encrypt(provider.apiKey, passphrase: passphrase)
            }
            bundle.providers.append(.init(name: provider.name, baseURL: provider.baseURL,
                                          isLocal: provider.isLocal, models: provider.models,
                                          keyEncrypted: keyEncrypted))
        }
        for task in (try? context.fetch(FetchDescriptor<GiantTask>())) ?? [] {
            bundle.tasks.append(.init(title: task.title, goal: task.goal, state: task.stateRaw,
                                      percent: task.percent, isResearch: task.isResearch, plan: task.plan))
            for a in GiantTaskEngine.artifactTexts(taskID: task.id) {
                bundle.artifacts.append(.init(taskID: task.id.uuidString, name: a.name, text: a.text))
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bundle)
        let name = "樱花副驾备份-\(Self.stamp()).json"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: 恢复（覆盖全部本地数据，调用前 UI 必须二次确认）
    func restore(from url: URL, passphrase: String) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            throw NSError(domain: "backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取备份文件"])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(Bundle.self, from: data) else {
            throw NSError(domain: "backup", code: 2, userInfo: [NSLocalizedDescriptionKey: "备份文件格式不正确"])
        }

        // 清空
        Self.deleteAll(context: context)

        // 恢复
        for k in bundle.knowledge {
            let item = KnowledgeItem(title: k.title, folder: k.folder, kind: k.kind, textContent: k.text, tags: k.tags)
            item.createdAt = k.createdAt; item.updatedAt = k.updatedAt
            context.insert(item)
        }
        var notebookMap: [String: Notebook] = [:]
        for n in bundle.notes {
            var notebookID: UUID?
            if let nid = n.notebookID {
                if let book = notebookMap[nid] { notebookID = book.id }
                else { let book = Notebook(name: "恢复-\(nid.prefix(4))"); context.insert(book); notebookMap[nid] = book; notebookID = book.id }
            }
            let note = Note(title: n.title, content: n.content, notebookID: notebookID,
                            pinned: n.pinned, isResearchReport: n.research, tags: n.tags)
            note.createdAt = n.createdAt; note.updatedAt = n.updatedAt
            context.insert(note)
        }
        for p in bundle.codeProjects {
            let project = CodeProject(name: p.name, descText: p.desc, language: p.language)
            context.insert(project)
            for f in p.files {
                let file = CodeFile(name: f.name, language: f.language, content: f.content)
                context.insert(file)
                file.project = project
            }
        }
        for s in bundle.codeSnippets {
            context.insert(CodeSnippet(title: s.title, language: s.language, code: s.code, tags: s.tags))
        }
        for s in bundle.skills {
            let skill = Skill(name: s.name, desc: s.desc, triggers: s.triggers,
                              prompt: s.prompt, steps: s.steps, enabled: s.enabled, isBuiltin: s.isBuiltin)
            context.insert(skill)
        }
        for kind in MemoryCardKind.allCases {
            let card = MemoryCard(kind: kind, enabled: true, personaText: kind == .persona ? bundle.memoryPersona : "")
            context.insert(card)
            for e in bundle.memoryEntries where e.kind == kind.rawValue {
                let entry = MemoryEntry(content: e.content)
                entry.createdAt = e.createdAt
                context.insert(entry)
                entry.card = card
            }
        }
        for p in bundle.providers {
            let provider = LLMProviderEntity(name: p.name, baseURL: p.baseURL,
                                             keychainID: "provider-\(UUID().uuidString)",
                                             isActive: false, isLocal: p.isLocal, models: p.models)
            context.insert(provider)
            if let enc = p.keyEncrypted, !passphrase.isEmpty,
               let key = Self.decrypt(enc, passphrase: passphrase) {
                KeychainStore.set(key, id: provider.keychainID)
            }
        }
        for c in bundle.conversations {
            let conv = Conversation(title: c.title, modelKey: c.modelKey, reasoningLevel: c.reasoningLevel,
                                    webSearch: c.webSearch, deepResearch: c.deepResearch, pinned: c.pinned)
            conv.createdAt = c.createdAt; conv.updatedAt = c.updatedAt
            context.insert(conv)
            for m in c.messages {
                let message = Message(id: UUID(uuidString: m.taskID ?? "") ?? UUID(),
                                      role: MessageRole(rawValue: m.role) ?? .assistant,
                                      kind: MessageKind(rawValue: m.kind) ?? .text,
                                      content: m.content, reasoning: m.reasoning,
                                      taskID: m.taskID.flatMap(UUID.init(uuidString:)))
                message.createdAt = m.createdAt
                message.citations = m.citations.map { Citation(id: $0.id, title: $0.title, snippet: $0.snippet, kind: $0.kind, itemID: $0.itemID, url: $0.url, chunkIndex: $0.chunkIndex) }
                message.toolTrace = m.trace
                message.archived = m.archived.compactMap { a in
                    guard let aid = UUID(uuidString: a.id) else { return nil }
                    return ArchivedMessage(id: aid, role: a.role, content: a.content, createdAt: a.createdAt)
                }
                context.insert(message)
                message.conversation = conv
            }
        }
        for t in bundle.tasks {
            let task = GiantTask(title: t.title, goal: t.goal,
                                 state: TaskState(rawValue: t.state) ?? .done,
                                 isResearch: t.isResearch)
            task.percent = t.percent
            task.plan = t.plan
            context.insert(task)
        }
        for a in bundle.artifacts {
            guard let taskID = UUID(uuidString: a.taskID) else { continue }
            let dir = GiantTaskEngine.artifactsDir(taskID: taskID)
            try? a.text.write(to: dir.appendingPathComponent(a.name), atomically: true, encoding: .utf8)
        }

        try context.save()
        return "已恢复：\(bundle.conversations.count) 会话 · \(bundle.knowledge.count) 知识 · \(bundle.notes.count) 笔记 · \(bundle.codeProjects.count) 项目 · \(bundle.skills.count) 技能"
    }

    static func deleteAll(context: ModelContext) {
        // CodeFile / Message / MemoryEntry 随宿主级联删除
        for item in (try? context.fetch(FetchDescriptor<Conversation>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<KnowledgeItem>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<Notebook>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<Note>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<CodeProject>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<CodeSnippet>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<Skill>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<MemoryCard>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<LLMProviderEntity>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<GiantTask>())) ?? [] { context.delete(item) }
        try? context.save()
    }

    // MARK: 对话导出（主流 LLM App 格式：Markdown / JSON）
    func exportConversation(_ conv: Conversation, asMarkdown: Bool) -> URL {
        let stamp = Self.stamp()
        if asMarkdown {
            var md = "# \(conv.title)\n\n"
            for m in conv.visibleMessages {
                if m.compressedOut { continue }
                switch m.kind {
                case .summary:
                    md += "> 🌸 \(m.content)\n\n"
                case .task:
                    md += "> 🧩 [任务卡片]\n\n"
                default:
                    md += "**\(m.role == .user ? "🧑 我" : "🤖 樱花副驾")**（\(Self.shortTime(m.createdAt))）\n\n\(m.content)\n\n"
                }
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(conv.title)-\(stamp).md")
            try? md.write(to: url, atomically: true, encoding: .utf8)
            return url
        } else {
            struct ExportMsg: Codable { var role: String; var content: String; var date: Date }
            struct ExportConv: Codable { var title: String; var created: Date; var messages: [ExportMsg] }
            let payload = ExportConv(title: conv.title, created: conv.createdAt,
                                     messages: conv.visibleMessages.filter { !$0.compressedOut }
                                        .map { ExportMsg(role: $0.roleRaw, content: $0.content, date: $0.createdAt) })
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(payload)) ?? Data()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("chat-\(stamp).json")
            try? data.write(to: url)
            return url
        }
    }

    // MARK: AES-GCM（密钥导出）
    static func encrypt(_ plain: String, passphrase: String) -> String? {
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data(passphrase.utf8))))
        guard let sealed = try? AES.GCM.seal(Data(plain.utf8), using: key) else { return nil }
        return sealed.combined?.base64EncodedString()
    }

    static func decrypt(_ base64: String, passphrase: String) -> String? {
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data(passphrase.utf8))))
        guard let data = Data(base64Encoded: base64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
