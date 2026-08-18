import Foundation
import SwiftData
import Observation

// MARK: - 巨型任务引擎
@MainActor
@Observable
final class GiantTaskEngine {
    let context: ModelContext
    let modelStore: ModelStore
    let prefs: Preferences
    let knowledge: KnowledgeService
    private var runners: [UUID: Task<Void, Never>] = [:]

    init(context: ModelContext, modelStore: ModelStore, prefs: Preferences, knowledge: KnowledgeService) {
        self.context = context
        self.modelStore = modelStore
        self.prefs = prefs
        self.knowledge = knowledge
        markInterruptedOnLaunch()
    }

    // MARK: - 数据访问
    func fetch(id: UUID) -> GiantTask? {
        var d = FetchDescriptor<GiantTask>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func allTasks() -> [GiantTask] {
        let d = FetchDescriptor<GiantTask>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    /// App 被杀后恢复：运行中的任务标记为「已中断，可续跑」
    func markInterruptedOnLaunch() {
        for task in allTasks() where task.state == .running {
            task.interrupted = true
            task.state = .paused
            task.detail = "App 重启，已从断点恢复待续跑"
        }
        try? context.save()
    }

    // MARK: - 任务创建 / 计划
    @discardableResult
    func createTask(goal: String, plan: TaskPlan, isResearch: Bool,
                    conversationID: UUID?, materials: [(title: String, text: String)]) -> GiantTask {
        let task = GiantTask(title: plan.title, goal: goal,
                             state: .awaiting, isResearch: isResearch,
                             conversationID: conversationID)
        task.plan = plan
        context.insert(task)
        // 材料落盘（断点续跑的输入）
        let inputsDir = Self.inputsDir(taskID: task.id)
        for (i, m) in materials.enumerated() {
            let name = "\(String(format: "%02d", i + 1))-\(Self.sanitize(m.title)).md"
            try? m.text.write(to: inputsDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try? context.save()
        return task
    }

    func start(_ id: UUID) {
        guard let task = fetch(id: id), task.state == .awaiting || task.state == .paused else { return }
        task.interrupted = false
        task.state = .running
        try? context.save()
        runners[id] = Task { [weak self] in
            await self?.runTask(id)
        }
    }

    func pause(_ id: UUID) {
        guard let task = fetch(id: id), task.state == .running else { return }
        task.state = .paused
        task.detail = "已暂停（断点已保存）"
        runners[id]?.cancel()
        runners[id] = nil
        try? context.save()
        LiveActivityService.shared.update(stage: task.stage, percent: task.percent,
                                          detail: "已暂停", isPaused: true)
    }

    func resume(_ id: UUID) { start(id) }

    func cancel(_ id: UUID) {
        guard let task = fetch(id: id) else { return }
        task.state = .cancelled
        task.detail = "已取消"
        runners[id]?.cancel()
        runners[id] = nil
        try? context.save()
        LiveActivityService.shared.end()
    }

    // MARK: - 执行主循环（阶段间串行、阶段内并行 3 路）
    private func runTask(_ id: UUID) async {
        guard let task = fetch(id: id), let plan = task.plan else { return }
        task.state = .running
        LiveActivityService.shared.start(taskID: task.id, title: task.title,
                                         stage: "启动", percent: task.percent, detail: "准备执行")
        var checkpoint = task.checkpoint
        var contextSummary = checkpoint.carry["context"] ?? ""

        let groups = Dictionary(grouping: plan.steps) { $0.group }.sorted { $0.key < $1.key }

        do {
            for (gi, pair) in groups.enumerated() {
                let steps = pair.value.filter { !checkpoint.completedStepIDs.contains($0.id) }
                guard !steps.isEmpty else { continue }
                task.stage = "第 \(gi + 1)/\(groups.count) 阶"
                task.detail = steps.first?.title ?? ""
                saveAndLive(task)

                var pending = steps
                while !pending.isEmpty {
                    try Task.checkCancellation()
                    let wave = Array(pending.prefix(3))
                    pending.removeFirst(min(3, pending.count))

                    let results = try await withThrowingTaskGroup(of: (String, StepOutcome).self) { group in
                        for step in wave {
                            let contextNow = contextSummary
                            group.addTask {
                                try await self.runStep(step, taskID: task.id,
                                                       goal: task.goal,
                                                       contextSummary: contextNow,
                                                       checkpoint: checkpoint)
                            }
                        }
                        var collected: [(String, StepOutcome)] = []
                        for try await r in group { collected.append(r) }
                        return collected
                    }

                    for (stepID, outcome) in results {
                        try Task.checkCancellation()
                        Self.writeArtifact(taskID: task.id, index: plan.steps.firstIndex(where: { $0.id == stepID }) ?? 0,
                                           name: outcome.artifactName, text: outcome.artifactText)
                        var map = task.progressMap
                        var sp = map[stepID] ?? StepProgress()
                        sp.statusRaw = StepStatus.done.rawValue
                        sp.progress = 1
                        sp.outputSummary = outcome.summary
                        sp.artifactNames = [outcome.artifactName]
                        sp.finishedAt = Date()
                        map[stepID] = sp
                        task.progressMap = map
                        checkpoint.completedStepIDs.append(stepID)
                        checkpoint.partialUnits[stepID] = (plan.steps.first { $0.id == stepID })?.units ?? 10
                        for (k, v) in outcome.carryUpdates { checkpoint.carry[k] = v }
                        contextSummary = Self.mergeSummary(base: contextSummary, addition: outcome.summary)
                        checkpoint.carry["context"] = contextSummary
                        task.checkpoint = checkpoint
                        task.detail = outcome.summary
                        recomputePercent(task, plan: plan, checkpoint: checkpoint)
                        saveAndLive(task)
                    }
                }

                // 阶段自检审计
                if groups.count > 1 {
                    try await auditStage(task, plan: plan, checkpoint: &checkpoint, context: contextSummary)
                }
            }

            task.state = .done
            task.percent = 1
            task.stage = "完成"
            task.detail = "全部步骤完成"
            try? context.save()
            LiveActivityService.shared.end()
            completeMessage(for: task)
        } catch is CancellationError {
            if task.stateRaw != TaskState.cancelled.rawValue {
                task.state = .paused
                task.detail = "已暂停（可随时续跑）"
            }
            saveAndLive(task, paused: true)
        } catch {
            task.state = .failed
            task.detail = "失败：\(error.localizedDescription)"
            try? context.save()
            LiveActivityService.shared.end()
        }
        runners[id] = nil
    }

    // MARK: - 单步执行
    struct StepOutcome: Sendable {
        var summary: String
        var artifactName: String
        var artifactText: String
        var carryUpdates: [String: String] = [:]
    }

    private func runStep(_ step: PlanStep, taskID: UUID, goal: String,
                         contextSummary: String, checkpoint: TaskCheckpoint) async throws -> (String, StepOutcome) {
        func partial(_ ratio: Double, _ detail: String) {
            if let task = fetch(id: taskID) {
                var map = task.progressMap
                var sp = map[step.id] ?? StepProgress()
                sp.statusRaw = StepStatus.running.rawValue
                sp.progress = max(0.02, min(ratio, 0.98))
                map[step.id] = sp
                task.progressMap = map
                if let plan = task.plan { recomputePercent(task, plan: plan, checkpoint: task.checkpoint) }
                task.detail = detail
                saveAndLive(task)
            }
        }

        switch step.kind {
        case .ingest:
            let (summary, understanding) = try await runIngest(taskID: taskID, goal: goal, step: step, onPartial: partial)
            return (step.id, StepOutcome(summary: "材料消化完成：" + summary,
                                         artifactName: "全局理解.md",
                                         artifactText: understanding))

        case .think:
            let text = try await llm("""
            任务目标：\(goal)
            当前步骤：\(step.title) —— \(step.detail)
            已有进展摘要：\(contextSummary)
            请完成本步骤的分析与规划，输出结构化、可执行的结论（要点+依据+下一步建议）。
            """, maxTokens: 3000)
            return (step.id, StepOutcome(summary: "分析：" + String(text.prefix(80)),
                                         artifactName: "分析-\(Self.sanitize(step.title)).md",
                                         artifactText: text,
                                         carryUpdates: [:]))

        case .search:
            let endpoint = prefs.searchEndpoint
            let apiKey = prefs.searchKey.isEmpty ? nil : prefs.searchKey
            let results = (try? await WebSearchService.search(query: step.detail.isEmpty ? goal : step.detail,
                                                              endpoint: endpoint, apiKey: apiKey, limit: 8)) ?? []
            let raw = results.enumerated().map { i, r in
                "[\(i + 1)] \(r.title)\n来源：\(r.url)\n\(r.snippet)"
            }.joined(separator: "\n---\n")
            let digest = try await llm("""
            研究子问题：\(step.detail.isEmpty ? goal : step.detail)
            搜索结果：\(raw)
            请提炼：关键发现 / 数据 / 相互印证或矛盾的来源（标注 [n]）/ 结论。控制在 600 字内。
            """, maxTokens: 1500)
            let artifact = "## 检索：\(step.detail)\n\n### 原始结果\n\(raw)\n\n### 提炼\n\(digest)"
            return (step.id, StepOutcome(summary: "检索完成（\(results.count) 条来源）",
                                         artifactName: "检索-\(Self.sanitize(step.title)).md",
                                         artifactText: artifact))

        case .write:
            let outcome = try await runLongWrite(step: step, taskID: taskID, goal: goal,
                                                 contextSummary: contextSummary,
                                                 checkpoint: checkpoint, onPartial: partial)
            return (step.id, outcome)

        case .audit:
            let text = try await llm("""
            任务目标：\(goal)
            已完成内容摘要：\(contextSummary)
            请自检：1) 有无前后矛盾（人物/时间线/口径/数据）2) 有无遗漏的子任务 3) 质量缺口。
            输出 JSON：{"issues":[{"severity":"high|low","desc":"..."}],"missing":["..."]}
            """, maxTokens: 1200)
            var carry: [String: String] = ["audit.latest": text]
            if let data = LLMClient.extractJSONObject(from: text),
               let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
                if let issues = json["issues"]?.arrayValue {
                    for issue in issues {
                        if let sev = issue["severity"]?.stringValue, let desc = issue["desc"]?.stringValue, sev == "high" {
                            carry["audit.high"] = (carry["audit.high"] ?? "") + desc + "\n"
                        }
                    }
                }
            }
            return (step.id, StepOutcome(summary: "自检完成",
                                         artifactName: "自检-\(Self.sanitize(step.title)).md",
                                         artifactText: text, carryUpdates: carry))

        case .report:
            let artifacts = Self.artifactTexts(taskID: taskID).prefix(12)
            let joined = artifacts.map { "【\($0.name)】\n\($0.text.prefix(2000))" }.joined(separator: "\n\n")
            let template = fetch(id: taskID)?.isResearch == true
                ? """
                  按以下结构输出深度研究报告（Markdown）：
                  # 报告标题
                  ## 一、结论（直接给答案）
                  ## 二、论据（每条标注来源 [n]）
                  ## 三、来源清单（编号列出）
                  ## 四、缺口（未能证实/信息不足的部分与后续建议）
                  """
                : "请把全部过程产出汇总为最终交付物（Markdown，含结论/要点/来源/遗留事项）。"
            let report = try await llm("""
            任务目标：\(goal)
            过程产出：\(joined)
            \(template)
            """, maxTokens: 8000)
            if let task = fetch(id: taskID), task.isResearch {
                let note = NotesLib.create(title: "深度研究：\(task.title)",
                                           content: report, notebookName: "深度研究",
                                           research: true, context: context)
                _ = note
            }
            return (step.id, StepOutcome(summary: "已生成最终报告\(fetch(id: taskID)?.isResearch == true ? "（已存为笔记）" : "")",
                                         artifactName: "报告.md", artifactText: report))

        case .custom:
            let text = try await llm("""
            任务目标：\(goal)
            当前步骤：\(step.title) —— \(step.detail)
            已有进展摘要：\(contextSummary)
            请直接执行并产出本步骤成果（完整交付内容，不要省略）。
            """, maxTokens: 6000)
            return (step.id, StepOutcome(summary: "完成：" + String(text.prefix(80)),
                                         artifactName: "产出-\(Self.sanitize(step.title)).md",
                                         artifactText: text))
        }
    }

    // MARK: 无限输入：分批消化 → 全局理解
    private func runIngest(taskID: UUID, goal: String, step: PlanStep,
                           onPartial: @escaping (Double, String) -> Void) async throws -> (String, String) {
        let inputsDir = Self.inputsDir(taskID: taskID)
        var materials: [(String, String)] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: inputsDir, includingPropertiesForKeys: nil), !files.isEmpty {
            materials = files.sorted { $0.lastPathComponent < $1.lastPathComponent }.map {
                ($0.deletingPathExtension().lastPathComponent, (try? String(contentsOf: $0, encoding: .utf8)) ?? "")
            }
        }
        if materials.isEmpty {
            // 从知识库取材：按目标匹配，或全库
            let items = knowledge.allItems()
            let matched = Self.selectKnowledge(items: items, goal: goal)
            materials = matched.map { ($0.title, $0.textContent) }
        }
        guard !materials.isEmpty else { return ("没有可用材料", "本次任务没有检测到输入材料。") }
        let endpoint = try workEndpoint()
        let fullText = materials.map { "《\($0.0)》\n\($0.1)" }.joined(separator: "\n\n")
        let totalChars = fullText.count
        let understanding = try await IngestService.digest(text: fullText, title: step.title,
                                                           endpoint: endpoint,
                                                           onProgress: { ratio in
            onPartial(ratio, "消化材料 \(Int(ratio * 100))%（共 \(totalChars) 字）")
        })
        let artifact = """
        # 全局理解（\(totalChars) 字材料）
        ## 材料清单
        \(materials.map { "· 《\($0.0)》\($0.1.count) 字" }.joined(separator: "\n"))
        ## 全局理解
        \(understanding)
        """
        // 全局理解同时入库，之后提问可带出处检索
        knowledge.createItem(title: "【全局理解】\(step.title.isEmpty ? goal.prefix(20) : step.title)",
                             text: artifact, folder: "任务消化", tags: ["巨型任务", "全局理解"], kind: "digest")
        return ("共消化 \(totalChars) 字、\(materials.count) 份材料", artifact)
    }

    private func selectKnowledge(items: [KnowledgeItem], goal: String) -> [KnowledgeItem] {
        if goal.contains("全库") || goal.contains("所有") || goal.contains("整个知识库") || items.count <= 20 {
            return items
        }
        let keywords = goal.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }
        let matched = items.filter { item in
            let hay = item.title + " " + (item.folder ?? "") + " " + item.tags.joined(separator: " ")
            return keywords.contains { hay.contains($0) }
        }
        return matched.isEmpty ? items : matched
    }

    // MARK: 无限输出：大纲驱动的长文写作（随身设定集/伏笔）
    private func runLongWrite(step: PlanStep, taskID: UUID, goal: String,
                              contextSummary: String, checkpoint: TaskCheckpoint,
                              onPartial: @escaping (Double, String) -> Void) async throws -> StepOutcome {
        let endpoint = try workEndpoint()
        let target = Self.estimateTargetChars(goal)
        let sectionLen = 3000
        let sections = max(1, min(Int(ceil(Double(target) / Double(sectionLen))), 600))

        let outlineKey = "\(step.id).outline"
        let bibleKey = "\(step.id).bible"
        let indexKey = "\(step.id).sectionIndex"

        var outlineJSON = checkpoint.carry[outlineKey] ?? ""
        if outlineJSON.isEmpty {
            outlineJSON = try await llmCustom(endpoint: endpoint, messages: [
                .system("你是长文写作规划器。只输出 JSON。"),
                .user("""
                写作目标：\(goal)
                总字数约 \(target) 字，分 \(sections) 节，每节约 \(sectionLen) 字。
                输出 JSON：{"sections":[{"title":"...","brief":"本节事件/要点","characters":["..."]}], "premise":"总体设定/前提"}
                """)
            ], maxTokens: 3000)
        }
        var bible = checkpoint.carry[bibleKey] ?? "{\"characters\":[],\"timeline\":[],\"settings\":[],\"foreshadow\":[],\"style\":\"\"}"
        var sectionIndex = Int(checkpoint.carry[indexKey] ?? "0") ?? 0

        let fileURL = Self.artifactsDir(taskID: taskID).appendingPathComponent("正文.md")
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            try "# \(goal.prefix(40))\n\n（目标 \(target) 字 · \(sections) 节）\n\n大纲：\(outlineJSON)\n\n---\n\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        while sectionIndex < sections {
            try Task.checkCancellation()
            onPartial(Double(sectionIndex) / Double(sections), "写作第 \(sectionIndex + 1)/\(sections) 节")
            let tail = Self.fileTail(url: fileURL, chars: 600)
            let sectionBrief = Self.outlineBrief(outlineJSON, index: sectionIndex)
            let body = try await llmCustom(endpoint: endpoint, messages: [
                .system("你是顶级长文作者。只输出正文，不要标题编号、不要解释。保持与前文无缝衔接。"),
                .user("""
                总目标：\(goal)
                设定集（必须严格遵守）：\(bible)
                本节任务：\(sectionBrief)
                前文结尾（接着写）：...\(tail)
                请写本节约 \(sectionLen) 字。
                """)
            ], maxTokens: 4500)

            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(("\n\n" + body).utf8))
            try handle.close()

            // 更新设定集
            bible = try await llmCustom(endpoint: endpoint, messages: [
                .system("只输出 JSON。"),
                .user("""
                原设定集：\(bible)
                本节新增内容：\(String(body.prefix(1500)))
                请合并更新设定集（人物/时间线/世界观/新增伏笔/回收伏笔/文风），输出：
                {"characters":[],"timeline":[],"settings":[],"foreshadow":[],"style":""}
                """)
            ], maxTokens: 1500)

            sectionIndex += 1
            if let task = fetch(id: taskID) {
                var cp = task.checkpoint
                cp.carry[outlineKey] = outlineJSON
                cp.carry[bibleKey] = bible
                cp.carry[indexKey] = String(sectionIndex)
                task.checkpoint = cp
                try? context.save()
            }
        }

        let chars = ((try? String(contentsOf: fileURL, encoding: .utf8)) ?? "").count
        let carry: [String: String] = [outlineKey: outlineJSON, bibleKey: bible, indexKey: String(sectionIndex)]
        return StepOutcome(summary: "长文完成：\(sections) 节 / 约 \(chars) 字",
                           artifactName: "正文.md",
                           artifactText: "正文已直接写入产出文件（\(chars) 字）。\n\n最新设定集：\(bible)",
                           carryUpdates: carry)
    }

    // MARK: 阶段自检 + 自动补救
    private func auditStage(_ task: GiantTask, plan: TaskPlan,
                            checkpoint: inout TaskCheckpoint, context: String) async throws {
        try Task.checkCancellation()
        task.detail = "阶段自检中…"
        saveAndLive(task)
        let issues = try await llm("""
        任务目标：\(task.goal)
        步骤：\(plan.steps.map { "\($0.kind.label)：\($0.title)" }.joined(separator: "；"))
        已完成内容摘要：\(context)
        自检有无：矛盾/遗漏/质量缺口。输出 JSON：{"issues":[{"severity":"high|low","desc":"..."}]}
        无问题则输出 {"issues":[]}
        """, maxTokens: 900)

        var log = task.auditLog
        var highIssues: [String] = []
        if let data = LLMClient.extractJSONObject(from: issues),
           let json = try? JSONDecoder().decode(JSONValue.self, from: data),
           let arr = json["issues"]?.arrayValue {
            for issue in arr {
                guard let desc = issue["desc"]?.stringValue else { continue }
                let sev = issue["severity"]?.stringValue ?? "low"
                log.append("\(sev == "high" ? "⚠️" : "ℹ️") 自检：\(desc)")
                if sev == "high" { highIssues.append(desc) }
            }
        }
        if highIssues.isEmpty {
            log.append("✅ 阶段自检通过")
        } else {
            let fix = try await llm("""
            任务目标：\(task.goal)
            发现的问题：\(highIssues.joined(separator: "\n"))
            已有进展：\(context)
            请输出补救方案与修正后的内容（直接可用的交付物）。
            """, maxTokens: 4000)
            Self.writeArtifact(taskID: task.id, index: plan.steps.count + log.count,
                               name: "补救.md", text: fix)
            checkpoint.carry["context"] = Self.mergeSummary(base: checkpoint.carry["context"] ?? "",
                                                            addition: "【已补救】" + highIssues.joined(separator: "；"))
            log.append("🔧 已自动补救 \(highIssues.count) 个高优问题")
        }
        task.auditLog = Array(log.suffix(60))
        task.checkpoint = checkpoint
        try? context.save()
    }

    // MARK: - 进度 / 产物
    private func recomputePercent(_ task: GiantTask, plan: TaskPlan, checkpoint: TaskCheckpoint) {
        let total = max(plan.totalUnits, 1)
        var done: Double = 0
        let map = task.progressMap
        for step in plan.steps {
            let p = map[step.id]?.progress ?? (checkpoint.completedStepIDs.contains(step.id) ? 1 : 0)
            done += p * Double(max(step.units, 1))
        }
        task.percent = min(done / Double(total), 0.999)
    }

    private func saveAndLive(_ task: GiantTask, paused: Bool = false) {
        task.updatedAt = Date()
        try? context.save()
        if task.state == .running || paused {
            LiveActivityService.shared.update(stage: task.stage, percent: task.percent,
                                              detail: task.detail, isPaused: paused)
        }
    }

    private func completeMessage(for task: GiantTask) {
        guard let conversationID = task.conversationID,
              let conv = (try? context.fetch(FetchDescriptor<Conversation>()))?.first(where: { $0.id == conversationID })
        else { return }
        let files = Self.artifactURLs(taskID: task.id).map { "· \($0.lastPathComponent)" }.joined(separator: "\n")
        let extra = task.isResearch ? "\n报告已自动保存到「笔记 → 深度研究」。" : ""
        let message = Message(role: .assistant, kind: .text,
                              content: "✅ 巨型任务「\(task.title)」已完成。\n产出文件：\n\(files)\(extra)\n可在任务卡或「任务中心」查看全部过程与产出。",
                              taskID: task.id)
        conv.messages.append(message)
        conv.updatedAt = Date()
        try? context.save()
    }

    // MARK: - LLM 辅助
    private func workEndpoint() throws -> LLMEndpoint {
        guard let endpoint = modelStore.workEndpoint() else { throw LLMError.noModelConfigured }
        return endpoint
    }

    private func llm(_ prompt: String, maxTokens: Int) async throws -> String {
        let endpoint = try workEndpoint()
        return try await LLMClient().chatOnce(endpoint: endpoint, messages: [.user(prompt)],
                                              temperature: 0.4, maxTokens: maxTokens)
    }

    private func llmCustom(endpoint: LLMEndpoint, messages: [WireMessage], maxTokens: Int) async throws -> String {
        try await LLMClient().chatOnce(endpoint: endpoint, messages: messages,
                                       temperature: 0.7, maxTokens: maxTokens)
    }

    // MARK: - 计划生成
    func makePlan(goal: String, materialsNote: String?) async -> TaskPlan {
        if let endpoint = modelStore.workEndpoint() {
            let prompt = """
            用户提出一个可能很大的任务，请拆解为可执行计划。
            任务：\(goal)
            \(materialsNote.map { "材料情况：\($0)" } ?? "")
            步骤类型只能是：ingest(消化材料) think(分析规划) search(联网检索) write(长文写作) audit(自检) report(汇总交付) custom(其他执行)。
            规则：能并行的步骤用相同的 group（整数，从0开始递增）；最后必须包含 report 汇总步骤；units 为工作量估计(1~50)。
            只输出 JSON：
            {"title":"...","summary":"...","steps":[{"title":"...","detail":"具体做什么","kind":"...","group":0,"units":10}]}
            """
            if let text = try? await LLMClient().chatOnce(endpoint: endpoint, messages: [.user(prompt)],
                                                          temperature: 0.3, maxTokens: 2000),
               let data = LLMClient.extractJSONObject(from: text),
               let json = try? JSONDecoder().decode(JSONValue.self, from: data),
               let plan = Self.parsePlan(json) {
                return plan
            }
        }
        return Self.fallbackPlan(goal: goal)
    }

    static func parsePlan(_ json: JSONValue) -> TaskPlan? {
        guard let title = json["title"]?.stringValue,
              let stepsJSON = json["steps"]?.arrayValue, !stepsJSON.isEmpty else { return nil }
        var steps: [PlanStep] = []
        for s in stepsJSON {
            guard let st = s["title"]?.stringValue else { continue }
            let kindRaw = s["kind"]?.stringValue ?? StepKind.custom.rawValue
            let kind = StepKind(rawValue: kindRaw) ?? .custom
            steps.append(PlanStep(title: st,
                                  detail: s["detail"]?.stringValue ?? "",
                                  kindRaw: kind.rawValue,
                                  group: s["group"]?.doubleValue.flatMap(Int.init) ?? 0,
                                  units: s["units"]?.doubleValue.flatMap(Int.init) ?? 10))
        }
        guard !steps.isEmpty else { return nil }
        return TaskPlan(title: title, summary: json["summary"]?.stringValue ?? "", steps: steps)
    }

    static func fallbackPlan(goal: String) -> TaskPlan {
        let isWriting = goal.contains("写") && (goal.contains("万字") || goal.contains("小说") || goal.contains("长文") || goal.contains("连载"))
        return TaskPlan(title: String(goal.prefix(24)), summary: "自动拆解的计划", steps: [
            PlanStep(title: "消化全部材料", detail: "分批读完所有输入材料并形成全局理解", kindRaw: StepKind.ingest.rawValue, group: 0, units: 25),
            PlanStep(title: "分析与规划", detail: "基于全局理解制定执行方案", kindRaw: StepKind.think.rawValue, group: 1, units: 10),
            PlanStep(title: isWriting ? "长文写作" : "主体执行",
                     detail: isWriting ? "按大纲逐节写作，维护设定集与伏笔" : "执行任务主体部分",
                     kindRaw: (isWriting ? StepKind.write : StepKind.custom).rawValue, group: 2, units: 40),
            PlanStep(title: "自检审计", detail: "检查矛盾/遗漏并补救", kindRaw: StepKind.audit.rawValue, group: 3, units: 10),
            PlanStep(title: "汇总交付", detail: "汇总全部产出为最终交付物", kindRaw: StepKind.report.rawValue, group: 4, units: 15)
        ])
    }

    // MARK: - 文件产物
    static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[\\\\/:*?\"<>|\\n]", with: "-", options: .regularExpression)
        return String(cleaned.prefix(24)).trimmingCharacters(in: .whitespaces)
    }

    static func tasksRoot() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artifacts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func artifactsDir(taskID: UUID) -> URL {
        let dir = tasksRoot().appendingPathComponent(taskID.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func inputsDir(taskID: UUID) -> URL {
        let dir = artifactsDir(taskID: taskID).appendingPathComponent("inputs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func writeArtifact(taskID: UUID, index: Int, name: String, text: String) {
        let url = artifactsDir(taskID: taskID)
            .appendingPathComponent("\(String(format: "%02d", index))-\(sanitize(name))")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func readArtifact(taskID: UUID, name: String) -> String? {
        let dir = artifactsDir(taskID: taskID)
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.contains(sanitize(name)) {
                return try? String(contentsOf: f, encoding: .utf8)
            }
        }
        return nil
    }

    static func artifactURLs(taskID: UUID) -> [URL] {
        let dir = artifactsDir(taskID: taskID)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent != "inputs" && !($0.lastPathComponent.hasPrefix(".")) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func artifactTexts(taskID: UUID) -> [(name: String, text: String)] {
        artifactURLs(taskID: taskID).map {
            ($0.lastPathComponent, (try? String(contentsOf: $0, encoding: .utf8)) ?? "")
        }
    }

    static func fileTail(url: URL, chars: Int) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return String(text.suffix(chars))
    }

    static func outlineBrief(_ outlineJSON: String, index: Int) -> String {
        guard let data = outlineJSON.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let sections = json["sections"]?.arrayValue,
              index < sections.count,
              let brief = sections[index]["brief"]?.stringValue else {
            return "第 \(index + 1) 节（按大纲推进）"
        }
        let title = sections[index]["title"]?.stringValue ?? ""
        return "\(title)：\(brief)"
    }

    static func estimateTargetChars(_ goal: String) -> Int {
        if let m = goal.range(of: "(\\d+(?:\\.\\d+)?)\\s*万", options: .regularExpression) {
            let num = Double(goal[m].replacingOccurrences(of: "万", with: "").trimmingCharacters(in: .whitespaces)) ?? 1
            return max(Int(num * 10000), 2000)
        }
        if let m = goal.range(of: "(\\d{3,})\\s*字", options: .regularExpression) {
            let num = Int(goal[m].replacingOccurrences(of: "字", with: "").trimmingCharacters(in: .whitespaces)) ?? 3000
            return max(num, 2000)
        }
        return 6000
    }

    static func mergeSummary(base: String, addition: String) -> String {
        guard !base.isEmpty else { return addition }
        var merged = base + "\n· " + addition
        if merged.count > 6000 {
            merged = String(merged.suffix(6000))
        }
        return merged
    }
}

// MARK: - 无限输入：分批消化管线
enum IngestService {
    struct Paused: Error {}

    static func digest(text: String, title: String, endpoint: LLMEndpoint,
                       onProgress: @escaping (Double) -> Void) async throws -> String {
        let chunks = Chunker.chunks(of: text, size: 9000, overlap: 200)
        guard !chunks.isEmpty else { return "" }

        var digests: [String] = []
        var done = 0
        let total = chunks.count
        for start in stride(from: 0, to: total, by: 3) {
            try Task.checkCancellation()
            let batch = Array(chunks[start..<min(start + 3, total)])
            let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for (i, chunk) in batch.enumerated() {
                    group.addTask {
                        let text = try await LLMClient().chatOnce(endpoint: endpoint, messages: [
                            .system("你是长材料消化器。输出要点清单：核心事实/数据/结论/关键原文（保留可定位的出处描述）。"),
                            .user("材料批次 #\(start + i)：\n\(chunk)")
                        ], temperature: 0.3, maxTokens: 1500)
                        return (i, text)
                    }
                }
                var out: [(Int, String)] = []
                for try await r in group { out.append(r) }
                return out.sorted { $0.0 < $1.0 }.map(\.1)
            }
            digests.append(contentsOf: results)
            done += batch.count
            onProgress(Double(done) / Double(total))
        }

        // 层级合并
        var level = digests
        while level.count > 1 {
            try Task.checkCancellation()
            var merged: [String] = []
            for start in stride(from: 0, to: level.count, by: 6) {
                let batch = Array(level[start..<min(start + 6, level.count)])
                merged.append(try await LLMClient().chatOnce(endpoint: endpoint, messages: [
                    .system("合并多份材料笔记为一份更全局的笔记：去重、整合、保留全部关键信息与出处。"),
                    .user(batch.enumerated().map { "笔记\($0.offset)：\n\($0.element)" }.joined(separator: "\n\n"))
                ], temperature: 0.3, maxTokens: 2000))
            }
            level = merged
        }
        return level.first ?? ""
    }
}
