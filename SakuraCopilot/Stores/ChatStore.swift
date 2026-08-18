import Foundation
import SwiftData
import Observation

// MARK: - 对话编排（全局唯一助理 · 流式 · 派活 · 巨型任务路由）
@MainActor
@Observable
final class ChatStore {
    unowned let services: AppServices
    private var context: ModelContext { services.container.mainContext }

    enum Route {
        case normal
        case giant(String)
    }

    // 输入区状态
    var draft: String = ""
    var attachments: [AttachmentRef] = []
    var mentionIDs: [UUID] = []
    var showMentionPicker = false
    var streaming = false

    private(set) var conversations: [Conversation] = []
    var current: Conversation?

    private var runTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
        refresh()
    }

    func refresh() {
        let d = FetchDescriptor<Conversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        conversations = (try? context.fetch(d)) ?? []
        if let cur = current, conversations.contains(where: { $0.id == cur.id }) { return }
        current = conversations.first
        ensureCurrent()
    }

    @discardableResult
    func newConversation() -> Conversation {
        let conv = Conversation(modelKey: services.modelStore.defaultModelKey.isEmpty ? nil : services.modelStore.defaultModelKey,
                                webSearch: services.prefs.webDefaultOn)
        context.insert(conv)
        try? context.save()
        refresh()
        current = conversations.first(where: { $0.id == conv.id }) ?? conv
        return conv
    }

    func ensureCurrent() {
        if current == nil { newConversation() }
    }

    func open(_ conv: Conversation) {
        current = conv
        conv.updatedAt = Date()
        try? context.save()
    }

    func deleteConversation(_ conv: Conversation) {
        if current?.id == conv.id { current = nil }
        context.delete(conv)
        try? context.save()
        refresh()
    }

    func rename(_ conv: Conversation, to title: String) {
        conv.title = title
        try? context.save()
        refresh()
    }

    // MARK: - 发送主流程
    func send() {
        guard !streaming else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let atts = attachments
        guard !text.isEmpty || !atts.isEmpty else { return }
        guard let conv = current ?? ({ newConversation(); return current }()) else { return }

        draft = ""
        attachments = []
        let mentions = mentionIDs.compactMap { services.knowledge.item(id: $0) }
        mentionIDs = []
        let matchedSkills = services.skills.matched(text: text)

        let userMessage = Message(role: .user, kind: .text, content: text.isEmpty ? "（附件）" : text)
        userMessage.attachments = atts
        userMessage.appliedSkills = matchedSkills.map(\.name)
        conv.messages.append(userMessage)
        if conv.title == "新对话", !text.isEmpty {
            conv.title = String(text.prefix(16))
        }
        conv.updatedAt = Date()
        try? context.save()

        if conv.deepResearch {
            startDeepResearch(question: text, attachments: atts, conversation: conv)
            return
        }

        runTask = Task { [weak self] in
            guard let self else { return }
            let route = await self.route(text: text, attachments: atts, mentions: mentions)
            switch route {
            case .giant:
                await self.planAndConfirm(goal: text, attachments: atts, mentions: mentions, conversation: conv)
            case .normal:
                await self.runAgentTurn(conversation: conv, text: text, attachments: atts,
                                        mentions: mentions, matchedSkills: matchedSkills)
            }
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        streaming = false
    }

    // MARK: 路由（巨型任务识别）
    private func route(text: String, attachments: [AttachmentRef], mentions: [KnowledgeItem]) async -> Route {
        let totalChars = text.count
            + attachments.reduce(0) { $0 + ($1.textContent?.count ?? 0) }
            + mentions.reduce(0) { $0 + $1.textContent.count }
        if totalChars > 60_000 { return .giant("输入内容约 \(totalChars) 字") }

        let giantKeywords = ["万字", "十万字", "百万", "千万", "全库整理", "整个知识库", "全部整理", "全部翻译", "批量翻译",
                             "翻译全部", "通读", "读完", "长篇", "连载", "写一本", "写个小说", "写成书", "逐字稿"]
        if giantKeywords.contains(where: { text.contains($0) }) {
            return .giant("检测到巨型任务特征")
        }
        guard services.prefs.smartRouter, let endpoint = services.modelStore.workEndpoint() else {
            return .normal
        }
        let prompt = """
        判断以下用户请求是否为「巨型任务」：需要多步骤执行、处理超长材料（数万字以上）、长文写作（数千字以上）、
        全库整理、批量处理、多轮调研等 → giant；普通问答/小操作 → normal。
        用户请求：\(String(text.prefix(2000)))
        只输出 JSON：{"route":"normal|giant","reason":"..."}
        """
        if let reply = try? await LLMClient().chatOnce(endpoint: endpoint, messages: [.user(prompt)],
                                                       temperature: 0, maxTokens: 80),
           let data = LLMClient.extractJSONObject(from: reply),
           let json = try? JSONDecoder().decode(JSONValue.self, from: data),
           json["route"]?.stringValue == "giant" {
            return .giant(json["reason"]?.stringValue ?? "AI 路由判定")
        }
        return .normal
    }

    // MARK: 巨型任务：先计划 → 用户确认 → 交给引擎
    private func planAndConfirm(goal: String, attachments: [AttachmentRef],
                                mentions: [KnowledgeItem], conversation: Conversation) async {
        streaming = true
        defer { streaming = false }
        let thinking = Message(role: .assistant, kind: .text, content: "🧠 正在拆解任务计划…")
        conversation.messages.append(thinking)
        try? context.save()

        let materials = Self.collectMaterials(attachments: attachments, mentions: mentions)
        let materialsNote = materials.isEmpty ? nil : "已附带 \(materials.count) 份材料，共 \(materials.reduce(0) { $0 + $1.text.count }) 字"
        let plan = await services.engine.makePlan(goal: goal, materialsNote: materialsNote)

        conversation.messages.removeAll { $0.id == thinking.id }
        try? context.save()

        let task = services.engine.createTask(goal: goal, plan: plan, isResearch: false,
                                              conversationID: conversation.id, materials: materials)
        let card = Message(role: .assistant, kind: .task, content: plan.summary, taskID: task.id)
        card.content = "已生成任务计划，请确认后开始执行。"
        conversation.messages.append(card)
        conversation.updatedAt = Date()
        try? context.save()
    }

    private func startDeepResearch(question: String, attachments: [AttachmentRef], conversation: Conversation) {
        let plan = ResearchService.buildPlan(question: question)
        let materials = Self.collectMaterials(attachments: attachments, mentions: [])
        let task = services.engine.createTask(goal: question, plan: plan, isResearch: true,
                                              conversationID: conversation.id, materials: materials)
        let card = Message(role: .assistant, kind: .task,
                           content: "🧠 深度研究已启动：多轮递进搜索 → 自检补搜 → 结构化报告（自动存为笔记）。",
                           taskID: task.id)
        conversation.messages.append(card)
        try? context.save()
        services.engine.start(task.id)
    }

    static func collectMaterials(attachments: [AttachmentRef], mentions: [KnowledgeItem]) -> [(title: String, text: String)] {
        var materials: [(String, String)] = []
        for att in attachments {
            if let text = att.textContent, !text.isBlank {
                materials.append((att.name, text))
            }
        }
        for item in mentions {
            materials.append(("@\(item.title)", item.textContent))
        }
        return materials
    }

    // MARK: 计划确认 / 待确认操作
    func confirmTaskPlan(_ taskID: UUID) {
        services.engine.start(taskID)
    }

    func cancelTaskPlan(_ taskID: UUID) {
        services.engine.cancel(taskID)
    }

    func confirmPending(_ message: Message) {
        guard let pending = message.pending, let conv = message.conversation else { return }
        message.pending = nil
        message.content = "⏳ 正在执行：\(pending.title)…"
        try? context.save()
        Task {
            let result = await services.tools.performConfirmed(pending)
            let done = Message(role: .assistant, kind: .text,
                               content: "✅ 已执行：\(pending.title)\n\(result)\n\n（回复「继续」可让助理接着推进任务）")
            conv.messages.append(done)
            conv.updatedAt = Date()
            try? context.save()
        }
    }

    func rejectPending(_ message: Message) {
        guard message.pending != nil else { return }
        let title = message.pending?.title ?? ""
        message.pending = nil
        message.content = "🚫 已取消：\(title)"
        try? context.save()
    }

    // MARK: - 普通智能体回合（流式 + 工具循环 + 引用）
    private func runAgentTurn(conversation conv: Conversation, text: String,
                              attachments: [AttachmentRef], mentions: [KnowledgeItem],
                              matchedSkills: [Skill]) async {
        streaming = true
        defer { streaming = false }

        guard let key = services.modelStore.currentKey(conversation: conv),
              let endpoint = services.modelStore.endpoint(for: key) else {
            appendError(conv, LLMError.noModelConfigured.localizedDescription)
            return
        }
        let toolsAvailable = endpoint.model.supportsTools

        var wire: [WireMessage] = [.system(services.chatContext.systemPrompt(toolsAvailable: toolsAvailable,
                                                                             matchedSkills: matchedSkills))]
        // 历史（不含刚存的用户消息——它稍后以「带资料版本」加入）
        wire.append(contentsOf: services.chatContext.historyWire(for: conv).dropLast())

        // RAG + 联网
        var hits: [KnowledgeHit] = []
        if services.prefs.autoRAG, !mentions.isEmpty || !text.isBlank {
            hits = await services.knowledge.search(text, topK: 5)
        }
        var web: [WebResult] = []
        if conv.webSearch {
            web = (try? await WebSearchService.search(query: text,
                                                      endpoint: services.prefs.searchEndpoint,
                                                      apiKey: services.prefs.searchKey.isEmpty ? nil : services.prefs.searchKey)) ?? []
        }
        let (userTurn, pool) = ChatContextService.buildUserTurn(text: text, attachments: attachments,
                                                                mentionItems: mentions.map { ($0.title, $0.textContent) },
                                                                hits: hits, web: web)
        wire.append(.user(userTurn))

        var citations = pool
        let draftMessage = Message(role: .assistant, kind: .text, content: "")
        conv.messages.append(draftMessage)
        try? context.save()

        var finalText = ""
        var reasoningText = ""
        var trace: [String] = []

        do {
            var round = 0
            roundLoop: while round < 12 {
                round += 1
                try Task.checkCancellation()
                var roundText = ""
                var roundReasoning = ""
                var calls: [WireToolCall] = []

                let stream = LLMClient().streamChat(endpoint: endpoint, messages: wire,
                                                    tools: toolsAvailable ? AssistantTools.wires : nil,
                                                    reasoningEffort: ReasoningLevel(rawValue: conv.reasoningLevel)?.apiValue)
                for try await event in stream {
                    switch event {
                    case .text(let t):
                        roundText += t
                        draftMessage.content = finalText + roundText
                    case .reasoning(let r):
                        roundReasoning += r
                        draftMessage.reasoning = reasoningText + roundReasoning
                    case .toolCall(let c):
                        calls.append(c)
                    case .finished:
                        break
                    }
                }
                finalText += roundText
                reasoningText += roundReasoning

                guard !calls.isEmpty, toolsAvailable else { break }

                wire.append(WireMessage(role: "assistant",
                                        content: roundText.isEmpty ? nil : roundText,
                                        toolCalls: calls))
                for call in calls {
                    try Task.checkCancellation()
                    let outcome = await services.tools.execute(call: call)
                    switch outcome {
                    case .text(let t, let cites):
                        let offset = citations.count
                        citations += cites.map { c -> Citation in
                            var copy = c
                            copy.id += offset
                            return copy
                        }
                        wire.append(.tool(t, callID: call.id, name: call.functionName))
                        trace.append("🔧 \(call.functionName)")
                        finalText += (finalText.isEmpty ? "" : "\n\n") + "· 已完成工具 \(call.functionName)"
                        draftMessage.content = finalText
                    case .needsConfirmation(let pending):
                        let card = Message(role: .assistant, kind: .pending, content: pending.title)
                        card.pending = pending
                        conv.messages.append(card)
                        try? context.save()
                        draftMessage.content = finalText.isEmpty
                            ? "（该操作需要你确认）"
                            : finalText
                        finalize(draftMessage, text: draftMessage.content, reasoning: reasoningText,
                                 trace: trace, citations: Self.usedCitations(in: finalText, pool: citations))
                        services.chatContext.maybeCompress(conversation: conv)
                        return
                    case .error(let e):
                        wire.append(.tool("错误：\(e)", callID: call.id, name: call.functionName))
                        trace.append("⚠️ \(call.functionName)：\(e)")
                    }
                }
                continue roundLoop
            }

            finalize(draftMessage, text: finalText, reasoning: reasoningText,
                     trace: trace, citations: Self.usedCitations(in: finalText, pool: citations))
            services.chatContext.maybeCompress(conversation: conv)
            conv.updatedAt = Date()
            try? context.save()
            refresh()
        } catch is CancellationError {
            draftMessage.content = (finalText.isEmpty ? "" : finalText + "\n\n") + "⏹ 已停止"
            try? context.save()
        } catch {
            draftMessage.kindRaw = MessageKind.error.rawValue
            draftMessage.content = finalText + "\n\n❌ " + error.localizedDescription
            try? context.save()
        }
    }

    private func finalize(_ message: Message, text: String, reasoning: String,
                          trace: [String], citations: [Citation]) {
        message.content = text.isBlank ? "（完成）" : text
        message.reasoning = reasoning.isBlank ? nil : reasoning
        message.toolTrace = trace
        message.citations = citations
    }

    private func appendError(_ conv: Conversation, _ text: String) {
        let message = Message(role: .assistant, kind: .error, content: text)
        conv.messages.append(message)
        try? context.save()
    }

    static func usedCitations(in text: String, pool: [Citation]) -> [Citation] {
        guard !pool.isEmpty else { return [] }
        var ids: Set<Int> = []
        if let regex = try? NSRegularExpression(pattern: "\\[(\\d{1,3})]") {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let n = Int(ns.substring(with: m.range(at: 1))) { ids.insert(n) }
            }
        }
        return pool.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
    }

    // MARK: - 内容区「✨ 让助理处理」入口
    func assistFromArea(_ request: AssistRequest) {
        let prompt = """
        请帮我处理【\(request.area)】相关任务：\(request.text)
        可以使用工具直接读取/创建/修改/整理该区域内容；删除/覆盖/批量移动会走确认。
        """
        draft = prompt
        services.router.tab = .chat
        send()
    }

    func resend(_ message: Message) {
        guard message.role == .user, let conv = message.conversation else { return }
        draft = message.content
        current = conv
        send()
    }
}
