import Foundation

// MARK: - 助理可用的工具（Function Calling）

struct ToolSpec {
    let name: String
    let description: String
    let parameters: JSONValue

    var wire: WireTool { WireTool(name: name, description: description, parameters: parameters) }
}

enum ToolOutcome {
    case text(String, [Citation])
    case needsConfirmation(PendingAction)
    case error(String)

    /// 便捷构造（无引用）
    static func text(_ s: String) -> ToolOutcome { .text(s, []) }
}

/// 需要二次确认的工具集合（删除 / 覆盖 / 批量移动）
enum DestructiveTools {
    static let confirmRequired: Set<String> = [
        "delete_knowledge_item", "move_knowledge_items",
        "update_note", "delete_note",
        "write_code_file_overwrite", "delete_code_file", "delete_code_project",
        "forget"
    ]
}

enum AssistantTools {

    static func schema(_ props: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .str("object"),
            "properties": .object(props),
            "required": .array(required.map { .str($0) })
        ])
    }

    static let all: [ToolSpec] = [
        ToolSpec(name: "search_knowledge",
                 description: "在用户知识库中全文检索，返回带出处(文档名+片段编号)的相关片段，用于回答知识库相关问题",
                 parameters: schema([
                    "query": .object(["type": .str("string"), "description": .str("检索关键词")])
                 ], required: ["query"])),
        ToolSpec(name: "read_knowledge",
                 description: "读取知识库某文档的指定片段内容",
                 parameters: schema([
                    "item_id": .object(["type": .str("string"), "description": .str("文档ID")]),
                    "start_chunk": .object(["type": .str("integer"), "description": .str("起始片段号，从0开始")]),
                    "chunk_count": .object(["type": .str("integer"), "description": .str("读取片段数，默认3")])
                 ], required: ["item_id"])),
        ToolSpec(name: "list_knowledge",
                 description: "列出知识库全部文档（ID/标题/字数/文件夹/标签）",
                 parameters: schema([:], required: [])),
        ToolSpec(name: "add_knowledge",
                 description: "新建一条知识库文档",
                 parameters: schema([
                    "title": .object(["type": .str("string")]),
                    "content": .object(["type": .str("string"), "description": .str("文档全文")]),
                    "folder": .object(["type": .str("string"), "description": .str("所属文件夹，可选")])
                 ], required: ["title", "content"])),
        ToolSpec(name: "rename_knowledge_item",
                 description: "重命名知识库文档",
                 parameters: schema([
                    "item_id": .object(["type": .str("string")]),
                    "new_title": .object(["type": .str("string")])
                 ], required: ["item_id", "new_title"])),
        ToolSpec(name: "move_knowledge_items",
                 description: "批量移动知识库文档到某文件夹（需用户确认）",
                 parameters: schema([
                    "item_ids": .object(["type": .str("array"), "items": .object(["type": .str("string")])]),
                    "folder": .object(["type": .str("string")])
                 ], required: ["item_ids", "folder"])),
        ToolSpec(name: "delete_knowledge_item",
                 description: "删除知识库文档（需用户确认）",
                 parameters: schema([
                    "item_id": .object(["type": .str("string")])
                 ], required: ["item_id"])),
        ToolSpec(name: "list_notes",
                 description: "列出全部笔记（ID/标题/笔记本）",
                 parameters: schema([:], required: [])),
        ToolSpec(name: "create_note",
                 description: "新建笔记。用户说「帮我记一下」等即调用此工具",
                 parameters: schema([
                    "title": .object(["type": .str("string")]),
                    "content": .object(["type": .str("string"), "description": .str("Markdown 正文")]),
                    "notebook": .object(["type": .str("string"), "description": .str("笔记本名，可选")])
                 ], required: ["title", "content"])),
        ToolSpec(name: "append_note",
                 description: "向已有笔记追加内容",
                 parameters: schema([
                    "note_id": .object(["type": .str("string")]),
                    "content": .object(["type": .str("string")])
                 ], required: ["note_id", "content"])),
        ToolSpec(name: "update_note",
                 description: "整体覆写笔记内容（需用户确认）",
                 parameters: schema([
                    "note_id": .object(["type": .str("string")]),
                    "new_content": .object(["type": .str("string")])
                 ], required: ["note_id", "new_content"])),
        ToolSpec(name: "delete_note",
                 description: "删除笔记（需用户确认）",
                 parameters: schema([
                    "note_id": .object(["type": .str("string")])
                 ], required: ["note_id"])),
        ToolSpec(name: "list_code",
                 description: "列出代码项目、文件与片段",
                 parameters: schema([:], required: [])),
        ToolSpec(name: "create_code_project",
                 description: "新建代码项目",
                 parameters: schema([
                    "name": .object(["type": .str("string")]),
                    "description": .object(["type": .str("string")]),
                    "language": .object(["type": .str("string")])
                 ], required: ["name"])),
        ToolSpec(name: "write_code_file",
                 description: "在项目中创建代码文件；若文件已存在且非空则为覆盖写（需用户确认）",
                 parameters: schema([
                    "project_id": .object(["type": .str("string")]),
                    "path": .object(["type": .str("string"), "description": .str("文件名或相对路径")]),
                    "content": .object(["type": .str("string")]),
                    "language": .object(["type": .str("string")])
                 ], required: ["project_id", "path", "content"])),
        ToolSpec(name: "read_code_file",
                 description: "读取代码文件内容",
                 parameters: schema([
                    "project_id": .object(["type": .str("string")]),
                    "path": .object(["type": .str("string")])
                 ], required: ["project_id", "path"])),
        ToolSpec(name: "update_code_file",
                 description: "精准修改代码文件：把 find 文本替换为 replace",
                 parameters: schema([
                    "project_id": .object(["type": .str("string")]),
                    "path": .object(["type": .str("string")]),
                    "find": .object(["type": .str("string")]),
                    "replace": .object(["type": .str("string")])
                 ], required: ["project_id", "path", "find", "replace"])),
        ToolSpec(name: "delete_code_file",
                 description: "删除代码文件（需用户确认）",
                 parameters: schema([
                    "project_id": .object(["type": .str("string")]),
                    "path": .object(["type": .str("string")])
                 ], required: ["project_id", "path"])),
        ToolSpec(name: "delete_code_project",
                 description: "删除整个代码项目（需用户确认）",
                 parameters: schema([
                    "project_id": .object(["type": .str("string")])
                 ], required: ["project_id"])),
        ToolSpec(name: "remember",
                 description: "写入记忆。用户说「以后叫我XX」「记住…」等即调用。kind: persona(助理人设)/profile(我的档案)/long_term(长期记忆)/tips(经验技巧)",
                 parameters: schema([
                    "kind": .object(["type": .str("string"), "enum": .array(["persona", "profile", "long_term", "tips"].map { .str($0) })]),
                    "content": .object(["type": .str("string")])
                 ], required: ["kind", "content"])),
        ToolSpec(name: "forget",
                 description: "按关键词删除记忆条目（需用户确认）。用户说「删掉关于X的记忆」即调用",
                 parameters: schema([
                    "keyword": .object(["type": .str("string")])
                 ], required: ["keyword"])),
        ToolSpec(name: "web_search",
                 description: "联网搜索最新信息，返回带来源链接的结果",
                 parameters: schema([
                    "query": .object(["type": .str("string")])
                 ], required: ["query"])),
        ToolSpec(name: "create_skill",
                 description: "创建新技能（提示词工作流包）",
                 parameters: schema([
                    "name": .object(["type": .str("string")]),
                    "description": .object(["type": .str("string")]),
                    "triggers": .object(["type": .str("array"), "items": .object(["type": .str("string")])]),
                    "prompt": .object(["type": .str("string"), "description": .str("技能系统提示词")]),
                    "steps": .object(["type": .str("array"), "items": .object(["type": .str("string")])])
                 ], required: ["name", "description", "prompt"]))
    ]

    static let names: Set<String> = Set(all.map(\.name))
    static var wires: [WireTool] { all.map(\.wire) }
}
