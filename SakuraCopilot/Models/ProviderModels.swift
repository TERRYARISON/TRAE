import Foundation
import SwiftData

// MARK: - 模型配置（任意 OpenAI 兼容 API）

struct ModelInfo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var supportsTools: Bool = true
    var supportsReasoning: Bool = false
    var contextTokens: Int = 128000
}

@Model
final class LLMProviderEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var baseURL: String
    var keychainID: String
    var isActive: Bool
    var isLocal: Bool
    var createdAt: Date

    @Attribute(.externalStorage) var modelsData: Data?

    init(id: UUID = UUID(), name: String, baseURL: String,
         keychainID: String, isActive: Bool = false, isLocal: Bool = false, models: [ModelInfo] = []) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.keychainID = keychainID
        self.isActive = isActive
        self.isLocal = isLocal
        self.createdAt = Date()
        self.modelsData = try? JSONEncoder().encode(models)
    }

    var models: [ModelInfo] {
        get { (try? JSONDecoder().decode([ModelInfo].self, from: modelsData ?? Data())) ?? [] }
        set { modelsData = try? JSONEncoder().encode(newValue) }
    }

    var apiKey: String { KeychainStore.get(keychainID) ?? "" }
}

// MARK: - 推理档位

enum ReasoningLevel: Int, CaseIterable, Codable, Identifiable {
    case off = 0, low, medium, high, max
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .max: return "Max"
        }
    }

    /// 不支持的模型自动隐藏该选项；off 不下发参数
    var apiValue: String? {
        switch self {
        case .off: return nil
        default: return label.lowercased()
        }
    }
}

// MARK: - 模型 Key（provider::model）

enum ModelKey {
    static func make(providerID: UUID, modelID: String) -> String {
        "\(providerID.uuidString)::\(modelID)"
    }

    static func parse(_ key: String) -> (providerID: UUID, modelID: String)? {
        let parts = key.components(separatedBy: "::")
        guard parts.count == 2, let pid = UUID(uuidString: parts[0]) else { return nil }
        return (pid, parts[1])
    }

    static func displayName(_ key: String, providers: [LLMProviderEntity]) -> String {
        guard let (pid, mid) = parse(key),
              let provider = providers.first(where: { $0.id == pid }) else { return "未配置模型" }
        let model = provider.models.first { $0.id == mid }
        return "\(provider.name) · \(model?.name ?? mid)"
    }
}

/// 一次 LLM 调用所需的全部端点信息
struct LLMEndpoint {
    var providerID: UUID
    var providerName: String
    var model: ModelInfo
    var baseURL: String
    var apiKey: String

    var chatURL: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        return URL(string: base + "/chat/completions")
    }

    var modelsURL: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        return URL(string: base + "/models")
    }
}
