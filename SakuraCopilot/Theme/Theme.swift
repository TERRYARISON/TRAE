import SwiftUI

// MARK: - 赛博朋克樱花 · 主题
enum CyberTheme {
    static let bg0        = Color(hex: 0x07030F)
    static let bg1        = Color(hex: 0x0E0819)
    static let panel      = Color(hex: 0x140C24).opacity(0.92)
    static let panelHi    = Color(hex: 0x1C1030)
    static let stroke     = Color(hex: 0x2A1B4A)

    static let neonPink   = Color(hex: 0xFF2E88)
    static let neonMagenta= Color(hex: 0xFF71CE)
    static let sakura     = Color(hex: 0xFFB7DE)
    static let neonCyan   = Color(hex: 0x00E5FF)
    static let neonPurple = Color(hex: 0x9D4EDD)
    static let neonGold   = Color(hex: 0xFFD166)

    static let textPri    = Color(hex: 0xF3EDFF)
    static let textSec    = Color(hex: 0xA79BC8)
    static let textFaint  = Color(hex: 0x6B5B8F)

    static let danger     = Color(hex: 0xFF3B5C)
    static let success    = Color(hex: 0x3DFFA2)

    static let pinkCyan   = LinearGradient(colors: [neonPink, neonPurple, neonCyan],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sakuraGrad = LinearGradient(colors: [neonMagenta, neonPink, sakura],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let panelStrokeGrad = LinearGradient(colors: [neonPink.opacity(0.55), neonPurple.opacity(0.35), neonCyan.opacity(0.55)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: alpha)
    }
}

extension Font {
    static func cyber(_ size: CGFloat, _ weight: Font.Weight = .regular, mono: Bool = false) -> Font {
        if mono { return .system(size: size, weight: weight, design: .monospaced) }
        return .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - 字数 / Token 估算
extension String {
    /// 粗略 token 估算（中英混排）：约 每 1.5 个字符 ≈ 1 token
    var approxTokens: Int { Int((Double(count) / 1.5).rounded()) + 4 }
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
