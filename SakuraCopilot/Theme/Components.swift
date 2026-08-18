import SwiftUI
import UIKit

// MARK: - 霓虹卡片
struct GlowCard<Content: View>: View {
    var glow: Bool = true
    var corner: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(CyberTheme.panel, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(CyberTheme.panelStrokeGrad, lineWidth: 1)
            )
            .shadow(color: CyberTheme.neonPink.opacity(glow ? 0.18 : 0), radius: glow ? 10 : 0)
    }
}

// MARK: - 按钮
struct PrimaryButtonStyle: ButtonStyle {
    var full: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cyber(15, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, full ? nil : 16)
            .frame(maxWidth: full ? .infinity : nil)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(CyberTheme.sakuraGrad)
                    .opacity(configuration.isPressed ? 0.6 : 1)
            )
            .shadow(color: CyberTheme.neonPink.opacity(0.45), radius: configuration.isPressed ? 3 : 8)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = CyberTheme.neonCyan
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cyber(14, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().strokeBorder(tint.opacity(0.7), lineWidth: 1))
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.18 : 0.07)))
    }
}

// MARK: - 标签
struct TagChip: View {
    let text: String
    var color: Color = CyberTheme.neonCyan
    var body: some View {
        Text(text)
            .font(.cyber(11, .medium, mono: true))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.8))
            .lineLimit(1)
    }
}

struct NeonDivider: View {
    var body: some View {
        Rectangle().fill(CyberTheme.panelStrokeGrad).frame(height: 0.8).opacity(0.6)
    }
}

struct SectionTitle: View {
    let text: String
    var icon: String = "sparkles"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(CyberTheme.neonPink).font(.system(size: 13, weight: .semibold))
            Text(text).font(.cyber(13, .bold)).foregroundStyle(CyberTheme.textSec).tracking(1.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 空态
struct EmptyStateView: View {
    let icon: String
    let title: String
    var hint: String = ""
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(CyberTheme.panelStrokeGrad)
                .shadow(color: CyberTheme.neonPink.opacity(0.5), radius: 10)
            Text(title).font(.cyber(15, .semibold)).foregroundStyle(CyberTheme.textSec)
            if !hint.isEmpty {
                Text(hint).font(.cyber(12)).foregroundStyle(CyberTheme.textFaint)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - 破坏性操作二次确认
struct DestructiveConfirm: ViewModifier {
    let title: String
    let message: String
    @Binding var isPresented: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            Button("确认删除", role: .destructive, action: action)
            Button("取消", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

extension View {
    func destructiveConfirm(title: String, message: String, isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        modifier(DestructiveConfirm(title: title, message: message, isPresented: isPresented, action: action))
    }
}

// MARK: - 侧滑抽屉
struct SideDrawer<Content: View>: View {
    enum Side { case left, right }
    let side: Side
    @Binding var isShown: Bool
    var width: CGFloat = UIScreen.main.bounds.width * 0.82
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: side == .left ? .leading : .trailing) {
            if isShown {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.22)) { isShown = false } }
                    .transition(.opacity)
                content()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(
                        LinearGradient(colors: [CyberTheme.bg1, CyberTheme.bg0],
                                       startPoint: side == .left ? .leading : .trailing, endPoint: .opposite)
                            .ignoresSafeArea()
                    )
                    .overlay(alignment: side == .left ? .trailing : .leading) {
                        NeonDivider()
                    }
                    .transition(.move(edge: side == .left ? .leading : .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isShown)
    }
}

// MARK: - 分享
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension View {
    @MainActor
    func shareSheet(_ items: [Any]) -> some View {
        sheet(isPresented: .constant(true)) { ActivityShareSheet(items: items) }
    }
}

// MARK: - 进度条
struct GlowProgress: View {
    var percent: Double // 0...1
    var paused: Bool = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CyberTheme.stroke.opacity(0.6))
                Capsule()
                    .fill(paused ? AnyShapeStyle(CyberTheme.neonGold.gradient) : AnyShapeStyle(CyberTheme.sakuraGrad))
                    .frame(width: max(6, geo.size.width * min(max(percent, 0), 1)))
                    .shadow(color: paused ? CyberTheme.neonGold.opacity(0.6) : CyberTheme.neonPink.opacity(0.7), radius: 5)
            }
        }
        .frame(height: 8)
        .animation(.spring(duration: 0.4), value: percent)
    }
}

// MARK: - 代码块
struct CodeBlockView: View {
    let code: String
    var language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.cyber(10, .bold, mono: true))
                    .foregroundStyle(CyberTheme.neonCyan)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.cyber(11, .medium))
                        .foregroundStyle(CyberTheme.textSec)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(CyberTheme.bg0.opacity(0.8))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.cyber(12, .regular, mono: true))
                    .foregroundStyle(CyberTheme.sakura)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0A0618)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(CyberTheme.neonCyan.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - 轻量 Markdown 渲染（代码块 + 行内样式）
struct MarkdownTextView: View {
    let text: String
    var tint: Color = CyberTheme.textPri

    enum Block: Hashable, Identifiable {
        case text(String)
        case code(String?, String)
        var id: Int { hashValue }
    }

    var body: some View {
        let blocks = Self.blocks(of: text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block {
                case .text(let t):
                    Text(Self.attr(t, tint: tint))
                        .font(.cyber(15))
                        .foregroundStyle(tint)
                        .textSelection(.enabled)
                case .code(let lang, let code):
                    CodeBlockView(code: code, language: lang)
                }
            }
        }
    }

    static func blocks(of source: String) -> [Block] {
        var result: [Block] = []
        var pending = ""
        var inFence = false
        var fenceLang: String?
        var fenceBody = ""
        for line in source.components(separatedBy: "\n") {
            if !inFence, line.hasPrefix("```") {
                if !pending.isBlank { result.append(.text(pending)) }
                pending = ""
                inFence = true
                fenceLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                fenceBody = ""
            } else if inFence, line.hasPrefix("```") {
                result.append(.code(fenceLang, fenceBody))
                inFence = false
                fenceLang = nil
                fenceBody = ""
            } else if inFence {
                fenceBody += line + "\n"
            } else {
                pending += line + "\n"
            }
        }
        if !pending.isBlank { result.append(.text(pending)) }
        if inFence, !fenceBody.isBlank { result.append(.code(fenceLang, fenceBody)) }
        return result
    }

    static func attr(_ s: String, tint: Color) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        guard var attr = try? AttributedString(markdown: s, options: options) else {
            return AttributedString(s)
        }
        attr.foregroundColor = tint
        return attr
    }
}
