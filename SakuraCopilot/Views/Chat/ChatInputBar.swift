import SwiftUI

// MARK: - 对话输入区（📎附件/📷拍照｜🌐联网 🧠深度研究｜模型｜发送）
struct ChatInputBar: View {
    @Environment(AppServices.self) private var services
    @Binding var showModelPicker: Bool
    @Binding var showAttachmentSheet: Bool
    @FocusState private var inputFocused: Bool

    private var chat: ChatStore { services.chat }

    var body: some View {
        VStack(spacing: 8) {
            if !chat.mentionIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chat.mentionIDs, id: \.self) { id in
                            if let item = services.knowledge.item(id: id) {
                                TagChip(text: "@\(item.title)", color: CyberTheme.sakura)
                            }
                        }
                    }
                }
            }

            if chat.showMentionPicker {
                KnowledgeMentionPicker()
                    .frame(height: 190)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                // 附件 / 拍照
                VStack(spacing: 6) {
                    Button { showAttachmentSheet = true } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CyberTheme.neonCyan)
                            .frame(width: 34, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9).fill(CyberTheme.panel))
                    }
                    Button { showAttachmentSheet = true } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CyberTheme.sakura)
                            .frame(width: 34, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9).fill(CyberTheme.panel))
                    }
                }

                TextField("问点什么，或 @ 知识库…", text: $chat.draft, axis: .vertical)
                    .font(.cyber(15))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16).fill(CyberTheme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(CyberTheme.panelStrokeGrad.opacity(0.7), lineWidth: 1))
                    .onChange(of: chat.draft) { _, new in
                        detectMention(new)
                    }
                    .onSubmit { chat.send() }

                // 发送 / 停止
                Button {
                    if chat.streaming { chat.stop() } else { chat.send(); inputFocused = true }
                } label: {
                    Image(systemName: chat.streaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(chat.streaming
                                         ? AnyShapeStyle(CyberTheme.danger)
                                         : AnyShapeStyle(CyberTheme.sakuraGrad))
                        .shadow(color: chat.streaming ? CyberTheme.danger.opacity(0.5) : CyberTheme.neonPink.opacity(0.5), radius: 6)
                }
                .disabled(!chat.streaming && chat.draft.isBlank && chat.attachments.isEmpty)
            }

            HStack(spacing: 8) {
                if let conv = chat.current {
                    @Bindable var conv = conv
                    ToggleCapsule(icon: "globe.asia.australia", text: "联网", isOn: $conv.webSearch)
                    ToggleCapsule(icon: "brain.head.profile", text: "深度研究", isOn: $conv.deepResearch, tint: CyberTheme.neonPurple)
                }
                Spacer()
                Button {
                    showModelPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(CyberTheme.success).frame(width: 6, height: 6)
                        Text(shortModelName)
                            .font(.cyber(11, .semibold, mono: true))
                            .foregroundStyle(CyberTheme.textPri)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CyberTheme.neonCyan)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(CyberTheme.panel))
                    .overlay(Capsule().strokeBorder(CyberTheme.neonCyan.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            Rectangle().fill(CyberTheme.bg0.opacity(0.92))
                .overlay(alignment: .top) { NeonDivider() }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var shortModelName: String {
        guard let key = services.modelStore.currentKey(conversation: chat.current),
              let (pid, mid) = ModelKey.parse(key),
              let provider = services.modelStore.providers.first(where: { $0.id == pid }) else { return "选模型" }
        let model = provider.models.first { $0.id == mid }
        return model?.name ?? mid
    }

    private func detectMention(_ text: String) {
        if let at = text.lastIndex(of: "@") {
            let tail = text[at...]
            if !tail.contains(" ") && !tail.contains("\n") {
                chat.showMentionPicker = true
                return
            }
        }
        chat.showMentionPicker = false
    }
}

// MARK: - 开关胶囊
struct ToggleCapsule: View {
    let icon: String
    let text: String
    @Binding var isOn: Bool
    var tint: Color = CyberTheme.neonCyan

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(text).font(.cyber(12, .semibold))
            }
            .foregroundStyle(isOn ? .white : CyberTheme.textFaint)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isOn ? AnyShapeStyle(tint.opacity(0.35)) : AnyShapeStyle(CyberTheme.panel))
            )
            .overlay(Capsule().strokeBorder(isOn ? tint : CyberTheme.stroke, lineWidth: isOn ? 1.2 : 1))
            .shadow(color: isOn ? tint.opacity(0.55) : .clear, radius: 5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - @ 知识库引用选择器
struct KnowledgeMentionPicker: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \KnowledgeItem.updatedAt, order: .reverse) private var items: [KnowledgeItem]

    var body: some View {
        GlowCard(corner: 14) {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "引用知识库", icon: "books.vertical")
                    .padding(.horizontal, 12).padding(.top, 10)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items.prefix(30)) { item in
                            Button {
                                services.chat.mentionIDs.append(item.id)
                                if let at = services.chat.draft.lastIndex(of: "@") {
                                    services.chat.draft = String(services.chat.draft[..<at])
                                }
                                services.chat.showMentionPicker = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 12))
                                        .foregroundStyle(CyberTheme.sakura)
                                    Text(item.title)
                                        .font(.cyber(13))
                                        .foregroundStyle(CyberTheme.textPri)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(item.charCount)字")
                                        .font(.cyber(10, mono: true))
                                        .foregroundStyle(CyberTheme.textFaint)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                        }
                        if items.isEmpty {
                            Text("知识库为空，先去导入些材料吧")
                                .font(.cyber(12)).foregroundStyle(CyberTheme.textFaint)
                                .padding(12)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                services.chat.showMentionPicker = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(CyberTheme.textFaint)
                    .padding(8)
            }
        }
    }
}
