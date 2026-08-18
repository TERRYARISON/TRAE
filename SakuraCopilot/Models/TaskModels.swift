import Foundation
import SwiftData

// MARK: - 巨型任务

enum TaskState: String, Codable {
    case planning, awaiting, running, paused, done, cancelled, failed

    var label: String {
        switch self {
        case .planning: return "规划中"
        case .awaiting: return "待确认"
        case .running: return "运行中"
        case .paused: return "已暂停"
        case .done: return "已完成"
        case .cancelled: return "已取消"
        case .failed: return "失败"
        }
    }
}

enum StepKind: String, Codable {
    case ingest, think, search, write, audit, report, custom

    var label: String {
        switch self {
        case .ingest: return "消化材料"
        case .think: return "分析"
        case .search: return "检索"
        case .write: return "写作"
        case .audit: return "自检"
        case .report: return "汇总"
        case .custom: return "执行"
        }
    }

    var icon: String {
        switch self {
        case .ingest: return "fork.knife"
        case .think: return "brain.head.profile"
        case .search: return "magnifyingglass"
        case .write: return "square.and.pencil"
        case .audit: return "checkmark.shield"
        case .report: return "doc.text.magnifyingglass"
        case .custom: return "gearshape.2"
        }
    }
}

struct PlanStep: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var detail: String
    var kindRaw: String = StepKind.custom.rawValue
    var group: Int = 0
    var units: Int = 10

    var kind: StepKind { StepKind(rawValue: kindRaw) ?? .custom }
}

struct TaskPlan: Codable, Hashable {
    var title: String
    var summary: String
    var steps: [PlanStep]

    var totalUnits: Int { steps.reduce(0) { $0 + max($1.units, 1) } }
    var groupCount: Int { Set(steps.map(\.group)).count }
}

enum StepStatus: String, Codable {
    case pending, running, done, failed, skipped
}

struct StepProgress: Codable, Hashable {
    var statusRaw: String = StepStatus.pending.rawValue
    var progress: Double = 0
    var outputSummary: String = ""
    var artifactNames: [String] = []
    var startedAt: Date?
    var finishedAt: Date?

    var status: StepStatus { StepStatus(rawValue: statusRaw) ?? .pending }
}

@Model
final class GiantTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var goal: String
    var stateRaw: String
    var percent: Double
    var stage: String
    var detail: String
    var interrupted: Bool
    var isResearch: Bool
    var conversationID: UUID?
    var createdAt: Date
    var updatedAt: Date

    @Attribute(.externalStorage) var planData: Data?
    @Attribute(.externalStorage) var progressData: Data?
    @Attribute(.externalStorage) var auditLogData: Data?
    @Attribute(.externalStorage) var checkpointData: Data?

    init(id: UUID = UUID(), title: String, goal: String,
         state: TaskState = .planning, isResearch: Bool = false, conversationID: UUID? = nil) {
        self.id = id
        self.title = title
        self.goal = goal
        self.stateRaw = state.rawValue
        self.percent = 0
        self.stage = "准备"
        self.detail = ""
        self.interrupted = false
        self.isResearch = isResearch
        self.conversationID = conversationID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var state: TaskState {
        get { TaskState(rawValue: stateRaw) ?? .planning }
        set { stateRaw = newValue.rawValue; updatedAt = Date() }
    }

    var plan: TaskPlan? {
        get { planData.flatMap { try? JSONDecoder().decode(TaskPlan.self, from: $0) } }
        set { planData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var progressMap: [String: StepProgress] {
        get {
            guard let data = progressData,
                  let map = try? JSONDecoder().decode([String: StepProgress].self, from: data) else { return [:] }
            return map
        }
        set { progressData = try? JSONEncoder().encode(newValue) }
    }

    var auditLog: [String] {
        get { (try? JSONDecoder().decode([String].self, from: auditLogData ?? Data())) ?? [] }
        set { auditLogData = try? JSONEncoder().encode(newValue) }
    }

    var checkpoint: TaskCheckpoint {
        get { checkpointData.flatMap { try? JSONDecoder().decode(TaskCheckpoint.self, from: $0) } ?? TaskCheckpoint() }
        set { checkpointData = try? JSONEncoder().encode(newValue) }
    }

    func progress(of stepID: String) -> StepProgress {
        progressMap[stepID] ?? StepProgress()
    }
}

/// 断点续跑检查点：已完成步骤 / 部分进度 / 写作类任务的随身状态
struct TaskCheckpoint: Codable, Hashable {
    var completedStepIDs: [String] = []
    var partialUnits: [String: Int] = [:]
    var carry: [String: String] = [:]      // write: outline / bible / sectionIndex / charOffset
}
