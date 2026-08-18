import SwiftUI
import SwiftData

// MARK: - 代码库 Tab（项目 / 文件 / 片段 · ✨助理处理）
struct CodeLibraryView: View {
    @Environment(AppServices.self) private var services
    @State private var mode = 0 // 0 项目 1 片段
    @State private var openProject: CodeProject?
    @State private var openSnippet: CodeSnippet?
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectLang = "Swift"
    @State private var deleteProject: CodeProject?
    @State private var showDeleteProject = false

    private var projects: [CodeProject] { CodeLib.projects(context: services.context) }
    private var snippets: [CodeSnippet] { CodeLib.snippets(context: services.context) }

    var body: some View {
        WithSakuraBackground {
            VStack(spacing: 0) {
                header
                NeonDivider()
                Picker("", selection: $mode) {
                    Text("项目").tag(0)
                    Text("代码片段").tag(1)
                }
                .pickerStyle(.segmented)
                .tint(CyberTheme.neonPink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if mode == 0 {
                    if projects.isEmpty {
                        EmptyStateView(icon: "chevron.left.forwardslash.chevron.right",
                                       title: "还没有代码项目",
                                       hint: "新建项目，或让助理帮你建")
                            .padding(.top, 50)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(projects) { project in
                                    ProjectRow(project: project,
                                               onTap: { openProject = project },
                                               onAsk: { ask(project) },
                                               onDelete: { deleteProject = project; showDeleteProject = true })
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                } else {
                    if snippets.isEmpty {
                        EmptyStateView(icon: "scissors",
                                       title: "还没有代码片段",
                                       hint: "收藏常用片段，助理可读写")
                            .padding(.top, 50)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(snippets) { snippet in
                                    SnippetRow(snippet: snippet, onTap: { openSnippet = snippet })
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
        .alert("新建代码项目", isPresented: $showNewProject) {
            TextField("项目名", text: $newProjectName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                if !newProjectName.isBlank {
                    _ = CodeLib.createProject(name: newProjectName, desc: "", language: newProjectLang,
                                              context: services.context)
                }
                newProjectName = ""
            }.tint(CyberTheme.neonPink)
        }
        .sheet(item: $openProject) { project in
            ProjectDetail(project: project)
                .environment(services)
        }
        .sheet(item: $openSnippet) { snippet in
            SnippetDetail(snippet: snippet)
                .environment(services)
        }
        .destructiveConfirm(title: "删除项目",
                             message: "删除「\(deleteProject?.name ?? "")」及其全部文件？此操作不可撤销。",
                             isPresented: $showDeleteProject) {
            if let project = deleteProject {
                services.context.delete(project)
                try? services.context.save()
            }
            deleteProject = nil
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("代码库").font(.cyber(20, .bold)).foregroundStyle(CyberTheme.sakura)
                Text("\(projects.count) 项目 · \(snippets.count) 片段")
                    .font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
            }
            Spacer()
            Button { showNewProject = true } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 21))
                    .foregroundStyle(CyberTheme.neonCyan)
            }
            Button {
                services.router.assistRequest = AssistRequest(area: "代码库", text: "")
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

    private func ask(_ project: CodeProject) {
        services.router.assistRequest = AssistRequest(area: "代码库", text: "请帮我审查并整理代码项目「\(project.name)」")
    }
}

private struct ProjectRow: View {
    let project: CodeProject
    let onTap: () -> Void
    let onAsk: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlowCard {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(CyberTheme.neonPurple)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.cyber(14, .semibold)).foregroundStyle(CyberTheme.textPri)
                        HStack(spacing: 6) {
                            TagChip(text: project.language, color: CyberTheme.neonCyan)
                            Text("\(project.files.count) 文件").font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
                        }
                        if !project.descText.isBlank {
                            Text(project.descText).font(.cyber(11)).foregroundStyle(CyberTheme.textSec).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11))
                        .foregroundStyle(CyberTheme.textFaint)
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

private struct SnippetRow: View {
    let snippet: CodeSnippet
    let onTap: () -> Void

    var body: some View {
        GlowCard {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "scissors")
                        .font(.system(size: 14))
                        .foregroundStyle(CyberTheme.neonGold)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snippet.title).font(.cyber(13, .semibold)).foregroundStyle(CyberTheme.textPri).lineLimit(1)
                        TagChip(text: snippet.language, color: CyberTheme.neonCyan)
                        Text(snippet.code.prefix(120))
                            .font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textSec)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
    }
}

// MARK: - 项目详情（文件列表 + 代码查看）
struct ProjectDetail: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let project: CodeProject
    @State private var openFile: CodeFile?
    @State private var deleteFile: CodeFile?
    @State private var showDeleteFile = false

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TagChip(text: project.language, color: CyberTheme.neonCyan)
                            Text("\(project.files.count) 个文件").font(.cyber(11, mono: true)).foregroundStyle(CyberTheme.textFaint)
                            Spacer()
                        }
                        Button {
                            services.router.assistRequest = AssistRequest(area: "代码库", text: "请帮我审查并整理代码项目「\(project.name)」：补注释、找 bug、优化结构")
                            dismiss()
                        } label: {
                            Label("让助理处理此项目", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(full: true))

                        if project.files.isEmpty {
                            EmptyStateView(icon: "doc.badge.plus", title: "暂无文件", hint: "让助理帮你写第一个文件")
                        }
                        ForEach(project.files) { file in
                            GlowCard(glow: false) {
                                Button { openFile = file } label: {
                                    HStack {
                                        Image(systemName: "doc.text").foregroundStyle(CyberTheme.neonCyan)
                                        Text(file.name).font(.cyber(13, .medium)).foregroundStyle(CyberTheme.textPri)
                                        Spacer()
                                        Text("\(file.content.count) 字").font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
                                    }
                                    .padding(11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .contextMenu {
                                    Button("删除", role: .destructive) { deleteFile = file; showDeleteFile = true }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .navigationTitle(project.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }.foregroundStyle(CyberTheme.neonPink)
                    }
                }
            }
        }
        .sheet(item: $openFile) { file in
            CodeFileViewer(file: file)
                .environment(services)
        }
        .destructiveConfirm(title: "删除文件", message: "删除「\(deleteFile?.name ?? "")」？",
                             isPresented: $showDeleteFile) {
            if let file = deleteFile { _ = CodeLib.deleteFile(project: project, path: file.name, context: services.context) }
            deleteFile = nil
        }
    }
}

struct CodeFileViewer: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let file: CodeFile
    @State private var text = ""

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    CodeBlockView(code: text, language: file.language)
                        .padding(14)
                }
                .navigationTitle(file.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }.foregroundStyle(CyberTheme.neonPink)
                    }
                }
            }
        }
        .onAppear { text = file.content }
    }
}

struct SnippetDetail: View {
    @Environment(\.dismiss) private var dismiss
    let snippet: CodeSnippet

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        TagChip(text: snippet.language, color: CyberTheme.neonCyan)
                        CodeBlockView(code: snippet.code, language: snippet.language)
                    }
                    .padding(14)
                }
                .navigationTitle(snippet.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }.foregroundStyle(CyberTheme.neonPink)
                    }
                }
            }
        }
    }
}
