import SwiftUI

// MARK: - 三个内容区统一的「✨ 让助理处理」入口
struct AskAssistantSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let area: String
    let prefilled: String

    @State private var text = ""

    var body: some View {
        WithSakuraBackground {
            VStack(spacing: 0) {
                HStack {
                    Label("让助理处理 · \(area)", systemImage: "sparkles")
                        .font(.cyber(16, .bold))
                        .foregroundStyle(CyberTheme.sakura)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22))
                            .foregroundStyle(CyberTheme.textFaint)
                    }
                }
                .padding(16)

                GlowCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("想让我做什么？")
                            .font(.cyber(12, .bold)).foregroundStyle(CyberTheme.textSec)
                        TextEditor(text: $text)
                            .font(.cyber(14))
                            .foregroundStyle(CyberTheme.textPri)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                        Text("例：帮我归类这些文档 / 给项目补注释 / 批量翻译 / 整理全部笔记")
                            .font(.cyber(11)).foregroundStyle(CyberTheme.textFaint)
                    }
                    .padding(14)
                }
                .padding(.horizontal, 16)

                Button {
                    send()
                } label: {
                    Label("交给助理", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(full: true))
                .padding(16)
                .disabled(text.isBlank)

                Spacer()
            }
        }
        .onAppear {
            if text.isBlank { text = prefilled }
        }
    }

    private func send() {
        services.chat.ensureCurrent()
        services.chat.draft = "【\(area)】\(text)"
        services.router.tab = .chat
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            services.chat.send()
        }
    }
}
