import SwiftUI
import SwiftData

// MARK: - 任务中心（计划确认 / 进度 / 断点续跑 / 审计 / 产物）
struct TaskCenterView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let focusTaskID: UUID?

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        let tasks = services.engine.allTasks()
                        if tasks.isEmpty {
                            EmptyStateView(icon: "figure.archery",
                                           title: "还没有巨型任务",
                                           hint: "在对话里提出大任务\n我会先给拆解计划，确认后才开跑")
                                .padding(.top, 60)
                        }
                        ForEach(tasks) { task in
                            TaskCard(task: task, highlighted: task.id == focusTaskID)
                        }
                    }
                    .padding(16)
                }
                .navigationTitle("任务中心")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { dismiss() }.foregroundStyle(CyberTheme.neonPink)
                    }
                }
            }
        }
    }
}

// MARK: - 对话内嵌任务进度卡（阶段 + 百分比 + 当前动作，点击进入任务中心）
struct TaskProgressCard: View {
    @Environment(AppServices.self) private var services
    let taskID: UUID

    var body: some View {
        if let task = services.engine.fetch(id: taskID) {
            Button {
                services.router.focusTaskID = task.id
                services.router.showTaskCenter = true
            } label: {
                GlowCard(glow: task.state == .running) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: task.isResearch ? "doc.text.magnifyingglass" : "figure.archery")
                                .foregroundStyle(stateColor(task.state))
                            Text(task.title)
                                .font(.cyber(14, .bold))
                                .foregroundStyle(CyberTheme.textPri)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(task.percent))%")
                                .font(.cyber(13, .bold, mono: true))
                                .foregroundStyle(CyberTheme.sakura)
                        }
                        GlowProgress(percent: task.percent / 100, paused: task.state == .paused)
                        HStack(spacing: 6) {
                            TagChip(text: task.state.label, color: stateColor(task.state))
                            if task.interrupted { TagChip(text: "已中断·可续跑", color: CyberTheme.neonGold) }
                            Spacer()
                            Text(task.stage)
                                .font(.cyber(11, .medium))
                                .foregroundStyle(CyberTheme.neonCyan)
                                .lineLimit(1)
                        }
                        if !task.detail.isBlank {
                            Text(task.detail)
                                .font(.cyber(11, mono: true))
                                .foregroundStyle(CyberTheme.textSec)
                                .lineLimit(2)
                        }
                        if let plan = task.plan {
                            let done = plan.steps.filter { task.progress(of: $0.id).status == .done }.count
                            Text("步骤 \(done)/\(plan.steps.count) · 点击查看详情")
                                .font(.cyber(10, mono: true))
                                .foregroundStyle(CyberTheme.textFaint)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func stateColor(_ state: TaskState) -> Color {
        switch state {
        case .running: return CyberTheme.neonCyan
        case .awaiting: return CyberTheme.neonGold
        case .paused: return CyberTheme.neonPurple
        case .done: return CyberTheme.success
        case .failed, .cancelled: return CyberTheme.danger
        case .planning: return CyberTheme.sakura
        }
    }
}

// MARK: - 任务卡片
struct TaskCard: View {
    @Environment(AppServices.self) private var services
    let task: GiantTask
    let highlighted: Bool
    @State private var showDetail = false
    @State private var showCancel = false

    var body: some View {
        GlowCard(glow: task.state == .running) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if task.state == .running || task.state == .paused {
                    GlowProgress(percent: task.percent / 100, paused: task.state == .paused)
                    HStack {
                        Text(task.stage).font(.cyber(12, .semibold)).foregroundStyle(CyberTheme.neonCyan)
                        Spacer()
                        Text("\(Int(task.percent))%").font(.cyber(12, .bold, mono: true)).foregroundStyle(CyberTheme.sakura)
                    }
                    if !task.detail.isBlank {
                        Text(task.detail).font(.cyber(11)).foregroundStyle(CyberTheme.textSec).lineLimit(2)
                    }
                }
                controls
                if let plan = task.plan, showDetail {
                    planSection(plan)
                }
            }
            .padding(14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(highlighted ? CyberTheme.neonCyan : Color.clear, lineWidth: 1.5)
        )
        .onAppear { if highlighted { showDetail = true } }
    }

    private var stateColor: Color {
        switch task.state {
        case .running: return CyberTheme.neonCyan
        case .awaiting: return CyberTheme.neonGold
        case .paused: return CyberTheme.neonPurple
        case .done: return CyberTheme.success
        case .failed, .cancelled: return CyberTheme.danger
        case .planning: return CyberTheme.sakura
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            Image(systemName: task.isResearch ? "doc.text.magnifyingglass" : "figure.archery")
                .foregroundStyle(stateColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.cyber(15, .bold)).foregroundStyle(CyberTheme.textPri).lineLimit(2)
                HStack(spacing: 6) {
                    TagChip(text: task.state.label, color: stateColor)
                    if task.interrupted { TagChip(text: "已中断·可续跑", color: CyberTheme.neonGold) }
                    if task.isResearch { TagChip(text: "深度研究", color: CyberTheme.neonPurple) }
                }
            }
            Spacer()
            Button { showDetail.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(showDetail ? 180 : 0))
                    .foregroundStyle(CyberTheme.textFaint)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            switch task.state {
            case .awaiting:
                Button { services.engine.start(task.id) } label: {
                    Label("确认开跑", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(full: true))
                Button { showCancel = true } label: {
                    Text("放弃").font(.cyber(13, .medium))
                }
                .buttonStyle(GhostButtonStyle(tint: CyberTheme.danger))
            case .running:
                Button { services.engine.pause(task.id) } label: {
                    Label("暂停", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle(tint: CyberTheme.neonGold))
                Button { showCancel = true } label: { Text("取消") }
                    .buttonStyle(GhostButtonStyle(tint: CyberTheme.danger))
            case .paused:
                Button { services.engine.resume(task.id) } label: {
                    Label(task.interrupted ? "断点续跑" : "继续", systemImage: "arrow.clockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(full: true))
                Button { showCancel = true } label: { Text("取消") }
                    .buttonStyle(GhostButtonStyle(tint: CyberTheme.danger))
            default:
                EmptyView()
            }
        }
        .destructiveConfirm(title: "取消任务",
                             message: "取消「\(task.title)」？已完成步骤的产物仍会保留。",
                             isPresented: $showCancel) {
            services.engine.cancel(task.id)
        }
    }

    @ViewBuilder
    private func planSection(_ plan: TaskPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NeonDivider()
            SectionTitle(text: "拆解计划（\(plan.steps.count) 步 · \(plan.groupCount) 组并行）", icon: "list.bullet.rectangle")
            if !plan.summary.isBlank {
                Text(plan.summary).font(.cyber(11)).foregroundStyle(CyberTheme.textSec)
            }
            ForEach(plan.steps) { step in
                let progress = task.progress(of: step.id)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: statusIcon(progress.status))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor(progress.status))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(step.title).font(.cyber(12, .semibold)).foregroundStyle(CyberTheme.textPri)
                            TagChip(text: step.kind.label, color: CyberTheme.neonPurple)
                        }
                        if !step.detail.isBlank {
                            Text(step.detail).font(.cyber(10)).foregroundStyle(CyberTheme.textFaint).lineLimit(2)
                        }
                        if progress.status == .running || progress.progress > 0 {
                            GlowProgress(percent: progress.progress)
                        }
                        if !progress.outputSummary.isBlank {
                            Text(progress.outputSummary).font(.cyber(10, mono: true))
                                .foregroundStyle(CyberTheme.neonCyan).lineLimit(2)
                        }
                    }
                    Spacer()
                }
            }

            let artifacts = GiantTaskEngine.artifactURLs(taskID: task.id)
            if !artifacts.isEmpty {
                SectionTitle(text: "产物文件（\(artifacts.count)）", icon: "shippingbox")
                ForEach(artifacts.prefix(20), id: \.absoluteString) { url in
                    HStack {
                        Image(systemName: "doc.text").font(.system(size: 10)).foregroundStyle(CyberTheme.neonGold)
                        Text(url.lastPathComponent).font(.cyber(11, mono: true)).foregroundStyle(CyberTheme.textSec)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = GiantTaskEngine.readArtifact(taskID: task.id, name: url.lastPathComponent) ?? ""
                        } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(CyberTheme.textFaint)
                        }
                    }
                }
            }

            let audit = task.auditLog
            if !audit.isEmpty {
                SectionTitle(text: "自检审计", icon: "checkmark.shield")
                ForEach(audit.suffix(6), id: \.self) { line in
                    Text("· " + line).font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
                }
            }
        }
    }

    private func statusIcon(_ status: StepStatus) -> String {
        switch status {
        case .pending: return "circle.dotted"
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .skipped: return "minus.circle"
        }
    }

    private func statusColor(_ status: StepStatus) -> Color {
        switch status {
        case .pending: return CyberTheme.textFaint
        case .running: return CyberTheme.neonCyan
        case .done: return CyberTheme.success
        case .failed: return CyberTheme.danger
        case .skipped: return CyberTheme.textFaint
        }
    }
}
