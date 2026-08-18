import SwiftUI

// MARK: - 底部 4 Tab（对话 / 知识库 / 笔记 / 代码库；设置不占 Tab）
struct RootTabView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var router = services.router
        TabView(selection: Binding(get: { router.tab }, set: { router.tab = $0 })) {
            ChatView()
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(AppTab.chat)
            KnowledgeView()
                .tabItem { Label("知识库", systemImage: "books.vertical.fill") }
                .tag(AppTab.knowledge)
            NotesView()
                .tabItem { Label("笔记", systemImage: "note.text") }
                .tag(AppTab.notes)
            CodeLibraryView()
                .tabItem { Label("代码库", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(AppTab.code)
        }
        .sheet(item: Binding(get: { router.assistRequest },
                             set: { router.assistRequest = $0 })) { request in
            AskAssistantSheet(area: request.area, prefilled: request.text)
                .environment(services)
        }
        .sheet(isPresented: Binding(get: { router.showTaskCenter },
                                    set: { router.showTaskCenter = $0 })) {
            TaskCenterView(focusTaskID: router.focusTaskID)
                .environment(services)
        }
    }
}
