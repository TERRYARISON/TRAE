import Foundation
import SwiftData

// MARK: - 工具执行器（助理「派活干活」的双手）
@MainActor
final class ToolExecutor {
    let context: ModelContext
    let knowledge: KnowledgeService
    let memory: MemoryService
    let skills: SkillService
    let modelStore: ModelStore
    let prefs: Preferences

    init(context: ModelContext, knowledge: KnowledgeService, memory: MemoryService,
         skills: SkillService, modelStore: ModelStore, prefs: Preferences) {
        self.context = context
        self.knowledge = knowledge
        self.memory = memory
        self.skills = skills
        self.modelStore = modelStore
        self.prefs = prefs
    }

    /// 模型发起的工具调用（含确认拦截）
    func execute(call: WireToolCall) async -> ToolOutcome {
        let args = call.argumentsJSON
        return await run(name: call.functionName, args: args, forced: false)
    }

    /// 用户确认后的执行
    func performConfirmed(_ action: PendingAction) async -> String {
        guard let data = action.argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return "参数解析失败"
        }
        let outcome = await run(name: action.toolName, args: args, forced: true)
        switch outcome {
        case .text(let text): return text
        case .error(let e): return "执行失败：\(e)"
        case .needsConfirmation: return "该操作仍需确认（异常）"
        }
    }

    // MARK: - 路由
    private func run(name: String, args: JSONValue, forced: Bool) async -> ToolOutcome {
        switch name {
        case "search_knowledge":
            guard let query = args["query"]?.stringValue else { return .error("缺少 query") }
            let hits = await knowledge.search(query, topK: 6)
            guard !hits.isEmpty else { return .text("知识库中没有检索到相关内容。") }
            var citations: [Citation] = []
            let lines = hits.enumerated().map { i, hit -> String in
                citations.append(Citation(id: i + 1, title: hit.title,
                                          snippet: String(hit.text.prefix(150)),
                                          kind: "knowledge", itemID: hit.itemID.uuidString,
                                          chunkIndex: hit.chunkIndex))
                return "[\(i + 1)] 《\(hit.title)》片段#\(hit.chunkIndex)：\(String(hit.text.prefix(300)))"
            }
            return .text("知识库检索到 \(hits.count) 个相关片段：\n" + lines.joined(separator: "\n---\n")
                         + "\n（引用请标注 [n]）", citations)
        case "read_knowledge":
            guard let idStr = args["item_id"]?.stringValue, let id = UUID(uuidString: idStr),
                  let item = knowledge.item(id: id) else { return .error("item_id 无效") }
            let chunks = Chunker.chunks(of: item.textContent)
            let start = args["start_chunk"]?.doubleValue.flatMap(Int.init) ?? 0
            let count = args["chunk_count"]?.doubleValue.flatMap(Int.init) ?? 3
            let slice = chunks.dropFirst(max(0, start)).prefix(max(1, count))
            guard !slice.isEmpty else { return .text("《\(item.title)》共 \(chunks.count) 片段，越界了。") }
            return .text("《\(item.title)》片段 \(start)..<\(start + slice.count)（共\(chunks.count)）：\n"
                         + slice.enumerated().map { "#\(start + $0.offset)\n\($0.element)" }.joined(separator: "\n\n"))
        case "list_knowledge":
            let items = knowledge.allItems()
            guard !items.isEmpty else { return .text("知识库为空。") }
            return .text(items.map { item in
                "· [\(item.id.uuidString.prefix(8))] 《\(item.title)》\(item.charCount)字 文件夹:\(item.folder ?? "未分组") 标签:\(item.tags.joined(separator: ","))"
            }.joined(separator: "\n"))
        case "add_knowledge":
            guard let title = args["title"]?.stringValue, let content = args["content"]?.stringValue else {
                return .error("缺少 title / content")
            }
            let item = knowledge.createItem(title: title, text: content,
                                            folder: args["folder"]?.stringValue ?? "助理整理",
                                            tags: ["助理"])
            return .text("已入库《\(item.title)》，ID：\(item.id.uuidString)，共 \(item.charCount) 字。")
        case "rename_knowledge_item":
            guard let idStr = args["item_id"]?.stringValue, let id = UUID(uuidString: idStr),
                  let item = knowledge.item(id: id),
                  let newTitle = args["new_title"]?.stringValue else { return .error("参数无效") }
            knowledge.rename(item: item, to: newTitle)
            return .text("已重命名为《\(newTitle)》。")
        case "move_knowledge_items":
            guard forced, let ids = args["item_ids"]?.arrayValue, let folder = args["folder"]?.stringValue else {
                guard let ids = args["item_ids"]?.arrayValue, let folder = args["folder"]?.stringValue else {
                    return .error("参数无效")
                }
                let names = ids.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
                    .compactMap { knowledge.item(id: $0) }
                return .needsConfirmation(PendingAction(
                    title: "批量移动 \(names.count) 个文档到「\(folder)」",
                    toolName: "move_knowledge_items",
                    argumentsJSON: args.prettyJSON))
            }
            let items = ids.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
                .compactMap { knowledge.item(id: $0) }
            knowledge.move(items: items, to: folder)
            return .text("已移动 \(items.count) 个文档到「\(folder)」。")
        case "delete_knowledge_item":
            guard let idStr = args["item_id"]?.stringValue, let id = UUID(uuidString: idStr),
                  let item = knowledge.item(id: id) else { return .error("item_id 无效") }
            guard forced else {
                return .needsConfirmation(PendingAction(
                    title: "删除知识库文档《\(item.title)》",
                    toolName: "delete_knowledge_item",
                    argumentsJSON: args.prettyJSON))
            }
            knowledge.delete(item: item)
            return .text("已删除《\(item.title)》。")
        case "list_notes":
            let notes = NotesLib.allNotes(context: context)
            guard !notes.isEmpty else { return .text("还没有笔记。") }
            return .text(notes.map { "· [ID:\($0.id.uuidString.prefix(8))] \($0.title)（更新于 \(Self.shortDate($0.updatedAt))）" }
                .joined(separator: "\n"))
        case "create_note":
            guard let title = args["title"]?.stringValue, let content = args["content"]?.stringValue else {
                return .error("缺少 title / content")
            }
            let note = NotesLib.create(title: title, content: content,
                                       notebookName: args["notebook"]?.stringValue,
                                       context: context)
            return .text("已创建笔记《\(note.title)》，ID：\(note.id.uuidString)（用户可在「笔记」Tab 查看）。")
        case "append_note":
            guard let idStr = args["note_id"]?.stringValue, let id = UUID(uuidString: idStr),
                  let note = NotesLib.note(id: id, context: context),
                  let content = args["content"]?.stringValue else { return .error("参数无效") }
            NotesLib.append(note, content: content)
            try? context.save()
            return .text("已向《\(note.title)》追加 \(content.count) 字。")
        case "update_note":
            guard let idStr = args["note_id"]?.stringValue, let id = UUID(uuidString: idStr),
                  let note = NotesLib.note(id: id, context: context),
                  let newContent = args["new_content"]?.stringValue else { return .error("参数无效") }
            guard forced else {
                return .needsConfirmation(PendingAction(
                    title: "覆写笔记《\(note.title)》（\(note.content.count) → \(newContent.count) 字）",
                    toolName: "update_note", argumentsJSON: args.prettyJSON))
            }
            note.content = newContent
            note.updatedAt = Date()
            try? context.save()
            return .text("已覆写《\(note.title)》。")
        case "delete_note":
            guard let idStr = args["note_id"]?.stringValue, let id = UUID(uuidString: idStr),
                  let note = NotesLib.note(id: id, context: context) else { return .error("note_id 无效") }
            guard forced else {
                return .needsConfirmation(PendingAction(
                    title: "删除笔记《\(note.title)》",
                    toolName: "delete_note", argumentsJSON: args.prettyJSON))
            }
            NotesLib.delete(note, context: context)
            return .text("已删除笔记《\(note.title)》。")
        case "list_code":
            let projects = CodeLib.projects(context: context)
            guard !projects.isEmpty else { return .text("代码库为空。") }
            var lines = projects.map { project in
                "· 项目 [ID:\(project.id.uuidString.prefix(8))] \(project.name)（\(project.language)，\(project.files.count) 个文件）"
            }
            for snippet in CodeLib.snippets(context: context) {
                lines.append("· 片段 [ID:\(snippet.id.uuidString.prefix(8))] \(snippet.title)（\(snippet.language)）")
            }
            return .text(lines.joined(separator: "\n"))
        case "create_code_project":
            guard let name = args["name"]?.stringValue else { return .error("缺少 name") }
            let project = CodeLib.createProject(name: name,
                                                desc: args["description"]?.stringValue ?? "",
                                                language: args["language"]?.stringValue ?? "Swift",
                                                context: context)
            return .text("已创建代码项目「\(project.name)」，ID：\(project.id.uuidString)。")
        case "write_code_file":
            guard let pidStr = args["project_id"]?.stringValue, let pid = UUID(uuidString: pidStr),
                  let project = CodeLib.project(id: pid, context: context),
                  let path = args["path"]?.stringValue,
                  let content = args["content"]?.stringValue else { return .error("参数无效") }
            let existing = CodeLib.file(project: project, path: path)
            if let existing, !existing.content.isBlank, !forced {
                return .needsConfirmation(PendingAction(
                    title: "覆盖代码文件 \(project.name)/\(path)（\(existing.content.count) → \(content.count) 字）",
                    toolName: "write_code_file", argumentsJSON: args.prettyJSON))
            }
            let file = CodeLib.writeFile(project: project, path: path, content: content,
                                         language: args["language"]?.stringValue, context: context)
            return .text(existing == nil
                         ? "已创建 \(file.project?.name ?? "")/\(file.name)（\(content.count) 字）。"
                         : "已覆盖 \(file.project?.name ?? "")/\(file.name)。")
        case "read_code_file":
            guard let pidStr = args["project_id"]?.stringValue, let pid = UUID(uuidString: pidStr),
                  let project = CodeLib.project(id: pid, context: context),
                  let path = args["path"]?.stringValue,
                  let file = CodeLib.file(project: project, path: path) else { return .error("参数无效") }
            return .text("文件 \(project.name)/\(file.name)（\(file.language)）：\n```\(file.language.lowercased())\n\(file.content)\n```")
        case "update_code_file":
            guard let pidStr = args["project_id"]?.stringValue, let pid = UUID(uuidString: pidStr),
                  let project = CodeLib.project(id: pid, context: context),
                  let path = args["path"]?.stringValue,
                  let find = args["find"]?.stringValue,
                  let replace = args["replace"]?.stringValue,
                  let file = CodeLib.file(project: project, path: path) else { return .error("参数无效") }
            guard file.content.contains(find) else {
                return .error("文件中没有找到要替换的文本。原文开头：" + String(file.content.prefix(120)))
            }
            file.content = file.content.replacingOccurrences(of: find, with: replace)
            file.updatedAt = Date()
            try? context.save()
            return .text("已修改 \(project.name)/\(path)：替换了 1 处。")
        case "delete_code_file":
            guard let pidStr = args["project_id"]?.stringValue, let pid = UUID(uuidString: pidStr),
                  let project = CodeLib.project(id: pid, context: context),
                  let path = args["path"]?.stringValue else { return .error("参数无效") }
            guard forced else {
                return .needsConfirmation(PendingAction(
                    title: "删除代码文件 \(project.name)/\(path)",
                    toolName: "delete_code_file", argumentsJSON: args.prettyJSON))
            }
            let ok = CodeLib.deleteFile(project: project, path: path, context: context)
            return ok ? .text("已删除 \(path)。") : .error("文件不存在")
        case "delete_code_project":
            guard let pidStr = args["project_id"]?.stringValue, let pid = UUID(uuidString: pidStr),
                  let project = CodeLib.project(id: pid, context: context) else { return .error("参数无效") }
            guard forced else {
                return .needsConfirmation(PendingAction(
                    title: "删除整个代码项目「\(project.name)」及其 \(project.files.count) 个文件",
                    toolName: "delete_code_project", argumentsJSON: args.prettyJSON))
            }
            context.delete(project)
            try? context.save()
            return .text("已删除项目「\(project.name)」。")
        case "remember":
            guard let kindRaw = args["kind"]?.stringValue,
                  let kind = MemoryCardKind(rawValue: kindRaw),
                  let content = args["content"]?.stringValue else { return .error("参数无效") }
            if kind == .persona {
                memory.personaText = content
                return .text("已更新助理人设。")
            }
            let ok = memory.addEntry(kind: kind, content: content)
            return ok ? .text("已写入「\(kind.title)」：\(content)") : .error("写入失败")
        case "forget":
            guard let keyword = args["keyword"]?.stringValue else { return .error("缺少 keyword") }
            guard forced else {
                return .needsConfirmation(PendingAction(
                    title: "删除包含「\(keyword)」的记忆条目",
                    toolName: "forget", argumentsJSON: args.prettyJSON))
            }
            let removed = memory.forget(keyword: keyword)
            return removed.isEmpty
                ? .text("没有找到包含「\(keyword)」的记忆。")
                : .text("已删除 \(removed.count) 条记忆：\n" + removed.joined(separator: "\n"))
        case "web_search":
            guard let query = args["query"]?.stringValue else { return .error("缺少 query") }
            do {
                let results = try await WebSearchService.search(query: query,
                                                                endpoint: prefs.searchEndpoint,
                                                                apiKey: prefs.searchKey.isEmpty ? nil : prefs.searchKey)
                guard !results.isEmpty else { return .text("联网搜索没有结果。") }
                var citations: [Citation] = []
                let lines = results.enumerated().map { i, r -> String in
                    citations.append(Citation(id: i + 1, title: r.title,
                                              snippet: String(r.snippet.prefix(150)),
                                              kind: "web", itemID: r.url, url: r.url))
                    return "[\(i + 1)] \(r.title)\n来源：\(r.url)\n\(String(r.snippet.prefix(300)))"
                }
                return .text("联网搜索结果：\n" + lines.joined(separator: "\n---\n") + "\n（引用请标注 [n]）", citations)
            } catch {
                return .error("搜索失败：\(error.localizedDescription)")
            }
        case "create_skill":
            guard let name = args["name"]?.stringValue,
                  let desc = args["description"]?.stringValue,
                  let prompt = args["prompt"]?.stringValue else { return .error("参数无效") }
            let triggers = args["triggers"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let steps = args["steps"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let skill = skills.create(name: name, desc: desc, triggers: triggers,
                                      prompt: prompt, steps: steps)
            return .text("已创建技能「\(skill.name)」，触发词：\(triggers.joined(separator: " / "))。")
        default:
            return .error("未知工具 \(name)")
        }
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
