import Foundation

// MARK: - 深度研究：多轮递进 → 自检补搜 → 结构化报告
enum ResearchService {
    static func buildPlan(question: String) -> TaskPlan {
        TaskPlan(
            title: "深度研究：\(String(question.prefix(24)))",
            summary: "多轮递进搜索 → 自检缺口补搜 → 输出结构化报告（结论/论据/来源/缺口），报告自动存为笔记",
            steps: [
                PlanStep(title: "拆解研究问题", detail: question,
                         kindRaw: StepKind.think.rawValue, group: 0, units: 8),
                PlanStep(title: "检索：核心概念与背景", detail: "针对研究问题检索核心概念、背景与权威定义",
                         kindRaw: StepKind.search.rawValue, group: 1, units: 10),
                PlanStep(title: "检索：最新进展与数据", detail: "针对研究问题检索最新进展、数据与案例",
                         kindRaw: StepKind.search.rawValue, group: 1, units: 10),
                PlanStep(title: "检索：不同立场与争议", detail: "针对研究问题检索不同立场、反面证据与争议点",
                         kindRaw: StepKind.search.rawValue, group: 1, units: 10),
                PlanStep(title: "自检缺口并补充检索", detail: "检查已有发现中的矛盾与缺口，补充针对性检索",
                         kindRaw: StepKind.audit.rawValue, group: 2, units: 8),
                PlanStep(title: "撰写结构化报告", detail: "输出报告：结论/论据(标来源)/来源清单/缺口与后续建议，自动存为笔记",
                         kindRaw: StepKind.report.rawValue, group: 3, units: 24)
            ])
    }
}
