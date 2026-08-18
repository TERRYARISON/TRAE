import Foundation
import ActivityKit

// MARK: - 灵动岛 / 锁屏实时活动
struct TaskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stage: String
        var percent: Double
        var detail: String
        var isPaused: Bool
    }
    var taskID: String
    var title: String
}

@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()
    private var activity: Activity<TaskActivityAttributes>?

    var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(taskID: UUID, title: String, stage: String, percent: Double, detail: String) {
        guard isEnabled else { return }
        end()
        let attributes = TaskActivityAttributes(taskID: taskID.uuidString, title: title)
        let state = TaskActivityAttributes.ContentState(stage: stage, percent: percent,
                                                        detail: detail, isPaused: false)
        activity = try? Activity.request(attributes: attributes,
                                         contentState: state,
                                         pushType: nil)
    }

    func update(stage: String, percent: Double, detail: String, isPaused: Bool) {
        guard let activity else { return }
        let state = TaskActivityAttributes.ContentState(stage: stage, percent: percent,
                                                        detail: detail, isPaused: isPaused)
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }
}
