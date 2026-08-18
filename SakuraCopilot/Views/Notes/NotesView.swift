import SwiftUI
import SwiftData

// MARK: - 笔记 Tab（笔记本 + Markdown · ✨助理处理）
struct NotesView: View {
    @Environment(AppServices.self) private var services
    @State private var searchText = ""
    @State private var editingNote: Note?
    @State private var newTitle = ""
    @State private var showNew = false
    @State private var deleteNote: Note?
    @State private var showDelete = false

    private var notes: [Note] {
        var list = NotesLib.allNotes(context: services.context)
        if !searchText.isBlank {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list.sorted { ($0.pinned ? 0 : 1, $0.updatedAt.timeIntervalSince1970)
                             < ($1.pinned ? 0 : 1, $1.updatedAt.timeIntervalSince1970) }
    }

    var body: some View {
        WithSakuraBackground {
            VStack(spacing: 0) {
                header
                NeonDivider()
                if notes.isEmpty {
                    EmptyStateView(icon: "note.text",
                                   title: "还没有笔记",
                                   hint: "手动新建，或对助理说「帮我记一下…」\n深度研究报告也会自动存为笔记")
                        .padding(.top, 60)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(notes) { note in
                                NoteRow(note: note,
                                        onTap: { editingNote = note },
                                        onAsk: { ask(note) },
                                        onDelete: { deleteNote = note; showDelete = true })
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .alert("新建笔记", isPresented: $showNew) {
            TextField("标题", text: $newTitle)
            Button("取消", role: .cancel) {}
            Button("创建") {
                if !newTitle.isBlank {
                    _ = NotesLib.create(title: newTitle, content: "", notebookName: nil,
                                        context: services.context)
                }
                newTitle = ""
            }.tint(CyberTheme.neonPink)
        }
        .sheet(item: $editingNote) { note in
            NoteEditor(note: note)
                .environment(services)
        }
        .destructiveConfirm(title: "删除笔记",
                             message: "删除「\(deleteNote?.title ?? "")」？此操作不可撤销。",
                             isPresented: $showDelete) {
            if let note = deleteNote { NotesLib.delete(note, context: services.context) }
            deleteNote = nil
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("笔记").font(.cyber(20, .bold)).foregroundStyle(CyberTheme.sakura)
                Text("\(NotesLib.allNotes(context: services.context).count) 篇 · Markdown")
                    .font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
            }
            Spacer()
            Button { showNew = true } label: {
                Image(systemName: "square.and.pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(CyberTheme.neonCyan)
            }
            Button {
                services.router.assistRequest = AssistRequest(area: "笔记", text: "")
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

    private func ask(_ note: Note) {
        services.router.assistRequest = AssistRequest(area: "笔记", text: "请帮我润色并扩写笔记《\(note.title)》")
    }
}

private struct NoteRow: View {
    let note: Note
    let onTap: () -> Void
    let onAsk: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlowCard {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: note.isResearchReport ? "doc.text.magnifyingglass" : "note.text")
                        .font(.system(size: 15))
                        .foregroundStyle(note.isResearchReport ? CyberTheme.neonGold : CyberTheme.sakura)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(CyberTheme.neonPink) }
                            Text(note.title).font(.cyber(14, .semibold)).foregroundStyle(CyberTheme.textPri).lineLimit(1)
                            if note.isResearchReport { TagChip(text: "研究报告", color: CyberTheme.neonGold) }
                        }
                        Text(note.content.prefix(100).replacingOccurrences(of: "\n", with: " "))
                            .font(.cyber(11)).foregroundStyle(CyberTheme.textSec)
                            .lineLimit(2)
                        Text(note.updatedAt, format: .dateTime.month().day().hour().minute())
                            .font(.cyber(10, mono: true)).foregroundStyle(CyberTheme.textFaint)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .contextMenu {
                Button("问助理", action: onAsk)
                Button(note.pinned ? "取消置顶" : "置顶") { note.pinned.toggle() }
                Button("删除", role: .destructive, action: onDelete)
            }
        }
    }
}

// MARK: - 笔记编辑器
struct NoteEditor: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var text = ""
    @State private var saved = false
    @State private var showPreview = false

    var body: some View {
        WithSakuraBackground {
            NavigationStack {
                VStack(spacing: 0) {
                    if showPreview {
                        ScrollView {
                            MarkdownTextView(text: text).padding(16)
                        }
                    } else {
                        TextEditor(text: $text)
                            .font(.cyber(14, .regular, mono: true))
                            .foregroundStyle(CyberTheme.textPri)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12)
                    }
                }
                .navigationTitle(note.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(showPreview ? "编辑" : "预览") { showPreview.toggle() }
                            .foregroundStyle(CyberTheme.neonCyan)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(saved ? "已保存" : "保存") {
                            note.content = text
                            note.updatedAt = Date()
                            try? services.context.save()
                            withAnimation { saved = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { saved = false } }
                        }
                        .foregroundStyle(saved ? CyberTheme.success : CyberTheme.neonPink)
                    }
                }
            }
        }
        .onAppear { text = note.content }
        .onDisappear {
            note.content = text
            note.updatedAt = Date()
            try? services.context.save()
        }
    }
}
