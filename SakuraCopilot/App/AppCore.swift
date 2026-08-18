import SwiftUI
import SwiftData
import Observation

// MARK: - 偏好设置
@MainActor
@Observable
final class Preferences {
    private let d = UserDefaults.standard

    var smartRouter: Bool {
        get { d.object(forKey: "smartRouter") as? Bool ?? true }
        set { d.set(newValue, forKey: "smartRouter") }
    }
    var autoRAG: Bool {
        get { d.object(forKey: "autoRAG") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoRAG") }
    }
    var webDefaultOn: Bool {
        get { d.object(forKey: "webDefaultOn") as? Bool ?? false }
        set { d.set(newValue, forKey: "webDefaultOn") }
    }
    var searchEndpoint: String {
        get { d.string(forKey: "searchEndpoint") ?? "https://searx.be/search" }
        set { d.set(newValue, forKey: "searchEndpoint") }
    }
    var searchKey: String {
        get { d.string(forKey: "searchKey") ?? "" }
        set { d.set(newValue, forKey: "searchKey") }
    }
    var compressThreshold: Int {
        get { d.object(forKey: "compressThreshold") as? Int ?? 30000 }
        set { d.set(max(8000, newValue), forKey: "compressThreshold") }
    }
    var petalsOn: Bool {
        get { d.object(forKey: "petalsOn") as? Bool ?? true }
        set { d.set(newValue, forKey: "petalsOn") }
    }
    var glowOn: Bool {
        get { d.object(forKey: "glowOn") as? Bool ?? true }
        set { d.set(newValue, forKey: "glowOn") }
    }
    var defaultModelKey: String {
        get { d.string(forKey: "defaultModelKey") ?? "" }
        set { d.set(newValue, forKey: "defaultModelKey") }
    }
}

// MARK: - 路由
enum AppTab: Int, Hashable {
    case chat, knowledge, notes, code
}

struct AssistRequest: Identifiable {
    let id = UUID()
    let area: String       // 知识库 / 笔记 / 代码库
    let text: String
}

@MainActor
@Observable
final class TabRouter {
    var tab: AppTab = .chat
    var assistRequest: AssistRequest?
    var showTaskCenter = false
    var focusTaskID: UUID?
}

// MARK: - 模型商店（多套配置 · 一键切换 · 密钥进 Keychain）
@MainActor
@Observable
final class ModelStore {
    private let context: ModelContext
    private(set) var providers: [LLMProviderEntity] = []

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        let d = FetchDescriptor<LLMProviderEntity>(sortBy: [SortDescriptor(\.createdAt)])
        providers = (try? context.fetch(d)) ?? []
    }

    var activeProvider: LLMProviderEntity? {
        providers.first(where: \.isActive) ?? providers.first
    }

    func setActive(_ provider: LLMProviderEntity) {
        for p in providers { p.isActive = (p.id == provider.id) }
        try? context.save()
        reload()
    }

    @discardableResult
    func addProvider(name: String, baseURL: String, apiKey: String,
                     isLocal: Bool = false, models: [ModelInfo] = []) -> LLMProviderEntity {
        let keychainID = "provider-\(UUID().uuidString)"
        if !apiKey.isEmpty { KeychainStore.set(apiKey, id: keychainID) }
        let shouldActive = providers.isEmpty
        let entity = LLMProviderEntity(name: name, baseURL: baseURL,
                                       keychainID: keychainID,
                                       isActive: shouldActive, isLocal: isLocal,
                                       models: models)
        context.insert(entity)
        try? context.save()
        reload()
        if defaultModelKey.isEmpty, let first = entity.models.first {
            defaultModelKey = ModelKey.make(providerID: entity.id, modelID: first.id)
        }
        return entity
    }

    func updateAPIKey(_ provider: LLMProviderEntity, _ key: String) {
        KeychainStore.set(key, id: provider.keychainID)
        try? context.save()
        reload()
    }

    func deleteProvider(_ provider: LLMProviderEntity) {
        KeychainStore.delete(provider.keychainID)
        context.delete(provider)
        try? context.save()
        reload()
        if let pid = ModelKey.parse(defaultModelKey)?.providerID, pid == provider.id {
            defaultModelKey = ""
        }
    }

    func upsertModel(_ provider: LLMProviderEntity, model: ModelInfo) {
        var models = provider.models
        if let idx = models.firstIndex(where: { $0.id == model.id }) {
            models[idx] = model
        } else {
            models.append(model)
        }
        provider.models = models
        try? context.save()
        reload()
    }

    func removeModel(_ provider: LLMProviderEntity, modelID: String) {
        provider.models = provider.models.filter { $0.id != modelID }
        try? context.save()
        reload()
    }

    // MARK: 解析
    func modelInfo(for key: String) -> ModelInfo? {
        guard let (pid, mid) = ModelKey.parse(key),
              let provider = providers.first(where: { $0.id == pid }) else { return nil }
        return provider.models.first { $0.id == mid }
    }

    func endpoint(for key: String?) -> LLMEndpoint? {
        guard let key,
              let (pid, mid) = ModelKey.parse(key),
              let provider = providers.first(where: { $0.id == pid }),
              let model = provider.models.first(where: { $0.id == mid }) else { return nil }
        return LLMEndpoint(providerID: provider.id, providerName: provider.name,
                           model: model, baseURL: provider.baseURL,
                           apiKey: provider.apiKey)
    }

    /// 当前对话使用的模型 Key（会话级覆盖 → 全局默认）
    func currentKey(conversation: Conversation?) -> String? {
        conversation?.modelKey ?? defaultModelKey
    }

    /// 干活端点：优先支持工具调用的模型
    func workEndpoint() -> LLMEndpoint? {
        if let key = currentKey(conversation: nil), let ep = endpoint(for: key), ep.model.supportsTools {
            return ep
        }
        for provider in providers {
            if let m = provider.models.first(where: { $0.supportsTools }) {
                return LLMEndpoint(providerID: provider.id, providerName: provider.name,
                                   model: m, baseURL: provider.baseURL, apiKey: provider.apiKey)
            }
        }
        return endpoint(for: currentKey(conversation: nil))
    }

    func displayName(key: String?) -> String {
        guard let key else { return "未配置模型" }
        return ModelKey.displayName(key, providers: providers)
    }

    /// 快捷预设（含本地小模型接口）
    static let presets: [(name: String, baseURL: String, models: [String])] = [
        ("OpenAI", "https://api.openai.com/v1", ["gpt-4o", "gpt-4o-mini", "o3-mini"]),
        ("DeepSeek", "https://api.deepseek.com/v1", ["deepseek-chat", "deepseek-reasoner"]),
        ("通义千问", "https://dashscope.aliyuncs.com/compatible-mode/v1", ["qwen-max", "qwen-plus", "qwen-turbo"]),
        ("Kimi", "https://api.moonshot.cn/v1", ["moonshot-v1-128k", "moonshot-v1-32k"]),
        ("智谱 GLM", "https://open.bigmodel.cn/api/paas/v4", ["glm-4-plus", "glm-4-flash"]),
        ("本地小模型 (Ollama)", "http://127.0.0.1:11434/v1", ["qwen2.5:7b", "llama3.1:8b"])
    ]
}
