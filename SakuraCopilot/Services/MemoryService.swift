import Foundation
import SwiftData

// MARK: - 记忆服务（四卡片）
@MainActor
final class MemoryService {
    let context: ModelContext
    private(set) var cards: [MemoryCard] = []

    static let masterKey = "memoryMaster"

    init(context: ModelContext) {
        self.context = context
        ensureCards()
    }

    var masterOn: Bool {
        get { UserDefaults.standard.object(forKey: Self.masterKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.masterKey) }
    }

    func ensureCards() {
        let existing = (try? context.fetch(FetchDescriptor<MemoryCard>())) ?? []
        let kinds = Set(existing.map(\.kindRaw))
        for kind in MemoryCardKind.allCases where !kinds.contains(kind.rawValue) {
            let card = MemoryCard(kind: kind, enabled: true,
                                  personaText: kind == .persona ? Self.defaultPersona : "")
            context.insert(card)
        }
        try? context.save()
        cards = ((try? context.fetch(FetchDescriptor<MemoryCard>())) ?? [])
            .sorted { MemoryCardKind(rawValue: $0.kindRaw)?.hashValue ?? 0 < MemoryCardKind(rawValue: $1.kindRaw)?.hashValue ?? 0 }
    }

    func card(_ kind: MemoryCardKind) -> MemoryCard? {
        cards.first { $0.kind == kind }
    }

    var personaText: String {
        get { card(.persona)?.personaText ?? "" }
        set {
            if let card = card(.persona) {
                card.personaText = newValue
                try? context.save()
            }
        }
    }

    static let defaultPersona = """
    你是「樱花副驾」，我唯一的个人 AI Copilot，赛博朋克樱花气质：冷静、锋利、可靠。
    默认简体中文交流；答知识库问题必须带来源角标；破坏性操作先确认；巨型任务先给计划。
    """

    @discardableResult
    func addEntry(kind: MemoryCardKind, content: String) -> Bool {
        guard let card = card(kind), !content.isBlank else { return false }
        let entry = MemoryEntry(content: content)
        context.insert(entry)
        entry.card = card
        try? context.save()
        ensureCards()
        return true
    }

    func delete(entry: MemoryEntry) {
        context.delete(entry)
        try? context.save()
        ensureCards()
    }

    /// 自然语言删除记忆：返回被删除条目的描述
    func forget(keyword: String) -> [String] {
        var removed: [String] = []
        for card in cards {
            for entry in card.entries where entry.content.localizedCaseInsensitiveContains(keyword) {
                removed.append("[\(card.kind.title)] \(entry.content)")
                context.delete(entry)
            }
        }
        try? context.save()
        ensureCards()
        return removed
    }

    /// 注入系统提示词的记忆段落
    func promptSection() -> String? {
        guard masterOn else { return nil }
        var parts: [String] = []
        if let persona = card(.persona), persona.enabled, let text = persona.personaText, !text.isBlank {
            parts.append("【助理人设】\n\(text)")
        }
        for kind in [MemoryCardKind.profile, .longTerm, .tips] {
            guard let card = card(kind), card.enabled, !card.sortedEntries.isEmpty else { continue }
            let lines = card.sortedEntries.map { "· \($0.content)" }.joined(separator: "\n")
            parts.append("【\(kind.title)】\n\(lines)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }
}
