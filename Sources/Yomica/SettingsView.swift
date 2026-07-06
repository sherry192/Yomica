import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("appAppearance") private var appAppearance: AppAppearance = .system
    @AppStorage("libraryDisplayMode") private var libraryDisplayMode: LibraryDisplayMode = .standard
    @AppStorage("libraryShowPageCount") private var libraryShowPageCount = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(LocalizedStringKey("通用"))) {
                    Picker(LocalizedStringKey("语言"), selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    
                    Picker(LocalizedStringKey("外观"), selection: $appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(LocalizedStringKey(appearance.displayName)).tag(appearance)
                        }
                    }
                    
                    Picker(LocalizedStringKey("主页展示"), selection: $libraryDisplayMode) {
                        ForEach(LibraryDisplayMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.displayName)).tag(mode)
                        }
                    }
                    
                    Toggle(LocalizedStringKey("主页显示漫画页数"), isOn: $libraryShowPageCount)
                }
                
                Section {
                    NavigationLink(LocalizedStringKey("阅读"), destination: ReadingSettingsView())
                    NavigationLink(LocalizedStringKey("储存"), destination: StorageSettingsView())
                }

                Section {
                    NavigationLink(LocalizedStringKey("关于页"), destination: AboutView())
                }
            }
            .navigationTitle(LocalizedStringKey("设置"))
        }
    }
}

struct StorageSettingsView: View {
    @EnvironmentObject var manager: ComicManager
    @State private var showingFolderPicker = false
    @AppStorage("storagePath") private var storagePath: String = ""

    var body: some View {
        Form {
            Section(header: Text(LocalizedStringKey("当前储存位置"))) {
                VStack(alignment: .leading, spacing: 8) {
                    if storagePath.isEmpty {
                        Text(LocalizedStringKey("默认"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(storagePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(LocalizedStringKey("更改存储路径")) {
                        showingFolderPicker = true
                    }
                }
            }

            Section {
                Button(LocalizedStringKey("重置为默认")) {
                    storagePath = ""
                    manager.loadExistingComics()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle(LocalizedStringKey("储存"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selectedURL = urls.first {
                    storagePath = selectedURL.absoluteString
                    manager.loadExistingComics()
                }
            case .failure(let error):
                print("Error selecting folder: \(error.localizedDescription)")
            }
        }
    }
}

struct AboutView: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    var body: some View {
        List {
            Section(header: Text(LocalizedStringKey("关于"))) {
                HStack {
                    Text("Yomica 是一款设计简洁、体验纯粹的本地漫画阅读器。仅此而已。")
                        .foregroundColor(.primary)
                }
            }
            
            Section(header: Text(LocalizedStringKey("链接"))) {
                Link(destination: URL(string: "https://github.com/sherry192/Yomica")!) {
                    HStack {
                        Text("Source Code")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text(LocalizedStringKey("版本号"))) {
                HStack {
                    Text(LocalizedStringKey("当前版本"))
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(LocalizedStringKey("关于页"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
