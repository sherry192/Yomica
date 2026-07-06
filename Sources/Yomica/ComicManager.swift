import Foundation
import ZIPFoundation
import UniformTypeIdentifiers
import SwiftUI

class ComicManager: ObservableObject {
    @Published var comics: [ComicBook] = []
    @Published var categories: [ComicCategory] = []
    @Published var favoriteImages: [FavoriteImage] = []
    @Published private var categoryAssignments: [String: Set<UUID>] = [:]
    @Published var isLoading: Bool = false
    
    private let allowedImageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic"]
    private let categoryColors = ["#5E8CFF", "#34C759", "#FF9F0A", "#FF375F", "#AF52DE", "#00C7BE", "#8E8E93"]
    private let queue = DispatchQueue(label: "com.yomica.manager", qos: .userInitiated)

    private var documentsDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "storagePath"),
           let url = URL(string: path) {
            return url
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var metadataDirectory: URL {
        documentsDirectory.appendingPathComponent(".yomica", isDirectory: true)
    }
    
    private var metadataURL: URL {
        metadataDirectory.appendingPathComponent("metadata.json")
    }
    
    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadExistingComics()
        }
    }
    
    func updateStoragePath(to url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: "storagePath")
        loadExistingComics()
    }
    
    func loadExistingComics() {
        isLoading = true
        queue.async { [weak self] in
            guard let self = self else { return }
            let fileManager = FileManager.default
            do {
                let metadata = self.readMetadata()
                let contents = try fileManager.contentsOfDirectory(at: self.documentsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                var loadedComics: [ComicBook] = []
                
                for url in contents {
                    autoreleasepool {
                        var isDirectory: ObjCBool = false
                        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                            if isDirectory.boolValue {
                                if let comic = self.createComic(from: url) {
                                    loadedComics.append(comic)
                                }
                            } else {
                                let ext = url.pathExtension.lowercased()
                                if ext == "zip" || ext == "cbz" {
                                    self.importArchiveSync(from: url)
                                    let title = url.deletingPathExtension().lastPathComponent
                                    let targetDir = self.documentsDirectory.appendingPathComponent(title)
                                    if let comic = self.createComic(from: targetDir) {
                                        loadedComics.append(comic)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Restore saved order
                if let savedOrder = UserDefaults.standard.stringArray(forKey: "comicsOrder") {
                    let orderDict = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
                    loadedComics.sort { (a, b) -> Bool in
                        let orderA = orderDict[a.title] ?? Int.max
                        let orderB = orderDict[b.title] ?? Int.max
                        return orderA < orderB
                    }
                } else {
                    loadedComics.sort(by: { $0.title < $1.title })
                }
                
                DispatchQueue.main.async {
                    self.comics = loadedComics
                    self.categories = metadata.categories.sorted { $0.order < $1.order }
                    self.categoryAssignments = self.prunedAssignments(metadata.assignments, categories: metadata.categories, validKeys: Set(loadedComics.map(\.libraryKey)))
                    self.favoriteImages = self.prunedFavoriteImages(metadata.favoriteImages, comics: loadedComics)
                    self.isLoading = false
                }
            } catch {
                print("Failed to load existing comics: \(error)")
                DispatchQueue.main.async { self.isLoading = false }
            }
        }
    }
    
    // 内部同步导入方法，运行在子线程
    private func importArchiveSync(from url: URL) {
        let fileManager = FileManager.default
        let title = url.deletingPathExtension().lastPathComponent
        let targetDir = self.documentsDirectory.appendingPathComponent(title)

        if fileManager.fileExists(atPath: targetDir.path) { return }

        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: url, to: targetDir)
            // 成功解压后可选删除原压缩包以节省空间，此处暂保留
        } catch {
            print("Error unzipping comic: \(error)")
            try? fileManager.removeItem(at: targetDir)
        }
    }

    func importComic(from url: URL) {
        isLoading = true
        queue.async { [weak self] in
            guard let self = self else { return }
            let secureAccess = url.startAccessingSecurityScopedResource()
            defer { if secureAccess { url.stopAccessingSecurityScopedResource() } }

            let fileManager = FileManager.default
            let ext = url.pathExtension.lowercased()
            let isArchive = ext == "zip" || ext == "cbz"
            let title = isArchive ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
            let targetDir = self.documentsDirectory.appendingPathComponent(title)

            if !fileManager.fileExists(atPath: targetDir.path) {
                do {
                    if isArchive {
                        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
                        try fileManager.unzipItem(at: url, to: targetDir)
                    } else {
                        try fileManager.copyItem(at: url, to: targetDir)
                    }
                } catch {
                    print("Error importing comic: \(error)")
                    try? fileManager.removeItem(at: targetDir)
                }
            }
            
            if let comic = self.createComic(from: targetDir) {
                DispatchQueue.main.async {
                    if !self.comics.contains(where: { $0.id == comic.id || $0.title == comic.title }) {
                        withAnimation(.easeIn(duration: 0.28)) {
                            self.comics.append(comic)
                        }
                    }
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }
    }
    
    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    private func createComic(from directory: URL) -> ComicBook? {
        autoreleasepool {
            let fileManager = FileManager.default
            let title = directory.lastPathComponent
            let attributes = try? fileManager.attributesOfItem(atPath: directory.path)
            let creationDate = attributes?[.creationDate] as? Date ?? Date()

            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return nil }

            var imageURLs: [URL] = []
            for case let fileURL as URL in enumerator {
                if !isDirectory(fileURL) && allowedImageExtensions.contains(fileURL.pathExtension.lowercased()) {
                    imageURLs.append(fileURL)
                }
            }
            guard !imageURLs.isEmpty else { return nil }

            let sortedURLs = imageURLs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let coverURL = sortedURLs.first { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare("cover") == .orderedSame } ?? sortedURLs.first
            let pages = sortedURLs.map { ComicPage(id: UUID(), imageURL: $0) }
            return ComicBook(libraryKey: title, title: title, coverURL: coverURL, pages: pages, dateAdded: creationDate)
        }
    }
    
    func deleteComic(_ comic: ComicBook) {
        deleteComics([comic])
    }

    func deleteComics(_ comicsToDelete: [ComicBook]) {
        let fileManager = FileManager.default
        for comic in comicsToDelete {
            let comicDir = documentsDirectory.appendingPathComponent(comic.title)
            try? fileManager.removeItem(at: comicDir)
        }
        
        ImageProvider.clearCache()
        
        DispatchQueue.main.async {
            let idsToDelete = Set(comicsToDelete.map { $0.id })
            withAnimation(.easeInOut(duration: 0.22)) {
                self.comics.removeAll { idsToDelete.contains($0.id) }
                for comic in comicsToDelete {
                    self.categoryAssignments.removeValue(forKey: comic.libraryKey)
                }
                let keysToDelete = Set(comicsToDelete.map(\.libraryKey))
                self.favoriteImages.removeAll { keysToDelete.contains($0.comicKey) }
            }
            self.saveMetadata()
            self.saveOrder()
        }
    }

    func renameComic(_ comic: ComicBook, to newName: String) {
        let fileManager = FileManager.default
        let oldDir = documentsDirectory.appendingPathComponent(comic.title)
        let newDir = documentsDirectory.appendingPathComponent(newName)

        if fileManager.fileExists(atPath: newDir.path) { return }

        do {
            try fileManager.moveItem(at: oldDir, to: newDir)
            if let assignedCategories = categoryAssignments.removeValue(forKey: comic.libraryKey) {
                categoryAssignments[newName] = assignedCategories
            }
            for index in favoriteImages.indices where favoriteImages[index].comicKey == comic.libraryKey {
                favoriteImages[index].comicKey = newName
                favoriteImages[index].comicTitle = newName
            }
            saveMetadata()
            loadExistingComics()
        } catch {
            print("Failed to rename comic: \(error)")
        }
    }

    func moveComics(from source: IndexSet, to destination: Int) {
        comics.move(fromOffsets: source, toOffset: destination)
        saveOrder()
    }
    
    func reorderComics(to visibleOrder: [ComicBook], isAscending: Bool) {
        let visibleIDs = Set(visibleOrder.map(\.id))
        let reorderedComics = isAscending ? visibleOrder : visibleOrder.reversed()
        comics = Array(reorderedComics) + comics.filter { !visibleIDs.contains($0.id) }
        saveOrder()
    }

    private func saveOrder() {
        let order = comics.map { $0.title }
        UserDefaults.standard.set(order, forKey: "comicsOrder")
    }
    
    func comics(in category: ComicCategory) -> [ComicBook] {
        comics.filter { categoryAssignments[$0.libraryKey, default: []].contains(category.id) }
    }
    
    var uncategorizedComics: [ComicBook] {
        comics.filter { categoryAssignments[$0.libraryKey, default: []].isEmpty }
    }
    
    func categories(for comic: ComicBook) -> [ComicCategory] {
        let assignedIDs = categoryAssignments[comic.libraryKey, default: []]
        return categories.filter { assignedIDs.contains($0.id) }
    }
    
    func categoryCount(_ category: ComicCategory) -> Int {
        comics(in: category).count
    }
    
    var favoritePages: [FavoriteComicPage] {
        favoriteImages.compactMap { favorite in
            guard let comic = comics.first(where: { $0.libraryKey == favorite.comicKey }),
                  let pageIndex = comic.pages.firstIndex(where: { relativePath(for: $0.imageURL, in: comic) == favorite.relativePath }) else {
                return nil
            }
            return FavoriteComicPage(
                favorite: favorite,
                comic: comic,
                imageURL: comic.pages[pageIndex].imageURL,
                pageIndex: pageIndex
            )
        }
    }
    
    func isFavorite(pageAt index: Int, in comic: ComicBook) -> Bool {
        guard comic.pages.indices.contains(index) else { return false }
        let relativePath = relativePath(for: comic.pages[index].imageURL, in: comic)
        return favoriteImages.contains { $0.comicKey == comic.libraryKey && $0.relativePath == relativePath }
    }
    
    @discardableResult
    func toggleFavorite(pageAt index: Int, in comic: ComicBook) -> Bool {
        guard comic.pages.indices.contains(index) else { return false }
        
        let relativePath = relativePath(for: comic.pages[index].imageURL, in: comic)
        if let existingIndex = favoriteImages.firstIndex(where: { $0.comicKey == comic.libraryKey && $0.relativePath == relativePath }) {
            favoriteImages.remove(at: existingIndex)
            saveMetadata()
            return false
        }
        
        favoriteImages.insert(
            FavoriteImage(
                comicKey: comic.libraryKey,
                comicTitle: comic.title,
                relativePath: relativePath,
                pageIndex: index
            ),
            at: 0
        )
        saveMetadata()
        return true
    }
    
    func removeFavorite(_ favorite: FavoriteImage) {
        favoriteImages.removeAll { $0.id == favorite.id }
        saveMetadata()
    }
    
    func createCategory(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        let color = categoryColors[categories.count % categoryColors.count]
        categories.append(ComicCategory(name: name, colorHex: color, order: categories.count))
        saveMetadata()
    }
    
    func renameCategory(_ category: ComicCategory, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        
        categories[index].name = name
        saveMetadata()
    }
    
    func deleteCategory(_ category: ComicCategory) {
        categories.removeAll { $0.id == category.id }
        for key in Array(categoryAssignments.keys) {
            categoryAssignments[key]?.remove(category.id)
            if categoryAssignments[key]?.isEmpty == true {
                categoryAssignments.removeValue(forKey: key)
            }
        }
        refreshCategoryOrder()
        saveMetadata()
    }
    
    func toggleCategory(_ category: ComicCategory, for comic: ComicBook) {
        if categoryAssignments[comic.libraryKey, default: []].contains(category.id) {
            removeComic(comic, from: category)
        } else {
            addComic(comic, to: category)
        }
    }
    
    func addComic(_ comic: ComicBook, to category: ComicCategory) {
        categoryAssignments[comic.libraryKey, default: []].insert(category.id)
        saveMetadata()
    }
    
    func addComics(_ selectedComics: [ComicBook], to category: ComicCategory) {
        for comic in selectedComics {
            categoryAssignments[comic.libraryKey, default: []].insert(category.id)
        }
        saveMetadata()
    }
    
    func removeComic(_ comic: ComicBook, from category: ComicCategory) {
        categoryAssignments[comic.libraryKey]?.remove(category.id)
        if categoryAssignments[comic.libraryKey]?.isEmpty == true {
            categoryAssignments.removeValue(forKey: comic.libraryKey)
        }
        saveMetadata()
    }
    
    private func refreshCategoryOrder() {
        for index in categories.indices {
            categories[index].order = index
        }
    }
    
    private func readMetadata() -> ComicLibraryMetadata {
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(ComicLibraryMetadata.self, from: data) else {
            return ComicLibraryMetadata()
        }
        return metadata
    }
    
    private func saveMetadata() {
        refreshCategoryOrder()
        
        let metadata = ComicLibraryMetadata(
            categories: categories,
            assignments: categoryAssignments.mapValues { Array($0) },
            favoriteImages: favoriteImages
        )
        
        do {
            try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true, attributes: nil)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
        } catch {
            print("Failed to save metadata: \(error)")
        }
    }
    
    private func prunedAssignments(_ rawAssignments: [String: [UUID]], categories: [ComicCategory], validKeys: Set<String>) -> [String: Set<UUID>] {
        let categoryIDs = Set(categories.map(\.id))
        var result: [String: Set<UUID>] = [:]
        
        for (key, ids) in rawAssignments where validKeys.contains(key) {
            let validIDs = Set(ids).intersection(categoryIDs)
            if !validIDs.isEmpty {
                result[key] = validIDs
            }
        }
        
        return result
    }
    
    private func relativePath(for imageURL: URL, in comic: ComicBook) -> String {
        let basePath = documentsDirectory
            .appendingPathComponent(comic.libraryKey, isDirectory: true)
            .standardizedFileURL
            .path
        let imagePath = imageURL.standardizedFileURL.path
        
        if imagePath.hasPrefix(basePath + "/") {
            return String(imagePath.dropFirst(basePath.count + 1))
        }
        
        return imageURL.lastPathComponent
    }
    
    private func prunedFavoriteImages(_ rawFavorites: [FavoriteImage], comics: [ComicBook]) -> [FavoriteImage] {
        rawFavorites.filter { favorite in
            guard let comic = comics.first(where: { $0.libraryKey == favorite.comicKey }) else { return false }
            return comic.pages.contains { relativePath(for: $0.imageURL, in: comic) == favorite.relativePath }
        }
    }
}
