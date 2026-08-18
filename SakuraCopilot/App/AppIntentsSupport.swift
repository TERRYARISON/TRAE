import Foundation
import AppIntents

// MARK: - Action 按钮默认动作：暂停 / 继续大任务
struct PauseResumeGiantTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "暂停或继续大任务"
    static var description = IntentDescription("暂停或继续当前正在运行的巨型任务（可在系统设置 → Action 按钮中指定）")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = AppServices.shared.engine
        let tasks = engine.allTasks()
        if let running = tasks.first(where: { $0.state == .running }) {
            engine.pause(running.id)
            return .result(dialog: "已暂停「\(running.title)」，断点已保存")
        }
        if let paused = tasks.first(where: { $0.state == .paused && !$0.interrupted || $0.state == .paused }) {
            engine.resume(paused.id)
            return .result(dialog: "继续执行「\(paused.title)」")
        }
        return .result(dialog: "当前没有可暂停或继续的大任务")
    }
}

struct SakuraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PauseResumeGiantTaskIntent(),
                    phrases: ["\(.applicationName)暂停任务", "\(.applicationName)继续任务"],
                    shortTitle: "暂停/继续大任务",
                    systemImageName: "pause.circle")
    }
}
