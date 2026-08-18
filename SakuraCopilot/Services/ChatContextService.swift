import Foundation
import SwiftData

// MARK: - 对话上下文（系统提示词 / 历史 / 压缩 / 用户轮装配）
@MainActor
final class ChatContextService {
    let memory: MemoryService
    let skills: SkillService
    let prefs: Preferences
    let modelStore: ModelStore

    init(memory: MemoryService, skills: SkillService, prefs: Preferences, modelStore: ModelStore) {
        self.memory = memory
        self.skills = skills
        self.prefs = prefs
        self.modelStore = modelStore
    }

    // MARK: 系统提示词
    func systemPrompt(toolsAvailable: Bool, matchedSkills: [Skill]) -> String {
        var parts: [String] = []
        let base = """
        你是「樱花副驾」——这位用户唯一的个人 AI Copilot（对标 ima Copilot 的个人纯享版）。
        当前日期：\(Self.dayFormatter.string(from: Date()))。默认使用简体中文。

        【知识库与资料】
        - 回答凡依据知识库、附件、@引用、检索结果或联网结果，必须在对应句末标注来源角标，格式 [n]；n 与资料块编号一致。
        - 不确定的内容不要编造，明确说明缺口。

        【做事准则】
        - 用户让你「帮我记一下 / 建个文件 / 改一下」时直接动手（用工具），做完简报结果，不要只给建议。
        - 创建类操作直接执行；删除、覆盖、批量移动会弹出确认卡片，等用户确认后再继续。
        - 巨型任务（超大材料阅读、超长写作、全库整理、批量翻译等）不要硬扛：说明将生成执行计划交给任务引擎，先给用户看拆解计划。

        【安全底线】
        - 删除/覆盖/批量移动必须经用户二次确认，绝不静默执行。
        """
        parts.append(base)

        if let persona = memory.promptSection() {
            parts.append(persona)
        }

        for skill in matchedSkills {
            let steps = skill.steps.isEmpty ? "" : "\n流程参考：\n" + skill.steps.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            parts.append("【已激活技能：\(skill.name)】\(skill.descText)\n\(skill.promptTemplate)\(steps)")
        }

        if !toolsAvailable {
            parts.append("""
            【本轮限制】
            当前所选模型不支持工具调用（仅对话）。如用户要求新建/修改/整理文件或笔记，请先给出内容与方案，并提示用户切换到支持工具调用的模型来「派活干活」。
            """)
        } else {
            parts.append("""
            【工具使用】
            - 需要查资料先 search_knowledge / web_search；动手指令用对应工具完成。
            - 记住用户信息用 remember；删除记忆用 forget（会走确认）。
            - 一次做一件事，依赖上一步结果的分多轮完成。
            """)
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: 历史 → Wire 消息
    func historyWire(for conversation: Conversation) -> [WireMessage] {
        var result: [WireMessage] = []
        for message in conversation.visibleMessages {
            if message.compressedOut { continue }
            switch message.kind {
            case .summary:
                result.append(.system("（更早对话已被压缩为以下摘要，视为已知历史）\n" + message.content))
            case .text, .error:
                switch message.role {
                case .user: result.append(.user(message.content))
                case .assistant: result.append(.assistant(message.content))
                default: break
                }
            default:
                break
            }
        }
        return result
    }

    // MARK: 长对话自动压缩（永远不会聊爆）
    func maybeCompress(conversation: Conversation) {
        let active = conversation.visibleMessages.filter {
            !$0.compressedOut && ($0.kind == .text || $0.kind == .error) &&
            ($0.role == .user || $0.role == .assistant)
        }
        let totalTokens = active.reduce(0) { $0 + $1.content.approxTokens }
        guard totalTokens > prefs.compressThreshold, active.count > 8 else { return }

        let keepCount = max(6, active.count / 2)
        let compressible = Array(active.dropLast(keepCount))
        guard !compressible.isEmpty else { return }

        var summary = ""
        if let endpoint = modelStore.workEndpoint() {
            let transcript = compressible.enumerated().map { i, m in
                "\(m.role == .user ? "用户" : "助理")：\(String(m.content.prefix(1200)))"
            }.joined(separator: "\n")
            let prompt = "把以下对话压缩成保留全部关键信息（事实、决定、待办、口径、人名设定）的摘要，用要点列出：\n\n\(transcript)"
            summary = (try? LLMClient().chatOnce(endpoint: endpoint,
                                                 messages: [.user(prompt)],
                                                 temperature: 0.3, maxTokens: 1500)) ?? ""
        }
        if summary.isBlank {
            summary = compressible.map { "· \($0.role == .user ? "用户" : "助理")：\(String($0.content.prefix(80)))" }
                .joined(separator: "\n")
        }

        let archivedMessages = compressible.map {
            ArchivedMessage(id: $0.id, role: $0.roleRaw, content: $0.content, createdAt: $0.createdAt)
        }
        let summaryMessage = Message(role: .assistant, kind: .summary, content: "早期对话摘要（\(compressible.count) 条已压缩）：\n\(summary)")
        summaryMessage.createdAt = compressible.first!.createdAt
        summaryMessage.archived = archivedMessages
        conversation.messages.append(summaryMessage)
        for m in compressible { m.compressedOut = true }
        try? conversation.managedObjectContext?.save()
    }

    // MARK: 用户轮装配（附件 / @引用 / 检索 / 联网）
    static func buildUserTurn(text: String,
                              attachments: [AttachmentRef],
                              mentionItems: [(title: String, text: String)],
                              hits: [KnowledgeHit],
                              web: [WebResult]) -> (String, [Citation]) {
        var blocks: [String] = []
        var citations: [Citation] = []
        var index = 1

        for mention in mentionItems {
            let body = mention.text.count > 20000
                ? String(mention.text.prefix(20000)) + "\n…（超长已截断，完整内容将由巨型任务管线消化）"
                : mention.text
            blocks.append("【@引用资料 [\(index)] \(mention.title)】\n\(body)")
            citations.append(Citation(id: index, title: mention.title,
                                      snippet: String(mention.text.prefix(120)),
                                      kind: "knowledge", itemID: mention.title, chunkIndex: 0))
            index += 1
        }
        for attachment in attachments {
            guard let content = attachment.textContent else { continue }
            let body = content.count > 30000
                ? String(content.prefix(30000)) + "\n…（附件过长，已截断；完整消化请走巨型任务）"
                : content
            blocks.append("【附件 [\(index)] \(attachment.name)】\n\(body)")
            citations.append(Citation(id: index, title: attachment.name,
                                      snippet: String(content.prefix(120)),
                                      kind: "knowledge", itemID: attachment.name, chunkIndex: 0))
            index += 1
        }
        if !hits.isEmpty {
            let hitLines = hits.map { hit in
                let block = "[\(index)] 《\(hit.title)》片段#\(hit.chunkIndex)（文件夹:\(hit.folder ?? "未分组")）\n\(String(hit.text.prefix(500)))"
                citations.append(Citation(id: index, title: hit.title,
                                          snippet: String(hit.text.prefix(150)),
                                          kind: "knowledge", itemID: hit.itemID.uuidString,
                                          chunkIndex: hit.chunkIndex))
                index += 1
                return block
            }
            blocks.append("【知识库检索结果】\n" + hitLines.joined(separator: "\n---\n"))
        }
        if !web.isEmpty {
            let webLines = web.map { result in
                let block = "[\(index)] \(result.title)\n来源：\(result.url)\n\(String(result.snippet.prefix(300)))"
                citations.append(Citation(id: index, title: result.title,
                                          snippet: String(result.snippet.prefix(150)),
                                          kind: "web", itemID: result.url, url: result.url))
                index += 1
                return block
            }
            blocks.append("【联网搜索结果】\n" + webLines.joined(separator: "\n---\n"))
        }

        var combined = text
        if !blocks.isEmpty {
            combined += "\n\n" + blocks.joined(separator: "\n\n")
            combined += "\n\n（回答引用上述资料时请标注对应的 [n] 角标。）"
        }
        return (combined, citations)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
}
