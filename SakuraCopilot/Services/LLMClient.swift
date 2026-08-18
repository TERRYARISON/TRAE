import Foundation

// MARK: - JSON 值（工具参数 Schema / 参数解析）
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else if let a = try? container.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "无法解析的 JSON")) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    subscript(key: String) -> JSONValue? { objectValue?[key] }

    var prettyJSON: String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func obj(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }
    static func str(_ s: String) -> JSONValue { .string(s) }
    static func int(_ n: Int) -> JSONValue { .number(Double(n)) }
    static func bool(_ b: Bool) -> JSONValue { .bool(b) }
}

// MARK: - 传输消息（OpenAI 兼容）
struct WireMessage: Codable, Hashable, Sendable {
    var role: String
    var content: String?
    var name: String?
    var toolCalls: [WireToolCall]?
    var toolCallID: String?

    init(role: String, content: String? = nil, name: String? = nil,
         toolCalls: [WireToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    static func system(_ text: String) -> WireMessage { WireMessage(role: "system", content: text) }
    static func user(_ text: String) -> WireMessage { WireMessage(role: "user", content: text) }
    static func assistant(_ text: String) -> WireMessage { WireMessage(role: "assistant", content: text) }
    static func tool(_ text: String, callID: String, name: String) -> WireMessage {
        WireMessage(role: "tool", content: text, name: name, toolCallID: callID)
    }

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        toolCalls = try c.decodeIfPresent([WireToolCall].self, forKey: .toolCalls)
        toolCallID = try c.decodeIfPresent(String.self, forKey: .toolCallID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }
}

struct WireToolCall: Codable, Hashable, Sendable {
    var id: String
    var functionName: String
    var arguments: String

    init(id: String, functionName: String, arguments: String) {
        self.id = id
        self.functionName = functionName
        self.arguments = arguments
    }

    enum CodingKeys: String, CodingKey { case id, type, function
        case name, arguments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let fn = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: .function)
        functionName = try fn.decode(String.self, forKey: .name)
        arguments = try fn.decodeIfPresent(String.self, forKey: .arguments) ?? "{}"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode("function", forKey: .type)
        var fn = c.nestedContainer(keyedBy: CodingKeys.self, forKey: .function)
        try fn.encode(functionName, forKey: .name)
        try fn.encode(arguments, forKey: .arguments)
    }

    var argumentsJSON: JSONValue {
        guard let data = arguments.data(using: .utf8) else { return .null }
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
    }
}

struct WireTool: Codable, Sendable {
    var name: String
    var description: String
    var parameters: JSONValue

    enum CodingKeys: String, CodingKey { case type, function, name, description, parameters }

    init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fn = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: .function)
        name = try fn.decode(String.self, forKey: .name)
        description = try fn.decode(String.self, forKey: .description)
        parameters = try fn.decode(JSONValue.self, forKey: .parameters)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("function", forKey: .type)
        var fn = c.nestedContainer(keyedBy: CodingKeys.self, forKey: .function)
        try fn.encode(name, forKey: .name)
        try fn.encode(description, forKey: .description)
        try fn.encode(parameters, forKey: .parameters)
    }
}

// MARK: - 流事件
enum LLMStreamEvent: Sendable {
    case text(String)
    case reasoning(String)
    case toolCall(WireToolCall)
    case finished(String?)
}

// MARK: - OpenAI 兼容客户端
struct LLMClient: Sendable {
    var session: URLSession = .shared

    nonisolated static func makeRequest(endpoint: LLMEndpoint, stream: Bool,
                                       messages: [WireMessage], tools: [WireTool]?,
                                       reasoningEffort: String?, temperature: Double?,
                                       maxTokens: Int?) throws -> URLRequest {
        struct Body: Codable {
            var model: String
            var messages: [WireMessage]
            var stream: Bool
            var tools: [WireTool]?
            var tool_choice: String?
            var reasoning_effort: String?
            var temperature: Double?
            var max_tokens: Int?
        }
        let body = Body(model: endpoint.model.id,
                        messages: messages,
                        stream: stream,
                        tools: tools,
                        tool_choice: tools != nil ? "auto" : nil,
                        reasoning_effort: reasoningEffort,
                        temperature: temperature,
                        max_tokens: maxTokens)
        guard let url = endpoint.chatURL else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !endpoint.apiKey.isEmpty {
            req.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    /// 流式对话（SSE）
    func streamChat(endpoint: LLMEndpoint, messages: [WireMessage],
                    tools: [WireTool]? = nil, reasoningEffort: String? = nil,
                    temperature: Double? = nil, maxTokens: Int? = nil)
        -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try Self.makeRequest(endpoint: endpoint, stream: true,
                                                   messages: messages, tools: tools,
                                                   reasoningEffort: reasoningEffort,
                                                   temperature: temperature, maxTokens: maxTokens)
                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    guard http.statusCode == 200 else {
                        var errText = ""
                        for try await line in bytes.lines { errText += line }
                        throw LLMError.http(http.statusCode, Self.cleanErrorMessage(errText))
                    }

                    struct StreamChunk: Decodable {
                        struct Choice: Decodable {
                            struct Delta: Decodable {
                                struct Fn: Decodable { var name: String?; var arguments: String? }
                                struct Call: Decodable { var index: Int?; var id: String?; var function: Fn? }
                                var role: String?
                                var content: String?
                                var reasoningContent: String?
                                var reasoning: String?
                                var toolCalls: [Call]?
                                enum CK: String, CodingKey {
                                    case role, content, reasoning
                                    case reasoningContent = "reasoning_content"
                                    case toolCalls = "tool_calls"
                                }
                                init(from decoder: Decoder) throws {
                                    let c = try decoder.container(keyedBy: CK.self)
                                    role = try c.decodeIfPresent(String.self, forKey: .role)
                                    content = try c.decodeIfPresent(String.self, forKey: .content)
                                    reasoningContent = try c.decodeIfPresent(String.self, forKey: .reasoningContent)
                                    reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning)
                                    toolCalls = try c.decodeIfPresent([Call].self, forKey: .toolCalls)
                                }
                            }
                            var delta: Delta?
                            var finish_reason: String?
                        }
                        var choices: [Choice]?
                    }

                    var pendingCalls: [Int: WireToolCall] = [:]

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else { continue }
                        guard let choice = chunk.choices?.first else { continue }
                        if let delta = choice.delta {
                            if let text = delta.content, !text.isEmpty {
                                continuation.yield(.text(text))
                            }
                            let rtext = delta.reasoningContent ?? delta.reasoning
                            if let rtext, !rtext.isEmpty {
                                continuation.yield(.reasoning(rtext))
                            }
                            if let calls = delta.toolCalls {
                                for call in calls {
                                    let idx = call.index ?? 0
                                    var acc = pendingCalls[idx] ?? WireToolCall(id: call.id ?? "", functionName: "", arguments: "")
                                    if let id = call.id, !id.isEmpty { acc.id = id }
                                    if let n = call.function?.name, !n.isEmpty { acc.functionName = n }
                                    if let a = call.function?.arguments { acc.arguments += a }
                                    pendingCalls[idx] = acc
                                }
                            }
                        }
                        if let finish = choice.finish_reason {
                            if finish == "tool_calls" || finish == "stop" {
                                if pendingCalls.isEmpty || finish == "stop" {
                                    // stop：可能带文本结束
                                }
                            }
                        }
                    }
                    for idx in pendingCalls.keys.sorted() {
                        let call = pendingCalls[idx]!
                        if !call.functionName.isEmpty {
                            continuation.yield(.toolCall(call))
                        }
                    }
                    continuation.yield(.finished("stop"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 单次非流式调用
    func chatOnce(endpoint: LLMEndpoint, messages: [WireMessage],
                  temperature: Double? = nil, maxTokens: Int? = nil) async throws -> String {
        let req = try Self.makeRequest(endpoint: endpoint, stream: false,
                                       messages: messages, tools: nil,
                                       reasoningEffort: nil, temperature: temperature, maxTokens: maxTokens)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http((response as? HTTPURLResponse)?.statusCode ?? -1, Self.cleanErrorMessage(text))
        }
        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { var content: String? }
                var message: Msg?
            }
            var choices: [Choice]?
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return reply.choices?.first?.message?.content ?? ""
    }

    /// 拉取远端模型列表 GET /models
    func fetchModelIDs(endpoint: LLMEndpoint) async throws -> [String] {
        guard let url = endpoint.modelsURL else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 30)
        if !endpoint.apiKey.isEmpty {
            req.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.http((response as? HTTPURLResponse)?.statusCode ?? -1, "拉取模型列表失败")
        }
        struct List: Decodable {
            struct Item: Decodable { var id: String }
            var data: [Item]?
        }
        return (try? JSONDecoder().decode(List.self, from: data))?.data.map(\.id) ?? []
    }

    static func cleanErrorMessage(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              let err = json["error"], let msg = err["message"]?.stringValue else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "未知错误" : String(trimmed.prefix(400))
        }
        return msg
    }

    /// 从模型回复中提取第一个 JSON 对象
    static func extractJSONObject(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }
}

enum LLMError: LocalizedError {
    case http(Int, String)
    case noModelConfigured
    case modelNotSupportTools(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return "接口错误(\(code))：\(msg)"
        case .noModelConfigured: return "尚未配置可用模型，请到「助理 → 模型」添加 OpenAI 兼容接口"
        case .modelNotSupportTools(let name): return "模型 \(name) 不支持工具调用（仅对话），无法派活干活"
        }
    }
}
