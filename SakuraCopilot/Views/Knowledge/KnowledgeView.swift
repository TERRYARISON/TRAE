import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 知识库 Tab（文件夹 / 标签 / 搜索 / 导入 / ✨助理处理）
struct KnowledgeView: View {
    @Environment(AppServices.self) private var services
    @State private var searchText = ""
    @State private var selectedFolder: String?
    @State private var showImporter = false
    @State private var importStatus = ""
    @State private var importing = false
    @State private var openItem: KnowledgeItem?
    @State private var deleteItem: KnowledgeItem?
    @State private var showDelete = false

    private var folders: [String] { services.knowledge.allFolders() }

    private var items: [KnowledgeItem] {
        var list = services.knowledge.allItems()
        if let folder = selectedFolder {
            list = list.filter { $0.folder == folder }
        }
        if !searchText.isBlank {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.textContent.localizedCaseInsensitiveContains(searchText)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return list
    }

    var body: some View {
        WithSakuraBackground {
            VStack(spacing: 0) {
                header
                NeonDivider()
                folderBar
                if items.isEmpty {
                    EmptyStateView(icon: "books.vertical",
                                   title: "知识库还是空的",
                                   hint: "导入文档，或让助理帮你入库\n支持 txt / Markdown / PDF / 图片 OCR 等")
                        .padding(.top, 60)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(items) { item in
                                KnowledgeRow(item: item,
                                             onTap: { openItem = item },
                                             onAsk: { askAbout(item) },
                                             onDelete: { deleteItem = item; showDelete = true })
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.text, .plainText, .pdf, .image, .json, .xml, .html, .rtf, .zip],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importing = true
            Task {
                let results = await services.knowledge.importFiles(urls: urls)
                let ok = results.filter(\.ok).count
                importStatus = ok == results.count ? "已导入 \(ok) 个文件" : "导入 \(ok)/\(results.count)，部分文件提取失败"
                importing = false
            }
        }
        .sheet(item: $openItem) { item in
            KnowledgeItemDetail(item: item)
                .environment(services)
        }
        .destructiveConfirm(title: "删除文档",
                             message: "删除「\(deleteItem?.title ?? "")」及其索引？此操作不可撤销。",
                             isPresented: $showDelete) {
            if let item = deleteItem { services.knowledge.delete(item: item) }
            deleteItem = nil
        }
        .overlay(alignment: .bottom) {
            if importing || !importStatus.isBlank {
                HStack {
                    if importing { ProgressView().tint(CyberTheme.neonPink) }
                    Text(importStatus).font(.cyber(11)).foregroundStyle(CyberTheme.textSec)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(CyberTheme.panel))
                .overlay(Capsule().strokeBorder(CyberTheme.neonPink.opacity(0.5), lineWidth: 1))
                .padding(.bottom, 60)
                .onTapGesture { importStatus = "" }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("知识库").font(.cyber(20, .bold)).foregroundStyle(CyberTheme.sakura)
                Text("\(services.knowledge.allItems().count) 个文档 · 全部本地")
                    .font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
            }
            Spacer()
            Button {
                showImporter = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(CyberTheme.neonCyan)
            }
            Button {
                services.router.assistRequest = AssistRequest(area: "知识库", text: "")
            } label: {
                Label("让助理处理", systemImage: "sparkles")
                    .font(.cyber(12, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(CyberTheme.sakuraGrad))
                    .shadow(color: CyberTheme.neonPink.opacity(0.45), radius: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FolderChip(text: "全部", active: selectedFolder == nil) { selectedFolder = nil }
                ForEach(folders, id: \.self) { folder in
                    FolderChip(text: folder, active: selectedFolder == folder) { selectedFolder = folder }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func askAbout(_ item: KnowledgeItem) {
        services.router.assistRequest = AssistRequest(area: "知识库", text: "请帮我深入解读知识库文档《\(item.title)》")
    }
}

private struct FolderChip: View {
    let text: String
    let active: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.cyber(12, active ? .bold : .medium))
                .foregroundStyle(active ? .white : CyberTheme.textSec)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(active ? AnyShapeStyle(CyberTheme.sakuraGrad) : AnyShapeStyle(CyberTheme.panel)))
                .overlay(Capsule().strokeBorder(active ? Color.clear : CyberTheme.stroke, lineWidth: 1))
        }
    }
}

private struct KnowledgeRow: View {
    let item: KnowledgeItem
    let onTap: () -> Void
    let onAsk: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlowCard {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.kind == "web" ? "globe.asia.australia" : (item.kind == "digest" ? "sparkles.rectangle.stack" : "doc.text.fill"))
                        .font(.system(size: 16))
                        .foregroundStyle(CyberTheme.neonCyan)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.cyber(14, .semibold)).foregroundStyle(CyberTheme.textPri)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let folder = item.folder { TagChip(text: folder, color: CyberTheme.neonPurple) }
                            Text("\(item.charCount) 字").font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
                            ForEach(item.tags.prefix(2), id: \.self) { tag in
                                Text("#\(tag)").font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.sakura)
                            }
                        }
                        Text(item.textContent.prefix(80).replacingOccurrences(of: "\n", with: " "))
                            .font(.cyber(11)).foregroundStyle(CyberTheme.textSec)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .contextMenu {
                Button("问助理", action: onAsk)
                Button("删除", role: .destructive, action: onDelete)
            }
        }
    }
}

// MARK: - 文档详情
struct KnowledgeItemDetail: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let item: KnowledgeItem
    @State private var renameText = ""

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TagChip(text: item.folder ?? "未分组", color: CyberTheme.neonPurple)
                            ForEach(item.tags, id: \.self) { tag in
                                TagChip(text: "#\(tag)", color: CyberTheme.sakura)
                            }
                            Spacer()
                            Text("\(item.charCount) 字").font(.cyber(11, mono: true)).foregroundStyle(CyberTheme.textFaint)
                        }
                        Button {
                            services.router.assistRequest = AssistRequest(area: "知识库", text: "请帮我解读知识库文档《\(item.title)》的要点")
                            dismiss()
                        } label: {
                            Label("让助理解读 / 整理此文档", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(full: true))
                        MarkdownTextView(text: item.textContent)
                    }
                    .padding(16)
                }
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }.foregroundStyle(CyberTheme.neonPink)
                    }
                }
            }
        }
        .onAppear { renameText = item.title }
    }
}
