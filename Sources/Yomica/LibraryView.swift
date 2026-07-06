import SwiftUI
import UniformTypeIdentifiers

enum SortOption: String, CaseIterable, Identifiable {
    case manual = "手动排序"
    case title = "按名称"
    case date = "按日期"
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        LocalizedStringKey(self.rawValue)
    }
}

struct LibraryView: View {
    @EnvironmentObject var manager: ComicManager
    @State private var showingFilePicker = false
    @State private var selectedComic: ComicBook?
    @State private var renamingComic: ComicBook?
    @State private var renameText = ""
    @State private var showingDeleteConfirmation = false
    @State private var deletingComic: ComicBook?
    
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("libraryDisplayMode") private var libraryDisplayMode: LibraryDisplayMode = .standard
    @AppStorage("libraryShowPageCount") private var libraryShowPageCount = false
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    // Search and Sort states
    @State private var searchText = ""
    @State private var sortOption: SortOption = .manual
    @State private var isAscending = true
    
    // Selection state
    @State private var selection = Set<ComicBook>()
    @State private var editMode: EditMode = .inactive
    @State private var draggedComic: ComicBook?

    var filteredComics: [ComicBook] {
        let filtered = manager.comics.filter { comic in
            searchText.isEmpty || comic.title.localizedCaseInsensitiveContains(searchText)
        }
        
        if sortOption == .manual {
            return isAscending ? filtered : filtered.reversed()
        }
        
        return filtered.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .title:
                result = a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .date:
                result = a.dateAdded < b.dateAdded
            case .manual:
                return true
            }
            return isAscending ? result : !result
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if manager.comics.isEmpty {
                    emptyState
                } else {
                    libraryContent
                }
            }
            .navigationTitle(LocalizedStringKey("漫画"))
            .toolbar(content: toolbarContent)
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.folder, .zip, .archive],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .fullScreenCover(item: $selectedComic) { comic in
                ReaderView(comic: comic, initialIndex: 0)
            }
            .sheet(item: $renamingComic) { comic in
                RenameComicSheet(
                    comic: comic,
                    name: $renameText,
                    onCancel: {
                        renamingComic = nil
                    },
                    onSave: { newName in
                        manager.renameComic(comic, to: newName)
                        renamingComic = nil
                    }
                )
            }
            .alert(LocalizedStringKey("删除漫画"), isPresented: $showingDeleteConfirmation, presenting: deletingComic) { comic in
                Button(LocalizedStringKey("取消"), role: .cancel) {}
                Button(LocalizedStringKey("删除"), role: .destructive) {
                    manager.deleteComic(comic)
                }
            } message: { comic in
                Text("确定要删除\"\(comic.title)\"吗？")
            }
            .overlay(loadingOverlay)
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) { newValue in
                if newValue == .inactive {
                    draggedComic = nil
                }
            }
        }
        .id(appLanguage)
    }
    
    @ViewBuilder
    private var libraryContent: some View {
        if libraryDisplayMode == .coverFocused {
            coverFocusedGrid
        } else {
            #if os(macOS)
            comicGrid
            #else
            if horizontalSizeClass == .regular {
                comicGrid
            } else {
                comicList
            }
            #endif
        }
    }
    
    private var emptyState: some View {
        VStack {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .padding(.bottom, 8)
            Text(LocalizedStringKey("暂无漫画"))
                .font(.headline)
            Text(LocalizedStringKey("点击右上角 + 导入文件夹或 CBZ/ZIP 文件"))
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    private var comicList: some View {
        searchableContent(
            List(selection: $selection) {
                ForEach(filteredComics) { comic in
                    ComicRow(comic: comic, showsPageCount: libraryShowPageCount)
                        .onTapGesture {
                            if editMode == .inactive {
                                selectedComic = comic
                            }
                        }
                        .contextMenu { comicContextMenu(for: comic) }
                        .transition(comicTransition)
                        .tag(comic)
                }
                .onMove { indices, newOffset in
                    if sortOption == .manual && searchText.isEmpty {
                        manager.moveComics(from: indices, to: newOffset)
                    }
                }
            }
            .listStyle(PlainListStyle())
        )
    }
    
    private var comicGrid: some View {
        searchableContent(
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)], spacing: 25) {
                    ForEach(filteredComics) { comic in
                        ComicGridItem(comic: comic, showsPageCount: libraryShowPageCount)
                            .onTapGesture {
                                handleComicTap(comic)
                            }
                            .contextMenu { comicContextMenu(for: comic) }
                            .transition(comicTransition)
                            .modifier(ComicReorderModifier(
                                comic: comic,
                                comics: filteredComics,
                                draggedComic: $draggedComic,
                                isEnabled: canReorderGrid,
                                move: moveVisibleComics
                            ))
                    }
                }
                .padding(25)
            }
        )
    }
    
    private var coverFocusedGrid: some View {
        searchableContent(
            ScrollView {
                LazyVGrid(columns: coverFocusedColumns, spacing: coverFocusedSpacing) {
                    ForEach(filteredComics) { comic in
                        ComicCoverItem(comic: comic, showsPageCount: libraryShowPageCount)
                            .onTapGesture {
                                handleComicTap(comic)
                            }
                            .contextMenu { comicContextMenu(for: comic) }
                            .transition(comicTransition)
                            .modifier(ComicReorderModifier(
                                comic: comic,
                                comics: filteredComics,
                                draggedComic: $draggedComic,
                                isEnabled: canReorderGrid,
                                move: moveVisibleComics
                            ))
                    }
                }
                .padding(coverFocusedPadding)
            }
        )
    }
    
    @ViewBuilder
    private func searchableContent<Content: View>(_ content: Content) -> some View {
        #if os(iOS)
        content.searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text(LocalizedStringKey("搜索漫画..."))
        )
        .modifier(SearchAutoHideModifier(searchText: $searchText))
        #else
        content.searchable(text: $searchText, prompt: Text(LocalizedStringKey("搜索漫画...")))
        #endif
    }
    
    private var coverFocusedColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)]
        #else
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 20)]
        }
        return [GridItem(.adaptive(minimum: 165, maximum: 240), spacing: 18)]
        #endif
    }
    
    private var coverFocusedSpacing: CGFloat {
        #if os(macOS)
        24
        #else
        horizontalSizeClass == .regular ? 28 : 22
        #endif
    }
    
    private var coverFocusedPadding: EdgeInsets {
        #if os(macOS)
        EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
        #else
        if horizontalSizeClass == .regular {
            return EdgeInsets(top: 26, leading: 26, bottom: 26, trailing: 26)
        }
        return EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)
        #endif
    }
    
    private var canReorderGrid: Bool {
        sortOption == .manual && searchText.isEmpty
    }
    
    private var comicTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .scale(scale: 0.82).combined(with: .opacity)
        )
    }
    
    private func handleComicTap(_ comic: ComicBook) {
        if editMode == .active {
            if selection.contains(comic) {
                selection.remove(comic)
            } else {
                selection.insert(comic)
            }
        } else {
            selectedComic = comic
        }
    }
    
    private func moveVisibleComics(_ visibleComics: [ComicBook]) {
        manager.reorderComics(to: visibleComics, isAscending: isAscending)
    }
    
    @ViewBuilder
    private func comicContextMenu(for comic: ComicBook) -> some View {
        if editMode == .inactive {
            Button {
                renamingComic = comic
                renameText = comic.title
            } label: {
                Label(LocalizedStringKey("重命名"), systemImage: "pencil")
            }
            
            Button {
                withAnimation {
                    editMode = .active
                    selection.insert(comic)
                }
            } label: {
                Label(LocalizedStringKey("编辑"), systemImage: "checkmark.circle")
            }
            
            if !manager.categories.isEmpty {
                Menu {
                    ForEach(manager.categories) { category in
                        Button {
                            manager.toggleCategory(category, for: comic)
                        } label: {
                            let isAssigned = manager.categories(for: comic).contains(category)
                            Label(category.name, systemImage: isAssigned ? "checkmark.circle.fill" : "circle")
                        }
                    }
                } label: {
                    Label(LocalizedStringKey("分类"), systemImage: "folder")
                }
            }
            
            Button(role: .destructive) {
                deletingComic = comic
                showingDeleteConfirmation = true
            } label: {
                Label(LocalizedStringKey("删除"), systemImage: "trash")
            }
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if editMode == .active {
                Button(LocalizedStringKey("完成")) {
                    withAnimation {
                        editMode = .inactive
                        selection.removeAll()
                    }
                }
                .fontWeight(.bold)
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            HStack {
                if editMode == .active {
                    Menu {
                        if manager.categories.isEmpty {
                            Text(LocalizedStringKey("暂无分类"))
                        } else {
                            ForEach(manager.categories) { category in
                                Button {
                                    manager.addComics(Array(selection), to: category)
                                } label: {
                                    Label(category.name, systemImage: "folder")
                                }
                            }
                        }
                    } label: {
                        Label(LocalizedStringKey("加入分类"), systemImage: "folder.badge.plus")
                    }
                    .disabled(selection.isEmpty || manager.categories.isEmpty)
                    
                    Button(role: .destructive) {
                        manager.deleteComics(Array(selection))
                        selection.removeAll()
                        editMode = .inactive
                    } label: {
                        Text(LocalizedStringKey("删除所选"))
                            .foregroundColor(.red)
                    }
                    .disabled(selection.isEmpty)
                } else {
                    Menu {
                        Section {
                            ForEach(SortOption.allCases) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Text(option.localizedName)
                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Section {
                            Button {
                                isAscending = true
                            } label: {
                                HStack {
                                    Text(LocalizedStringKey("升序"))
                                    if isAscending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Button {
                                isAscending = false
                            } label: {
                                HStack {
                                    Text(LocalizedStringKey("降序"))
                                    if !isAscending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }

                    Button(action: {
                        showingFilePicker = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    private var loadingOverlay: some View {
        Group {
            if manager.isLoading {
                ProgressView(LocalizedStringKey("正在导入..."))
                    .padding()
                    .background(Color(.systemBackground).opacity(0.8))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
        }
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                manager.importComic(from: url)
            }
        case .failure(let error):
            print("Error importing: \(error.localizedDescription)")
        }
    }
}

#if os(iOS)
private struct SearchAutoHideModifier: ViewModifier {
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.isSearching) private var isSearching
    @Binding var searchText: String
    @State private var lastSearchActivity = Date()
    
    private let idleInterval: TimeInterval = 4
    
    func body(content: Content) -> some View {
        content
            .onChange(of: isSearching) { _ in
                lastSearchActivity = Date()
            }
            .onChange(of: searchText) { _ in
                lastSearchActivity = Date()
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                guard searchText.isEmpty,
                      !isSearching,
                      Date().timeIntervalSince(lastSearchActivity) >= idleInterval else {
                    return
                }
                dismissSearch()
            }
    }
}
#endif

private struct ComicReorderModifier: ViewModifier {
    let comic: ComicBook
    let comics: [ComicBook]
    @Binding var draggedComic: ComicBook?
    let isEnabled: Bool
    let move: ([ComicBook]) -> Void
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrag {
                    draggedComic = comic
                    return NSItemProvider(object: comic.id.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ComicReorderDropDelegate(
                        targetComic: comic,
                        comics: comics,
                        draggedComic: $draggedComic,
                        move: move
                    )
                )
        } else {
            content
        }
    }
}

private struct ComicReorderDropDelegate: DropDelegate {
    let targetComic: ComicBook
    let comics: [ComicBook]
    @Binding var draggedComic: ComicBook?
    let move: ([ComicBook]) -> Void
    
    func dropEntered(info: DropInfo) {
        guard let draggedComic,
              draggedComic != targetComic,
              let fromIndex = comics.firstIndex(of: draggedComic),
              let toIndex = comics.firstIndex(of: targetComic) else {
            return
        }
        
        var updatedComics = comics
        updatedComics.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
        
        withAnimation(.easeInOut(duration: 0.18)) {
            move(updatedComics)
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedComic = nil
        return true
    }
}

private struct RenameComicSheet: View {
    let comic: ComicBook
    @Binding var name: String
    let onCancel: () -> Void
    let onSave: (String) -> Void
    @FocusState private var isNameFocused: Bool
    
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName != comic.title
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                LocalAsyncImage(url: comic.coverURL, targetSize: CGSize(width: 120, height: 168)) {
                    PlaceholderCover(isGrid: true)
                }
                .scaledToFill()
                .frame(width: 120, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 8)
                
                VStack(spacing: 6) {
                    Text(LocalizedStringKey("重命名漫画"))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(LocalizedStringKey("请输入新的漫画名称"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                TextField(LocalizedStringKey("漫画名"), text: $name)
                    .font(.body)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 26)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("取消"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("保存"), action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
        #if os(iOS)
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
        #endif
    }
    
    private func save() {
        if canSave {
            onSave(trimmedName)
        }
    }
}

struct ComicRow: View {
    let comic: ComicBook
    var showsPageCount = true
    
    var body: some View {
        HStack(spacing: 15) {
            LocalAsyncImage(url: comic.coverURL, targetSize: CGSize(width: 80, height: 110)) {
                PlaceholderCover()
            }
            .scaledToFill()
            .frame(width: 80, height: 110)
            .cornerRadius(6)
            .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(comic.title)
                    .font(.headline)
                    .lineLimit(2)

                if showsPageCount {
                    Text("\(comic.pages.count) 页")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct ComicGridItem: View {
    let comic: ComicBook
    var showsPageCount = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocalAsyncImage(url: comic.coverURL, targetSize: CGSize(width: 200, height: 280)) {
                PlaceholderCover(isGrid: true)
            }
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(0.72, contentMode: .fill)
            .cornerRadius(12)
            .clipped()
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(comic.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if showsPageCount {
                    Text("\(comic.pages.count) 页")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }
}

struct ComicCoverItem: View {
    let comic: ComicBook
    var showsPageCount = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalAsyncImage(url: comic.coverURL, targetSize: CGSize(width: 300, height: 430)) {
                PlaceholderCover(isGrid: true)
            }
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(0.7, contentMode: .fill)
            .cornerRadius(8)
            .clipped()
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 3)
            
            Text(comic.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            
            HStack(spacing: 4) {
                if showsPageCount {
                    Text("\(comic.pages.count) 页")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
            }
            .frame(height: 18, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

struct PlaceholderCover: View {
    var isGrid: Bool = false
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: isGrid ? nil : 80, height: isGrid ? nil : 110)
            .aspectRatio(isGrid ? 0.72 : nil, contentMode: .fit)
            .cornerRadius(isGrid ? 12 : 6)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            )
    }
}
