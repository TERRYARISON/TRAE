import Foundation
import ActivityKit

// MARK: - 与主 App 共享的活动属性（两个 target 各持一份同名同构类型）
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
