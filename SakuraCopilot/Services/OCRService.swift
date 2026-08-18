import Foundation
import Vision
import UIKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - iOS 原生 OCR（Vision）
enum OCRService {
    static func recognizeText(in data: Data) async -> String {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let text = (request.results ?? []).compactMap { obs in
                        obs.topCandidates(1).first?.string
                    }.joined(separator: "\n")
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    static func recognizeText(in image: UIImage) async -> String {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return "" }
        return await recognizeText(in: data)
    }
}

// MARK: - 常见文档文本提取
enum TextExtractor {

    struct Unsupported: Error { let ext: String }

    static func extract(url fileURL: URL) async throws -> String {
        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScope { fileURL.stopAccessingSecurityScopedResource() } }

        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return await Task.detached(priority: .userInitiated) { () -> String in
                guard let doc = PDFDocument(url: fileURL) else { return "" }
                var text = ""
                for i in 0..<doc.pageCount {
                    text += doc.page(at: i)?.string ?? ""
                    text += "\n"
                }
                return text
            }.value
        case "png", "jpg", "jpeg", "heic", "webp":
            if let data = try? Data(contentsOf: fileURL) {
                return await OCRService.recognizeText(in: data)
            }
            return ""
        case "html", "htm":
            guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
            return stripHTML(raw)
        default:
            // txt / md / json / csv / 各类源代码文件
            if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                return text
            }
            if let data = try? Data(contentsOf: fileURL), let text = String(data: data, encoding: .utf8) {
                return text
            }
            throw Unsupported(ext: ext)
        }
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        if let data = html.data(using: .utf8),
           let attr = try? NSAttributedString(data: data,
                                              options: [.documentType: NSAttributedString.DocumentType.html],
                                              documentAttributes: nil) {
            text = attr.string
        } else {
            text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        return text
    }
}

// MARK: - 分块
enum Chunker {
    /// 将长文本切为重叠片段（无限输入的基础）
    static func chunks(of text: String, size: Int = 1400, overlap: Int = 180) -> [String] {
        guard !text.isEmpty else { return [] }
        let chars = Array(text)
        guard chars.count > size else { return [text] }
        var result: [String] = []
        var start = 0
        while start < chars.count {
            let end = min(start + size, chars.count)
            result.append(String(chars[start..<end]))
            if end >= chars.count { break }
            start = end - overlap
        }
        return result
    }
}
