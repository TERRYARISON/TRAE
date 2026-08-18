import Foundation
import SwiftData

// MARK: - 检索命中
struct KnowledgeHit: Identifiable, Hashable {
    var id: String { "\(itemID)#\(chunkIndex)" }
    let itemID: UUID
    let title: String
    let folder: String?
    let tags: [String]
    let chunkIndex: Int
    let text: String
    let score: Double
}

struct KnowledgeSnapshot: Sendable {
    let id: UUID
    let title: String
    let folder: String
    let tags: [String]
    let chunks: [String]
}

// MARK: - BM25 中文检索（字符二元组 + 英文词）
enum BM25 {
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        let lowered = text.lowercased()
        var word = ""
        var prevHan: Character?
        for ch in lowered {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                word.append(ch)
                prevHan = nil
            } else {
                if !word.isEmpty { tokens.append(word); word = "" }
                if ("\u{4E00}"..."\u{9FFF}").contains(ch) {
                    if let p = prevHan { tokens.append(String(p) + String(ch)) }
                    prevHan = ch
                } else {
                    prevHan = nil
                }
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }

    static func score(snapshots: [KnowledgeSnapshot], query: String, topK: Int) -> [KnowledgeHit] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        // 每个片段的词频
        struct ChunkTokens { let snapshot: KnowledgeSnapshot; let index: Int; let tokens: [String]; var tf: [String: Int] }
        var all: [ChunkTokens] = []
        for snap in snapshots {
            for (i, chunk) in snap.chunks.enumerated() {
                let toks = tokenize(chunk + " " + snap.title)
                var tf: [String: Int] = [:]
                for t in toks { tf[t, default: 0] += 1 }
                all.append(ChunkTokens(snapshot: snap, index: i, tokens: toks, tf: tf))
            }
        }
        guard !all.isEmpty else { return [] }

        let N = Double(all.count)
        var df: [String: Int] = [:]
        var avgLen = 0.0
        for c in all {
            avgLen += Double(c.tokens.count)
            for t in Set(c.tf.keys) { df[t, default: 0] += 1 }
        }
        avgLen /= max(N, 1)

        let k1 = 1.5, b = 0.75
        var hits: [KnowledgeHit] = []
        for c in all {
            var score = 0.0
            for q in queryTokens {
                guard let tf = c.tf[q] else { continue }
                let n = Double(df[q] ?? 1)
                let idf = log((N - n + 0.5) / (n + 0.5) + 1)
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * Double(c.tokens.count) / avgLen))
            }
            if score > 0 {
                hits.append(KnowledgeHit(itemID: c.snapshot.id, title: c.snapshot.title,
                                         folder: c.snapshot.folder, tags: c.snapshot.tags,
                                         chunkIndex: c.index, text: c.snapshot.chunks[c.index],
                                         score: score))
            }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(topK))
    }
}

// MARK: - 知识库服务
@MainActor
final class KnowledgeService {
    let context: ModelContext
    private(set) var cacheStamp: [UUID: Date] = [:]

    init(context: ModelContext) { self.context = context }

    func allItems() -> [KnowledgeItem] {
        let descriptor = FetchDescriptor<KnowledgeItem>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func item(id: UUID) -> KnowledgeItem? {
        var descriptor = FetchDescriptor<KnowledgeItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    func createItem(title: String, text: String, folder: String? = nil,
                    tags: [String] = [], kind: String = "doc") -> KnowledgeItem {
        let item = KnowledgeItem(title: title, folder: folder, kind: kind,
                                 textContent: text, tags: tags)
        context.insert(item)
        try? context.save()
        return item
    }

    func importFiles(urls: [URL]) async -> [(name: String, ok: Bool, message: String)] {
        var results: [(String, Bool, String)] = []
        for url in urls {
            do {
                let text = try await TextExtractor.extract(url: url)
                if text.isBlank {
                    results.append((url.lastPathComponent, false, "未能提取到文字内容"))
                } else {
                    let title = url.deletingPathExtension().lastPathComponent
                    createItem(title: title, text: text,
                               folder: "导入", tags: ["导入"])
                    results.append((url.lastPathComponent, true, "已导入 \(text.count) 字"))
                }
            } catch {
                results.append((url.lastPathComponent, false, "不支持的格式 .\(url.pathExtension)"))
            }
        }
        return results
    }

    func delete(item: KnowledgeItem) {
        context.delete(item)
        try? context.save()
    }

    func rename(item: KnowledgeItem, to newTitle: String) {
        item.title = newTitle
        item.updatedAt = Date()
        try? context.save()
    }

    func move(items: [KnowledgeItem], to folder: String) {
        for item in items { item.folder = folder; item.updatedAt = Date() }
        try? context.save()
    }

    func allFolders() -> [String] {
        Set(allItems().compactMap(\.folder)).sorted()
    }

    /// 全文检索（后台 BM25）
    func search(_ query: String, topK: Int = 6) async -> [KnowledgeHit] {
        let snapshots: [KnowledgeSnapshot] = allItems().map { item in
            KnowledgeSnapshot(id: item.id, title: item.title,
                              folder: item.folder ?? "", tags: item.tags,
                              chunks: Chunker.chunks(of: item.textContent))
        }
        let q = query
        return await Task.detached(priority: .userInitiated) {
            BM25.score(snapshots: snapshots, query: q, topK: topK)
        }.value
    }
}
