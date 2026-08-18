import SwiftUI
import SwiftData

@main
struct SakuraCopilotApp: App {
    @State private var services = AppServices.shared

    init() {
        // 深色霓虹标签栏
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(CyberTheme.bg0).withAlphaComponent(0.94)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services)
                .tint(CyberTheme.neonPink)
                .preferredColorScheme(.dark)
                .onOpenURL { url in services.handle(url: url) }
                .onAppear { services.bootstrap() }
        }
        .modelContainer(services.container)
    }
}
