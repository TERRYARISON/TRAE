import Foundation

// MARK: - 联网搜索（SearXNG 兼容 JSON 接口，可自配）

struct WebResult: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var url: String
    var snippet: String
}

enum WebSearchService {

    static func search(query: String, endpoint: String, apiKey: String?, limit: Int = 6) async throws -> [WebResult] {
        let base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, var comps = URLComponents(string: base) else {
            throw LLMError.http(0, "未配置联网搜索服务，请到「助理 → 偏好」填写搜索接口地址")
        }
        let existing = comps.queryItems ?? []
        comps.queryItems = existing + [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.http((response as? HTTPURLResponse)?.statusCode ?? -1, "搜索服务无响应或未开放 JSON 接口")
        }

        struct Reply: Decodable {
            struct Item: Decodable { var title: String?; var url: String?; var content: String? }
            var results: [Item]?
        }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        let items = (reply?.results ?? []).prefix(limit).enumerated().map { idx, item in
            WebResult(id: idx,
                      title: item.title ?? "未命名结果",
                      url: item.url ?? "",
                      snippet: item.content ?? "")
        }
        return Array(items)
    }
}
