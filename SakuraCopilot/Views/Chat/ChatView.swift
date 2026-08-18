import SwiftUI
import SwiftData

// MARK: - 对话页（双抽屉：左历史 · 右助理）
struct ChatView: View {
    @Environment(AppServices.self) private var services
    @State private var showHistory = false
    @State private var showAssistantDrawer = false
    @State private var showModelPicker = false
    @State private var showAttachmentSheet = false
    @State private var sourceCitation: Citation?
    @State private var summaryMessage: Message?

    private var chat: ChatStore { services.chat }

    var body: some View {
        ZStack {
            SakuraBackground()

            VStack(spacing: 0) {
                topBar
                NeonDivider()
                messageList
                ChatInputBar(showModelPicker: $showModelPicker,
                             showAttachmentSheet: $showAttachmentSheet)
            }

            SideDrawer(side: .left, isShown: $showHistory) {
                HistoryDrawer(close: { showHistory = false })
            }
            SideDrawer(side: .right, isShown: $showAssistantDrawer) {
                AssistantDrawer(close: { showAssistantDrawer = false })
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet()
                .environment(services)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentSheet()
                .environment(services)
                .presentationDetents([.medium])
        }
        .sheet(item: $sourceCitation) { citation in
            SourceDetailSheet(citation: citation)
                .presentationDetents([.medium])
                .environment(services)
        }
        .sheet(item: $summaryMessage) { message in
            SummaryExpandSheet(message: message)
                .presentationDetents([.large])
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { showHistory = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CyberTheme.textPri)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(CyberTheme.panel))
                    .overlay(Circle().strokeBorder(CyberTheme.neonPink.opacity(0.5), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("樱花副驾")
                    .font(.cyber(16, .bold))
                    .foregroundStyle(CyberTheme.textPri)
                Text(chat.current.map { _ in services.modelStore.displayName(services.modelStore.currentKey(conversation: $0)) } ?? "未配置模型")
                    .font(.cyber(10, .medium, mono: true))
                    .foregroundStyle(CyberTheme.neonCyan)
                    .lineLimit(1)
            }
            Spacer()

            Button {
                withAnimation { showAssistantDrawer = true }
            } label: {
                Text("樱")
                    .font(.cyber(16, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(CyberTheme.sakuraGrad))
                    .shadow(color: CyberTheme.neonPink.opacity(0.6), radius: 8)
                    .overlay(
                        Circle().strokeBorder(CyberTheme.sakura.opacity(0.8), lineWidth: 1.5)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let conv = chat.current {
                    LazyVStack(spacing: 14) {
                        if conv.visibleMessages.isEmpty {
                            EmptyStateView(icon: "sparkles.rectangle.stack",
                                           title: "我是你的专属樱花副驾",
                                           hint: "直接对话 · @知识库提问 · 巨型任务我会先给计划再开跑\n所有数据只存在本机")
                                .padding(.top, 60)
                        }
                        ForEach(conv.visibleMessages) { message in
                            MessageRow(message: message,
                                       onCitation: { sourceCitation = $0 },
                                       onSummaryTap: { summaryMessage = message })
                                .id(message.id)
                        }
                        if chat.streaming {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { i in
                                    Circle().fill(CyberTheme.neonPink)
                                        .frame(width: 6, height: 6)
                                        .opacity(0.4 + Double(i) * 0.3)
                                }
                                Text("思考中…").font(.cyber(11)).foregroundStyle(CyberTheme.textFaint)
                            }
                            .id("streaming")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    EmptyStateView(icon: "bubble.left.and.bubble.right",
                                   title: "开始新对话",
                                   hint: "点击输入框开始与你的专属助理交流")
                        .padding(.top, 100)
                }
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.current?.messages.count) {
                if let last = chat.current?.visibleMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: chat.streaming) {
                if chat.streaming { proxy.scrollTo("streaming", anchor: .bottom) }
            }
        }
    }
}

// MARK: - 来源详情
struct SourceDetailSheet: View {
    @Environment(AppServices.self) private var services
    let citation: Citation

    var body: some View {
        WithSakuraBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TagChip(text: kindLabel, color: CyberTheme.neonCyan)
                        Spacer()
                        Text("#\(citation.id)").font(.cyber(12, .bold, mono: true)).foregroundStyle(CyberTheme.textFaint)
                    }
                    Text(citation.title)
                        .font(.cyber(18, .bold))
                        .foregroundStyle(CyberTheme.textPri)
                    GlowCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("片段内容").font(.cyber(12, .bold)).foregroundStyle(CyberTheme.textSec)
                            Text(citation.snippet)
                                .font(.cyber(13))
                                .foregroundStyle(CyberTheme.textPri)
                                .textSelection(.enabled)
                            if citation.chunkIndex > 0 {
                                Text("片段 #\(citation.chunkIndex)").font(.cyber(11, mono: true)).foregroundStyle(CyberTheme.textFaint)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if citation.kind == "web", let url = URL(string: citation.url ?? "") {
                        Link(destination: url) {
                            Label("打开网页来源", systemImage: "safari")
                                .font(.cyber(14, .semibold))
                                .foregroundStyle(CyberTheme.neonCyan)
                        }
                    }
                    if citation.kind == "knowledge",
                       let itemID = UUID(uuidString: citation.itemID),
                       let item = services.knowledge.item(id: itemID) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("文档：\(item.title) · \(item.charCount) 字", systemImage: "doc.text")
                                .font(.cyber(13, .semibold))
                                .foregroundStyle(CyberTheme.textPri)
                            let chunks = Chunker.chunks(of: item.textContent)
                            if citation.chunkIndex < chunks.count {
                                ScrollView {
                                    Text(chunks[citation.chunkIndex])
                                        .font(.cyber(13))
                                        .foregroundStyle(CyberTheme.textSec)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 320)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var kindLabel: String {
        switch citation.kind {
        case "web": return "联网来源"
        case "note": return "笔记"
        case "code": return "代码"
        default: return "知识库"
        }
    }
}

// MARK: - 摘要气泡展开
struct SummaryExpandSheet: View {
    let message: Message
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        GlowCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("压缩摘要", systemImage: "sparkles")
                                    .font(.cyber(14, .bold)).foregroundStyle(CyberTheme.sakura)
                                Text(message.content).font(.cyber(14)).foregroundStyle(CyberTheme.textPri)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        SectionTitle(text: "被压缩的原始对话（\(message.archived.count) 条）", icon: "archivebox")
                        ForEach(message.archived) { arch in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(arch.role == "user" ? "🧑 我" : "🤖 助理")
                                    .font(.cyber(11, .bold)).foregroundStyle(CyberTheme.textFaint)
                                Text(arch.content).font(.cyber(13)).foregroundStyle(CyberTheme.textSec)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(CyberTheme.bg1.opacity(0.8)))
                        }
                    }
                    .padding(16)
                }
                .navigationTitle("早期对话")
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
