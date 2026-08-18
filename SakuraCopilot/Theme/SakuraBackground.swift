import SwiftUI

// MARK: - 赛博朋克樱花背景（花瓣粒子 + 霓虹光斑 + 扫描线）
struct SakuraBackground: View {
    var intensity: Double = 1.0

    struct Petal: Identifiable {
        let id: Int
        let xRatio: CGFloat      // 起始横向位置 0...1
        let size: CGFloat
        let speed: CGFloat        // 下落速度 pt/s
        let sway: CGFloat         // 横向摆幅
        let phase: CGFloat
        let spin: CGFloat
        let palette: Int          // 0 樱花粉 1 霓虹青 2 品红
    }

    @State private var petals: [Petal] = []

    var body: some View {
        ZStack {
            CyberTheme.bg0.ignoresSafeArea()
            LinearGradient(colors: [CyberTheme.bg1, CyberTheme.bg0, Color(hex: 0x0A0518)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // 霓虹光斑
            Circle()
                .fill(CyberTheme.neonPink.opacity(0.16 * intensity))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .position(x: UIScreen.main.bounds.width * 0.85, y: 90)
            Circle()
                .fill(CyberTheme.neonCyan.opacity(0.12 * intensity))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .position(x: 30, y: UIScreen.main.bounds.height * 0.35)
            Circle()
                .fill(CyberTheme.neonPurple.opacity(0.14 * intensity))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .position(x: UIScreen.main.bounds.width * 0.5, y: UIScreen.main.bounds.height * 0.95)

            // 花瓣粒子
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    for petal in petals {
                        let progress = CGFloat((t * Double(petal.speed) + Double(petal.phase) * 800).truncatingRemainder(dividingBy: Double(size.height + 80)))
                        let y = progress - 40
                        let x = petal.xRatio * size.width + CGFloat(sin(t * 0.8 + Double(petal.phase))) * petal.sway
                        let angle = Angle.degrees(Double(t * 24 * petal.spin + petal.phase * 360))
                        let rect = CGRect(x: x - petal.size / 2, y: y - petal.size / 2, width: petal.size, height: petal.size)
                        ctx.drawLayer { layer in
                            layer.translateBy(x: rect.midX, y: rect.midY)
                            layer.rotate(by: .radians(angle.radians * 0.3))
                            let path = PetalShape().path(in: CGRect(x: -petal.size / 2, y: -petal.size / 2,
                                                                    width: petal.size, height: petal.size))
                            let color: Color = petal.palette == 0 ? CyberTheme.sakura : (petal.palette == 1 ? CyberTheme.neonCyan : CyberTheme.neonMagenta)
                            layer.fill(path, with: .color(color.opacity(0.5 * intensity)))
                            layer.stroke(path, with: .color(color.opacity(0.75 * intensity)), lineWidth: 0.6)
                        }
                    }
                }
            }
            .ignoresSafeArea()

            // 扫描线
            GeometryReader { geo in
                Path { p in
                    var y: CGFloat = 0
                    while y < geo.size.height {
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += 5
                    }
                }
                .stroke(Color.white.opacity(0.018), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            guard petals.isEmpty else { return }
            var seeds: [Petal] = []
            for i in 0..<22 {
                seeds.append(Petal(id: i,
                                   xRatio: .random(in: 0...1),
                                   size: .random(in: 7...16),
                                   speed: .random(in: 18...46),
                                   sway: .random(in: 10...30),
                                   phase: .random(in: 0...10),
                                   spin: .random(in: 0.5...1.5),
                                   palette: Int.random(in: 0...6) == 0 ? 1 : (Int.random(in: 0...4) == 0 ? 2 : 0)))
            }
            petals = seeds
        }
        .allowsHitTesting(false)
    }
}

struct PetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h * 0.55),
                   control1: CGPoint(x: w * 0.98, y: h * 0.12),
                   control2: CGPoint(x: w * 0.95, y: h * 0.42))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h),
                       control: CGPoint(x: w * 0.78, y: h * 0.92))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.55),
                       control: CGPoint(x: w * 0.22, y: h * 0.92))
        p.addCurve(to: CGPoint(x: w * 0.5, y: 0),
                   control1: CGPoint(x: w * 0.05, y: h * 0.42),
                   control2: CGPoint(x: w * 0.02, y: h * 0.12))
        p.closeSubpath()
        return p
    }
}

// MARK: - 全屏背景修饰
struct WithSakuraBackground<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            SakuraBackground()
            content()
        }
    }
}
