import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case library = "主页"
    case category = "分类"
    case settings = "设置"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .library: return "house"
        case .category: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }
}

struct MainTabView: View {
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("selectedTab") private var selectedTab: Int = 0
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    @State private var sidebarSelection: SidebarItem? = .library

    var body: some View {
        #if os(macOS)
        desktopBody
        #else
        if horizontalSizeClass == .regular {
            desktopBody // iPad 橫屏/大屏
        } else {
            phoneBody // iPhone
        }
        #endif
    }
    
    // iPhone 布局：传统 TabView
    private var phoneBody: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label(LocalizedStringKey("主页"), systemImage: "house")
                }
                .tag(0)
            
            CategoryView()
                .tabItem {
                    Label(LocalizedStringKey("分类"), systemImage: "square.grid.2x2")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label(LocalizedStringKey("设置"), systemImage: "gearshape")
                }
                .tag(2)
        }
    }
    
    // iPad & macOS 布局：侧边栏 Sidebar
    private var desktopBody: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $sidebarSelection) { item in
                NavigationLink(value: item) {
                    Label(LocalizedStringKey(item.rawValue), systemImage: item.icon)
                }
            }
            .navigationTitle("")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            #endif
        } detail: {
            if let selection = sidebarSelection {
                switch selection {
                case .library:
                    LibraryView()
                case .category:
                    CategoryView()
                case .settings:
                    SettingsView()
                }
            } else {
                Text("Select an item")
            }
        }
    }
}
