import SwiftUI

@main
struct YomicaApp: App {
    @StateObject private var comicManager = ComicManager()
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("appAppearance") private var appAppearance: AppAppearance = .system
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(comicManager)
                .environment(\.locale, .init(identifier: appLanguage))
                .preferredColorScheme(appAppearance.colorScheme)
                .id(appLanguage)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {} // 移除默认的“新建”菜单
        }
        #endif
    }
}
// 确保该目录下没有其他 @main 的文件
