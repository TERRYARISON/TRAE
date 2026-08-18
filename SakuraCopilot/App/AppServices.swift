import SwiftUI
import SwiftData
import Observation

// MARK: - 应用服务容器（全部本地 · 单用户 · 无账号）
@MainActor
@Observable
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    let prefs = Preferences()
    let router = TabRouter()
    let modelStore: ModelStore
    let knowledge: KnowledgeService
    let skills: SkillService
    let memory: MemoryService
    let chatContext: ChatContextService
    let engine: GiantTaskEngine
    let backup: BackupService
    let tools: ToolExecutor
    var chat: ChatStore!

    init() {
        let schema = Schema([
            Conversation.self, Message.self,
            KnowledgeItem.self,
            Notebook.self, Note.self,
            CodeProject.self, CodeFile.self, CodeSnippet.self,
            Skill.self,
            MemoryCard.self, MemoryEntry.self,
            LLMProviderEntity.self,
            GiantTask.self
        ])
        let config = ModelConfiguration(url: Self.storeURL())
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 极端损坏时的兜底：重建存储
            try? FileManager.default.removeItem(at: Self.storeURL())
            container = (try? ModelContainer(for: schema, configurations: [config])) ?? {
                fatalError("无法初始化本地数据库：\(error)")
            }()
        }

        let ctx = container.mainContext
        modelStore = ModelStore(context: ctx)
        knowledge = KnowledgeService(context: ctx)
        skills = SkillService(context: ctx)
        memory = MemoryService(context: ctx)
        chatContext = ChatContextService(memory: memory, skills: skills, prefs: prefs, modelStore: modelStore)
        engine = GiantTaskEngine(context: ctx, modelStore: modelStore, prefs: prefs, knowledge: knowledge)
        backup = BackupService(context: ctx)
        tools = ToolExecutor(context: ctx, knowledge: knowledge, memory: memory,
                             skills: skills, modelStore: modelStore, prefs: prefs)
        chat = ChatStore(services: self)
    }

    func bootstrap() {
        skills.seedBuiltinsIfNeeded()
        memory.ensureCards()
        if memory.personaText.isBlank { memory.personaText = MemoryService.defaultPersona }
        chat.ensureCurrent()
    }

    func handle(url: URL) {
        // sakura://task/<uuid> 灵动岛/通知深链
        guard url.scheme == "sakura", url.host == "task" else { return }
        let idString = url.lastPathComponent
        router.focusTaskID = UUID(uuidString: idString)
        router.showTaskCenter = true
        router.tab = .chat
    }

    static func storeURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SakuraCopilot.sqlite")
    }
}
