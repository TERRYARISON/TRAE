import Foundation
import SwiftData

// MARK: - 记忆四卡片

enum MemoryCardKind: String, Codable, CaseIterable {
    case persona      // 助理人设
    case profile      // 我的档案
    case longTerm     // 长期记忆
    case tips         // 经验技巧

    var title: String {
        switch self {
        case .persona: return "助理人设"
        case .profile: return "我的档案"
        case .longTerm: return "长期记忆"
        case .tips: return "经验技巧"
        }
    }

    var icon: String {
        switch self {
        case .persona: return "person.crop.square.filled.and.at.rectangle"
        case .profile: return "folder.badge.person.crop"
        case .longTerm: return "brain.head.profile"
        case .tips: return "lightbulb.max"
        }
    }

    var hint: String {
        switch self {
        case .persona: return "它是谁、怎么说话、性格与底线（整段自由文本）"
        case .profile: return "我是谁：称呼、职业、偏好等事实条目"
        case .longTerm: return "跨会话需要一直记住的事"
        case .tips: return "做事方法、口径、坑与经验"
        }
    }

    var tint: String {
        switch self {
        case .persona: return "pink"
        case .profile: return "cyan"
        case .longTerm: return "purple"
        case .tips: return "gold"
        }
    }
}

@Model
final class MemoryCard {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var enabled: Bool
    var personaText: String?      // 仅 persona 卡使用

    @Relationship(deleteRule: .cascade, inverse: \MemoryEntry.card)
    var entries: [MemoryEntry]

    init(id: UUID = UUID(), kind: MemoryCardKind, enabled: Bool = true, personaText: String = "") {
        self.id = id
        self.kindRaw = kind.rawValue
        self.enabled = enabled
        self.personaText = personaText
        self.entries = []
    }

    var kind: MemoryCardKind { MemoryCardKind(rawValue: kindRaw) ?? .longTerm }

    var sortedEntries: [MemoryEntry] {
        entries.sorted { $0.createdAt < $1.createdAt }
    }
}

@Model
final class MemoryEntry {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var card: MemoryCard?

    init(id: UUID = UUID(), content: String) {
        self.id = id
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.card = nil
    }
}
