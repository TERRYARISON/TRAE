import SwiftUI
import SwiftData

// MARK: - 左抽屉：历史会话
struct HistoryDrawer: View {
    @Environment(AppServices.self) private var services
    let close: () -> Void
    @State private var searchText = ""
    @State private var renameTarget: Conversation?
    @State private var renameText = ""
    @State private var deleteTarget: Conversation?
    @State private var showDeleteConfirm = false

    private var chat: ChatStore { services.chat }
    private var filtered: [Conversation] {
        let all = chat.conversations
        guard !searchText.isBlank else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        WithSakuraBackground {
            VStack(spacing: 0) {
                HStack {
                    Label("历史会话", systemImage: "clock.arrow.circlepath")
                        .font(.cyber(18, .bold))
                        .foregroundStyle(CyberTheme.sakura)
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(CyberTheme.textFaint)
                    }
                }
                .padding(16)

                TextField("搜索会话…", text: $searchText)
                    .font(.cyber(14))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(CyberTheme.bg0))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CyberTheme.neonPurple.opacity(0.4), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                Button {
                    chat.newConversation()
                    close()
                } label: {
                    Label("开启新对话", systemImage: "plus.bubble.fill")
                        .font(.cyber(14, .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(full: true))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if chat.conversations.isEmpty {
                    EmptyStateView(icon: "tray", title: "还没有对话", hint: "点上方按钮开始")
                        .padding(.top, 60)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { conv in
                                HistoryRow(conv: conv,
                                           isActive: chat.current?.id == conv.id,
                                           onTap: { chat.open(conv); close() },
                                           onRename: { renameTarget = $0; renameText = $0.title },
                                           onDelete: { deleteTarget = $0; showDeleteConfirm = true })
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 30)
                    }
                }
                Spacer(minLength: 0)
            }
            .alert("重命名会话", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("会话标题", text: $renameText)
                Button("取消", role: .cancel) { renameTarget = nil }
                Button("保存") {
                    if let target = renameTarget {
                        chat.rename(target, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? target.title : renameText)
                    }
                    renameTarget = nil
                }.tint(CyberTheme.neonPink)
            }
            .destructiveConfirm(title: "删除此会话",
                                 message: "删除「\(deleteTarget?.title ?? "")」及其全部消息？此操作不可撤销。",
                                 isPresented: $showDeleteConfirm) {
                if let target = deleteTarget { chat.deleteConversation(target) }
                deleteTarget = nil
            }
        }
    }
}

private struct HistoryRow: View {
    let conv: Conversation
    let isActive: Bool
    let onTap: () -> Void
    let onRename: (Conversation) -> Void
    let onDelete: (Conversation) -> Void

    var body: some View {
        GlowCard(glow: isActive) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: conv.pinned ? "pin.fill" : "bubble.left.fill")
                        .foregroundStyle(isActive ? CyberTheme.neonPink : CyberTheme.textFaint)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conv.title).font(.cyber(14, .semibold))
                            .foregroundStyle(CyberTheme.textPri)
                            .lineLimit(1)
                        Text(conv.updatedAt, format: .dateTime.month().day().hour().minute())
                            .font(.cyber(10, mono: true))
                            .foregroundStyle(CyberTheme.textFaint)
                        Text("\(conv.messages.count) 条消息")
                            .font(.cyber(10, mono: true))
                            .foregroundStyle(CyberTheme.textSec)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .contextMenu {
                Button("重命名") { onRename(conv) }
                Button("置顶 / 取消") { conv.pinned.toggle() }
                Button("删除", role: .destructive) { onDelete(conv) }
            }
        }
    }
}
