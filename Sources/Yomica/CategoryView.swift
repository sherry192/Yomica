import SwiftUI

struct CategoryView: View {
    @EnvironmentObject var manager: ComicManager
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.simplifiedChinese.rawValue
    
    @State private var showingCreateCategory = false
    @State private var newCategoryName = ""
    @State private var renamingCategory: ComicCategory?
    @State private var categoryName = ""
    @State private var deletingCategory: ComicCategory?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: categoryCoverColumns, spacing: 22) {
                    NavigationLink {
                        FavoriteImageListView()
                    } label: {
                        CategoryCoverItem(
                            title: "图片收藏",
                            count: manager.favoritePages.count,
                            color: .yellow,
                            systemImage: "star.fill",
                            isLocalized: true,
                            coverURL: manager.favoritePages.first?.imageURL
                        )
                    }
                    .buttonStyle(.plain)
                    
                    ForEach(manager.categories) { category in
                        let comics = manager.comics(in: category)
                        NavigationLink {
                            CategoryComicListView(category: category)
                        } label: {
                            CategoryCoverItem(
                                title: category.name,
                                count: comics.count,
                                color: Color(hex: category.colorHex),
                                systemImage: "folder",
                                coverURL: comics.first?.coverURL
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                renamingCategory = category
                                categoryName = category.name
                            } label: {
                                Label(LocalizedStringKey("重命名"), systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                deletingCategory = category
                            } label: {
                                Label(LocalizedStringKey("删除"), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(categoryCoverPadding)
            }
            .navigationTitle(LocalizedStringKey("分类"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newCategoryName = ""
                        showingCreateCategory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert(LocalizedStringKey("新建分类"), isPresented: $showingCreateCategory) {
                TextField(LocalizedStringKey("分类名称"), text: $newCategoryName)
                Button(LocalizedStringKey("取消"), role: .cancel) {}
                Button(LocalizedStringKey("确定")) {
                    manager.createCategory(named: newCategoryName)
                }
            }
            .alert(LocalizedStringKey("重命名分类"), isPresented: Binding(
                get: { renamingCategory != nil },
                set: { if !$0 { renamingCategory = nil } }
            )) {
                TextField(LocalizedStringKey("分类名称"), text: $categoryName)
                Button(LocalizedStringKey("取消"), role: .cancel) {
                    renamingCategory = nil
                }
                Button(LocalizedStringKey("确定")) {
                    if let category = renamingCategory {
                        manager.renameCategory(category, to: categoryName)
                    }
                    renamingCategory = nil
                }
            }
            .alert(LocalizedStringKey("删除分类"), isPresented: Binding(
                get: { deletingCategory != nil },
                set: { if !$0 { deletingCategory = nil } }
            )) {
                Button(LocalizedStringKey("取消"), role: .cancel) {
                    deletingCategory = nil
                }
                Button(LocalizedStringKey("删除"), role: .destructive) {
                    if let category = deletingCategory {
                        manager.deleteCategory(category)
                    }
                    deletingCategory = nil
                }
            } message: {
                Text(LocalizedStringKey("分类会被删除，漫画文件不会被删除。"))
            }
        }
        .id(appLanguage)
    }
    
    private var categoryCoverColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)]
    }
    
    private var categoryCoverPadding: EdgeInsets {
        EdgeInsets(top: 18, leading: 20, bottom: 24, trailing: 20)
    }
}

private struct CategoryCoverItem: View {
    let title: String
    let count: Int
    let color: Color
    var systemImage = "folder"
    var isLocalized = false
    var coverURL: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            coverView
            
            if isLocalized {
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            } else {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            
            Text("\(count)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var coverView: some View {
        if let coverURL {
            LocalAsyncImage(url: coverURL, targetSize: CGSize(width: 260, height: 370)) {
                placeholder
            }
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(0.7, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 3)
        } else {
            placeholder
        }
    }
    
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(0.14))
            .aspectRatio(0.7, contentMode: .fit)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(color)
            )
    }
}

private struct CategoryComicListView: View {
    @EnvironmentObject var manager: ComicManager
    let category: ComicCategory?
    
    @State private var selectedComic: ComicBook?
    @State private var showingAddComics = false
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    private var currentCategory: ComicCategory? {
        guard let category else { return nil }
        return manager.categories.first { $0.id == category.id }
    }
    
    private var title: String {
        currentCategory?.name ?? "未分类"
    }
    
    private var navigationTitle: Text {
        if currentCategory == nil {
            return Text(LocalizedStringKey("未分类"))
        }
        return Text(title)
    }
    
    private var comics: [ComicBook] {
        if let category = currentCategory {
            return manager.comics(in: category)
        }
        return manager.uncategorizedComics
    }
    
    private var addableComics: [ComicBook] {
        guard let category = currentCategory else { return [] }
        let existingIDs = Set(manager.comics(in: category).map(\.id))
        return manager.comics.filter { !existingIDs.contains($0.id) }
    }
    
    var body: some View {
        Group {
            if comics.isEmpty {
                CategoryEmptyState(
                    title: "暂无漫画",
                    subtitle: "",
                    systemImage: "book.closed"
                )
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
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if currentCategory != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddComics = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(addableComics.isEmpty)
                    .accessibilityLabel(Text(LocalizedStringKey("添加漫画")))
                }
            }
        }
        .sheet(isPresented: $showingAddComics) {
            if let category = currentCategory {
                AddComicsToCategoryView(category: category, comics: addableComics)
            }
        }
        .fullScreenCover(item: $selectedComic) { comic in
            ReaderView(comic: comic, initialIndex: 0)
        }
    }
    
    private var comicList: some View {
        List {
            ForEach(comics) { comic in
                ComicRow(comic: comic)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedComic = comic
                    }
                    .contextMenu {
                        removeFromCategoryButton(for: comic)
                    }
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private var comicGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)], spacing: 25) {
                ForEach(comics) { comic in
                    ComicGridItem(comic: comic)
                        .onTapGesture {
                            selectedComic = comic
                        }
                        .contextMenu {
                            removeFromCategoryButton(for: comic)
                        }
                }
            }
            .padding(25)
        }
    }
    
    @ViewBuilder
    private func removeFromCategoryButton(for comic: ComicBook) -> some View {
        if let category = currentCategory {
            Button(role: .destructive) {
                manager.removeComic(comic, from: category)
            } label: {
                Label(LocalizedStringKey("移出分类"), systemImage: "minus.circle")
            }
        }
    }
}

private struct AddComicsToCategoryView: View {
    @EnvironmentObject var manager: ComicManager
    @Environment(\.dismiss) private var dismiss
    
    let category: ComicCategory
    let comics: [ComicBook]
    
    @State private var selection = Set<ComicBook>()
    
    var body: some View {
        NavigationStack {
            Group {
                if comics.isEmpty {
                    CategoryEmptyState(
                        title: "暂无可添加漫画",
                        subtitle: "",
                        systemImage: "checkmark.circle"
                    )
                } else {
                    List(comics, selection: $selection) { comic in
                        ComicRow(comic: comic)
                            .tag(comic)
                    }
                    .environment(\.editMode, .constant(.active))
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle(LocalizedStringKey("添加漫画"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("取消")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("添加")) {
                        manager.addComics(Array(selection), to: category)
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct FavoriteImageListView: View {
    @EnvironmentObject var manager: ComicManager
    @State private var selectedPage: FavoriteComicPage?
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    private var favoritePages: [FavoriteComicPage] {
        manager.favoritePages
    }
    
    var body: some View {
        Group {
            if favoritePages.isEmpty {
                CategoryEmptyState(
                    title: "暂无收藏",
                    subtitle: "在阅读器里点击星标收藏喜欢的图片",
                    systemImage: "star"
                )
            } else {
                #if os(macOS)
                favoriteGrid
                #else
                if horizontalSizeClass == .regular {
                    favoriteGrid
                } else {
                    favoriteList
                }
                #endif
            }
        }
        .navigationTitle(LocalizedStringKey("图片收藏"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fullScreenCover(item: $selectedPage) { page in
            ReaderView(comic: page.comic, initialIndex: page.pageIndex)
        }
    }
    
    private var favoriteList: some View {
        List {
            ForEach(favoritePages) { page in
                FavoriteImageRow(page: page)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPage = page
                    }
                    .contextMenu {
                        removeFavoriteButton(for: page)
                    }
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private var favoriteGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 18)], spacing: 22) {
                ForEach(favoritePages) { page in
                    FavoriteImageGridItem(page: page)
                        .onTapGesture {
                            selectedPage = page
                        }
                        .contextMenu {
                            removeFavoriteButton(for: page)
                        }
                }
            }
            .padding(22)
        }
    }
    
    private func removeFavoriteButton(for page: FavoriteComicPage) -> some View {
        Button(role: .destructive) {
            manager.removeFavorite(page.favorite)
        } label: {
            Label(LocalizedStringKey("取消收藏"), systemImage: "star.slash")
        }
    }
}

private struct FavoriteImageRow: View {
    let page: FavoriteComicPage
    
    var body: some View {
        HStack(spacing: 14) {
            LocalAsyncImage(url: page.imageURL, targetSize: CGSize(width: 86, height: 120)) {
                PlaceholderCover()
            }
            .scaledToFill()
            .frame(width: 86, height: 120)
            .cornerRadius(8)
            .clipped()
            
            VStack(alignment: .leading, spacing: 6) {
                Text(page.comic.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(LocalizedStringKey("第 \(page.pageIndex + 1) 页"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
        }
        .padding(.vertical, 4)
    }
}

private struct FavoriteImageGridItem: View {
    let page: FavoriteComicPage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                LocalAsyncImage(url: page.imageURL, targetSize: CGSize(width: 180, height: 250)) {
                    PlaceholderCover(isGrid: true)
                }
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(0.72, contentMode: .fill)
                .cornerRadius(12)
                .clipped()
                
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .padding(8)
            }
            
            Text(page.comic.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
            
            Text(LocalizedStringKey("第 \(page.pageIndex + 1) 页"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct CategoryEmptyState: View {
    let title: String
    let subtitle: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
            
            Text(LocalizedStringKey(title))
                .font(.headline)
            
            if !subtitle.isEmpty {
                Text(LocalizedStringKey(subtitle))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
