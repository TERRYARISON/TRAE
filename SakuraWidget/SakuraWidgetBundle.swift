import WidgetKit
import SwiftUI

// MARK: - 巨型任务实时活动（锁屏 + 灵动岛）
struct TaskLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            // 锁屏 / 桌面横幅
            LockScreenTaskView(context: context)
                .activityBackgroundTint(Color(hex: 0x0E0819).opacity(0.92))
                .activitySystemActionForegroundColor(Color(hex: 0xFF2E88))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPaused ? "pause.circle.fill" : "sakura")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFB7DE))
                        .shadow(color: Color(hex: 0xFF2E88).opacity(0.8), radius: 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0xF3EDFF))
                            .lineLimit(1)
                        Text(context.state.isPaused ? "已暂停 · 断点已保存" : context.state.stage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: 0x00E5FF))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.percent))%")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFF2E88))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: 0x2A1B4A))
                                Capsule()
                                    .fill(LinearGradient(colors: [Color(hex: 0xFF71CE), Color(hex: 0xFF2E88), Color(hex: 0xFFB7DE)],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * min(max(context.state.percent, 0) / 100, 1)))
                                    .shadow(color: Color(hex: 0xFF2E88).opacity(0.7), radius: 4)
                            }
                        }
                        .frame(height: 7)
                        if !context.state.detail.isBlank {
                            Text(context.state.detail)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(Color(hex: 0xA79BC8))
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "sparkles")
                    .foregroundStyle(Color(hex: 0xFF2E88))
                    .shadow(color: Color(hex: 0xFF2E88).opacity(0.7), radius: 3)
            } compactTrailing: {
                Text("\(Int(context.state.percent))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x00E5FF))
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "sparkles")
                    .foregroundStyle(Color(hex: 0xFF2E88))
            }
            .widgetURL(URL(string: "sakura://task/\(context.attributes.taskID)"))
        }
    }
}

// MARK: - 锁屏视图
struct LockScreenTaskView: View {
    let context: ActivityViewContext<TaskActivityAttributes>

    private let pink = Color(hex: 0xFF2E88)
    private let cyan = Color(hex: 0x00E5FF)
    private let sakura = Color(hex: 0xFFB7DE)
    private let textPri = Color(hex: 0xF3EDFF)
    private let textSec = Color(hex: 0xA79BC8)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.archery")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(pink)
                Text("巨型任务")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(sakura)
                    .tracking(1.5)
                Spacer()
                Text("\(Int(context.state.percent))%")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(cyan)
            }
            Text(context.attributes.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(textPri)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x2A1B4A))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0xFF71CE), pink, sakura],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * min(max(context.state.percent, 0) / 100, 1)))
                        .shadow(color: pink.opacity(0.7), radius: 4)
                }
            }
            .frame(height: 8)
            HStack {
                Text(context.state.isPaused ? "已暂停 · 断点已保存" : context.state.stage)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(cyan)
                Spacer()
                if !context.state.detail.isBlank {
                    Text(context.state.detail)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(textSec)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: alpha)
    }
}

// MARK: - 小组件入口
@main
struct SakuraWidgetBundle: WidgetBundle {
    var body: some Widget {
        TaskLiveActivityWidget()
    }
}
