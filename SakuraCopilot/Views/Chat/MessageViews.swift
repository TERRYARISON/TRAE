import SwiftUI

// MARK: - 消息气泡
struct MessageRow: View {
    @Environment(AppServices.self) private var services
    let message: Message
    var onCitation: (Citation) -> Void
    var onSummaryTap: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        switch message.kind {
        case .summary: summaryBubble
        case .task:
            if let taskID = message.taskID {
                TaskProgressCard(taskID: taskID)
            }
        case .pending: pendingCard
        default: normalBubble
        }
    }

    // MARK: 普通气泡
    private var normalBubble: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if !message.appliedSkills.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.appliedSkills, id: \.self) { name in
                        TagChip(text: "技能·\(name)", color: CyberTheme.neonMagenta)
                    }
                }
            }

            GlowCard(glow: message.role != .user) {
                VStack(alignment: .leading, spacing: 10) {
                    if let reasoning = message.reasoning, !reasoning.isBlank {
                        DisclosureGroup {
                            Text(reasoning)
                                .font(.cyber(12, mono: true))
                                .foregroundStyle(CyberTheme.textFaint)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg0.opacity(0.7)))
                        } label: {
                            Label("深度思考", systemImage: "brain.head.profile")
                                .font(.cyber(11, .semibold))
                                .foregroundStyle(CyberTheme.neonPurple)
                        }
                    }

                    MarkdownTextView(text: message.content,
                                     tint: message.kind == .error ? CyberTheme.danger
                                            : (message.role == .user ? CyberTheme.textPri : CyberTheme.textPri))

                    if !message.toolTrace.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(message.toolTrace, id: \.self) { t in
                                    TagChip(text: t, color: CyberTheme.neonCyan)
                                }
                            }
                        }
                    }

                    if !message.attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(message.attachments) { att in
                                Label(att.name, systemImage: att.kind == "image" ? "photo" : "doc")
                                    .font(.cyber(11))
                                    .foregroundStyle(CyberTheme.textSec)
                            }
                        }
                    }

                    if !message.citations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(text: "来源", icon: "link")
                            ForEach(message.citations) { citation in
                                Button { onCitation(citation) } label: {
                                    HStack(spacing: 6) {
                                        Text("[\(citation.id)]")
                                            .font(.cyber(10, .bold, mono: true))
                                            .foregroundStyle(CyberTheme.neonCyan)
                                        Text(citation.title)
                                            .font(.cyber(12))
                                            .foregroundStyle(CyberTheme.textSec)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: citation.kind == "web" ? "safari" : "doc.text.magnifyingglass")
                                            .font(.system(size: 10))
                                            .foregroundStyle(CyberTheme.textFaint)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                        .overlay(alignment: .top) { NeonDivider().opacity(0.4) }
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: message.role == .user ? 300 : .infinity, alignment: message.role == .user ? .trailing : .leading)
            .contextMenu {
                Button { UIPasteboard.general.string = message.content } label: { Label("复制", systemImage: "doc.on.doc") }
                if message.role == .user {
                    Button { services.chat.resend(message) } label: { Label("重发", systemImage: "arrow.uturn.circle") }
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: { Label("删除", systemImage: "trash") }
            }
            .destructiveConfirm(title: "删除这条消息",
                                 message: "删除后不可恢复",
                                 isPresented: $showDeleteConfirm) {
                if let conv = message.conversation {
                    conv.messages.removeAll { $0.id == message.id }
                    try? services.context.save()
                }
            }

            Text(Self.timeFormatter.string(from: message.createdAt))
                .font(.cyber(10, mono: true))
                .foregroundStyle(CyberTheme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    // MARK: 摘要气泡
    private var summaryBubble: some View {
        Button(action: onSummaryTap) {
            GlowCard(glow: false, corner: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(CyberTheme.sakura.gradient)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("早期对话已压缩为摘要（\(message.archived.count) 条）")
                            .font(.cyber(13, .semibold))
                            .foregroundStyle(CyberTheme.sakura)
                        Text("永远不会聊爆 · 点击查看被压缩的内容")
                            .font(.cyber(11))
                            .foregroundStyle(CyberTheme.textFaint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(CyberTheme.textFaint)
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(CyberTheme.sakura.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    // MARK: 待确认操作卡
    private var pendingCard: some View {
        GlowCard(corner: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("助理请求执行以下操作", systemImage: "shield.lefthalf.filled")
                    .font(.cyber(13, .bold))
                    .foregroundStyle(CyberTheme.neonGold)
                Text(message.content)
                    .font(.cyber(14, .medium))
                    .foregroundStyle(CyberTheme.textPri)
                if message.pending != nil {
                    HStack(spacing: 10) {
                        Button { services.chat.confirmPending(message) } label: { Label("确认执行", systemImage: "checkmark.circle.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                        Button { services.chat.rejectPending(message) } label: { Label("取消", systemImage: "xmark.circle") }
                            .buttonStyle(GhostButtonStyle(tint: CyberTheme.danger))
                        Spacer()
                    }
                }
            }
            .padding(14)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(CyberTheme.neonGold.opacity(0.5), lineWidth: 1))
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
