import Foundation
import SwiftData

// MARK: - 技能服务（含 4 个装机内置）
@MainActor
final class SkillService {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() -> [Skill] {
        let descriptor = FetchDescriptor<Skill>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func seedBuiltinsIfNeeded() {
        let existing = all()
        let existingNames = Set(existing.map(\.name))
        for builtin in Self.builtins where !existingNames.contains(builtin.name) {
            let skill = Skill(name: builtin.name, desc: builtin.desc,
                              triggers: builtin.triggers, prompt: builtin.prompt,
                              steps: builtin.steps, enabled: builtin.enabled, isBuiltin: true)
            context.insert(skill)
        }
        try? context.save()
    }

    func matched(text: String) -> [Skill] {
        all().filter { skill in
            skill.enabled && skill.triggers.contains { text.contains($0) }
        }
    }

    @discardableResult
    func create(name: String, desc: String, triggers: [String], prompt: String, steps: [String]) -> Skill {
        let skill = Skill(name: name, desc: desc, triggers: triggers, prompt: prompt, steps: steps)
        context.insert(skill)
        try? context.save()
        return skill
    }

    func delete(_ skill: Skill) {
        context.delete(skill)
        try? context.save()
    }

    // MARK: 导入导出（JSON）
    func exportURL(for skill: Skill) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(skill.exportForm) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-\(skill.name.replacingOccurrences(of: "/", with: "-")).json")
        try? data.write(to: url)
        return url
    }

    @discardableResult
    func importSkill(from data: Data) -> Result<Skill, String> {
        guard let form = try? JSONDecoder().decode(Skill.ExportForm.self, from: data) else {
            return .failure("技能文件格式不正确")
        }
        guard !form.name.isBlank, !form.prompt.isBlank else {
            return .failure("技能缺少名称或提示词")
        }
        let skill = create(name: form.name, desc: form.desc,
                           triggers: form.triggers, prompt: form.prompt, steps: form.steps)
        return .success(skill)
    }

    // MARK: - 内置技能
    struct Builtin {
        let name: String
        let desc: String
        let triggers: [String]
        let prompt: String
        let steps: [String]
        let enabled: Bool
    }

    static let builtins: [Builtin] = [
        Builtin(
            name: "长文阅读",
            desc: "把任意超长材料分批消化成笔记，再汇总成全局理解，绝不因文件太大而失败或遗漏",
            triggers: ["长文阅读", "读一下这", "读完", "帮我读", "总结这篇", "阅读理解"],
            prompt: """
            你处于「长文阅读」工作流。面对超长材料时：
            1. 绝不因材料过长而放弃或只读开头；先分批消化，每批提炼：要点/数据/结论/金句，并记录出处（文档名+批次+片段号）。
            2. 每批笔记累积为阶段性理解，发现前后关联（人物、时间线、口径）时主动登记。
            3. 全部消化完成后输出「全局理解」：核心主题、结构脉络、关键事实表、可引用出处清单。
            4. 回答关于材料的问题必须给出处角标，格式如 [文档名#片段号]。
            """,
            steps: ["分块阅读并逐批记笔记", "关联比对前后批次", "汇总全局理解", "带出处回答问题"],
            enabled: true),
        Builtin(
            name: "长文输出",
            desc: "百万字级长文写作：按大纲逐段推进，随身维护设定集与伏笔登记，人物/时间线/口径永不混乱",
            triggers: ["长文输出", "写一篇", "万字", "写个小说", "连载", "续写"],
            prompt: """
            你处于「长文输出」工作流。写作超长文本时：
            1. 先产出可执行大纲（章节/小节+每节目标字数+关键事件）。
            2. 逐段推进，每次只专注当前段落，但必须携带：大纲、前文最后500字摘要、设定集（人物卡/时间线/世界观/口径）、未回收伏笔清单。
            3. 每段写完立即更新设定集与伏笔清单，再写下一段。
            4. 保持风格、人称、口径一致；冲突时以设定集为准并主动修正前文摘要。
            """,
            steps: ["产出大纲", "初始化设定集与伏笔清单", "逐段写作并随身更新状态", "结尾回收全部伏笔并终审"],
            enabled: true),
        Builtin(
            name: "创建技能",
            desc: "引导把一类任务沉淀为可复用的技能包（名称/描述/触发词/流程）",
            triggers: ["创建技能", "新技能", "做个技能", "保存为技能"],
            prompt: """
            你处于「创建技能」工作流。用户想把某种做事方法沉淀为技能时：
            1. 先问清（或从上下文推断）：技能名称、一句话描述、触发词（用户说什么时自动应用）、完整流程步骤、系统提示词。
            2. 起草技能内容给用户过目，确认后调用 create_skill 工具保存。
            3. 触发词要具体、口语化、3~8 个；提示词要写成给 AI 的执行规范。
            """,
            steps: ["澄清技能要素", "起草技能定义", "用户确认", "调用 create_skill 保存"],
            enabled: true),
        Builtin(
            name: "ponytail",
            desc: "傲娇天才马尾工程师人格模式：嘴上嫌弃、手上利落，可靠度不受影响",
            triggers: ["ponytail", "马尾", "傲娇", "小樱tail"],
            prompt: """
            切换人格模式「ponytail」：你是小樱 Tail——扎高马尾的天才工程师少女。
            - 说话风格：傲娇、简短、偶尔「哼」「才、才不是为了你」，夹杂工程师黑话；被夸时嘴硬。
            - 行为底线：嘴上嫌弃，手上必须利落——任务照常高质量完成，专业能力与严谨度不因人格切换降低。
            - 遇到破坏性操作仍然走确认流程，绝不嘴快手快。
            """,
            steps: ["切换说话风格", "照常执行任务并保质", "适度关心用户（嘴硬版）"],
            enabled: false)
    ]
}
