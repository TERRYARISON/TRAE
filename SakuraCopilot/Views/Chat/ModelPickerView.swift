import SwiftUI

// MARK: - 模型选择器（常驻胶囊点开 · 含推理档位 · 「仅对话」标注）
struct ModelPickerSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    private var chat: ChatStore { services.chat }

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let conv = chat.current ?? { chat.ensureCurrent(); return chat.current }() {
                            modelSections(conv: conv)
                        } else {
                            EmptyStateView(icon: "cpu", title: "还没有配置模型",
                                           hint: "到「助理 → 模型」添加任意 OpenAI 兼容接口")
                        }
                    }
                    .padding(16)
                }
                .navigationTitle("模型选择")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }.foregroundStyle(CyberTheme.neonPink)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelSections(conv: Conversation) -> some View {
        let currentKey = services.modelStore.currentKey(conversation: conv)

        SectionTitle(text: "模型（当前会话独立选择）", icon: "cpu")
        ForEach(services.modelStore.providers) { provider in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(provider.isActive ? CyberTheme.success : CyberTheme.textFaint)
                        .frame(width: 6, height: 6)
                    Text(provider.name)
                        .font(.cyber(14, .bold))
                        .foregroundStyle(CyberTheme.textPri)
                    if provider.isLocal { TagChip(text: "本地", color: CyberTheme.neonGold) }
                    Spacer()
                }
                if provider.models.isEmpty {
                    Text("暂无模型，去「助理 → 模型」添加")
                        .font(.cyber(11)).foregroundStyle(CyberTheme.textFaint)
                }
                ForEach(provider.models) { model in
                    let key = ModelKey.make(providerID: provider.id, modelID: model.id)
                    Button {
                        conv.modelKey = key
                        try? services.context.save()
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.name).font(.cyber(14, .medium)).foregroundStyle(CyberTheme.textPri)
                                HStack(spacing: 6) {
                                    if !model.supportsTools { TagChip(text: "仅对话", color: CyberTheme.danger) }
                                    if model.supportsReasoning { TagChip(text: "推理", color: CyberTheme.neonCyan) }
                                    Text("\(model.contextTokens / 1000)k 上下文")
                                        .font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
                                }
                            }
                            Spacer()
                            if currentKey == key {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(CyberTheme.neonPink)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(currentKey == key ? CyberTheme.neonPink.opacity(0.1) : CyberTheme.bg1.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(CyberTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CyberTheme.stroke, lineWidth: 0.8))
        }

        // 推理档位（不支持的模型自动隐藏）
        if let model = services.modelStore.modelInfo(for: currentKey ?? ""), model.supportsReasoning {
            @Bindable var conv = conv
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "推理强度 · \(model.name)", icon: "brain")
                Picker("推理强度", selection: $conv.reasoningLevel) {
                    ForEach(ReasoningLevel.allCases) { level in
                        Text(level.label).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .tint(CyberTheme.neonPurple)
                Text("Off = 不下发推理参数；Max 为最强档（部分模型可能忽略）。")
                    .font(.cyber(10)).foregroundStyle(CyberTheme.textFaint)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(CyberTheme.panel))
        }

        // 设为默认
        if let key = services.modelStore.currentKey(conversation: conv) {
            Button {
                services.modelStore.defaultModelKey = key
            } label: {
                Label("设为全局默认模型", systemImage: "star.circle")
            }
            .buttonStyle(GhostButtonStyle(tint: CyberTheme.neonGold))
            .frame(maxWidth: .infinity)

            Text("""
            说明：
            · 「仅对话」= 不支持工具调用，无法派活干活（建笔记/改文件等），其余模型可正常派活
            · 会话选中的模型只影响当前对话；新对话使用全局默认
            · 干活模型优先取支持工具调用的模型
            """)
            .font(.cyber(11))
            .foregroundStyle(CyberTheme.textFaint)
        }
    }
}
