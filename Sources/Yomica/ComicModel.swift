import Foundation
import SwiftUI
import ImageIO

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformImage = NSImage
#endif

public struct ComicBook: Identifiable, Hashable {
    public let id: UUID
    public let libraryKey: String
    public let title: String
    public let coverURL: URL?
    public let pages: [ComicPage]
    public let dateAdded: Date
    
    public init(id: UUID = UUID(), libraryKey: String? = nil, title: String, coverURL: URL?, pages: [ComicPage], dateAdded: Date = Date()) {
        self.id = id
        self.libraryKey = libraryKey ?? title
        self.title = title
        self.coverURL = coverURL
        self.pages = pages
        self.dateAdded = dateAdded
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ComicBook, rhs: ComicBook) -> Bool {
        lhs.id == rhs.id
    }
}

public struct ComicPage: Identifiable, Hashable {
    public let id: UUID
    public let imageURL: URL
    
    public init(id: UUID = UUID(), imageURL: URL) {
        self.id = id
        self.imageURL = imageURL
    }
}

public struct ComicCategory: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var order: Int
    
    public init(id: UUID = UUID(), name: String, colorHex: String, order: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.order = order
    }
}

public struct FavoriteImage: Identifiable, Codable, Hashable {
    public var comicKey: String
    public var comicTitle: String
    public var relativePath: String
    public var pageIndex: Int
    public var dateAdded: Date
    
    public var id: String {
        "\(comicKey)::\(relativePath)"
    }
    
    public init(comicKey: String, comicTitle: String, relativePath: String, pageIndex: Int, dateAdded: Date = Date()) {
        self.comicKey = comicKey
        self.comicTitle = comicTitle
        self.relativePath = relativePath
        self.pageIndex = pageIndex
        self.dateAdded = dateAdded
    }
}

public struct FavoriteComicPage: Identifiable, Hashable {
    public let favorite: FavoriteImage
    public let comic: ComicBook
    public let imageURL: URL
    public let pageIndex: Int
    
    public var id: String {
        favorite.id
    }
}

public struct ComicLibraryMetadata: Codable {
    public var version: Int
    public var categories: [ComicCategory]
    public var assignments: [String: [UUID]]
    public var favoriteImages: [FavoriteImage]
    
    public init(version: Int = 2, categories: [ComicCategory] = [], assignments: [String: [UUID]] = [:], favoriteImages: [FavoriteImage] = []) {
        self.version = version
        self.categories = categories
        self.assignments = assignments
        self.favoriteImages = favoriteImages
    }
    
    private enum CodingKeys: String, CodingKey {
        case version
        case categories
        case assignments
        case favoriteImages
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        categories = try container.decodeIfPresent([ComicCategory].self, forKey: .categories) ?? []
        assignments = try container.decodeIfPresent([String: [UUID]].self, forKey: .assignments) ?? [:]
        favoriteImages = try container.decodeIfPresent([FavoriteImage].self, forKey: .favoriteImages) ?? []
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        
        self.init(red: red, green: green, blue: blue)
    }
}

public enum ImageProvider {
    public static let cache = ImageCache()

    public static func clearCache() {
        cache.clear()
    }

    public static func getCacheKey(url: URL, targetSize: CGSize, scale: CGFloat) -> NSString {
        // Floor the size to avoid sub-pixel mismatch
        let w = Int(targetSize.width)
        let h = Int(targetSize.height)
        let s = Int(scale * 10) // e.g. 2.0 -> 20, 3.0 -> 30
        return "\(url.path)_\(w)_\(h)_\(s)" as NSString
    }

    public static func downsample(imageAt url: URL, to pointSize: CGSize, scale: CGFloat) -> PlatformImage? {
        let cacheKey = getCacheKey(url: url, targetSize: pointSize, scale: scale)
        if let cached = cache.get(forKey: cacheKey) {
            return cached
        }


        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
            return nil
        }
        
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        #if os(iOS)
        let finalImage = UIImage(cgImage: downsampledImage)
        #else
        let size = NSSize(width: CGFloat(downsampledImage.width), height: CGFloat(downsampledImage.height))
        let finalImage = NSImage(cgImage: downsampledImage, size: size)
        #endif
        
        cache.set(finalImage, forKey: cacheKey)
        return finalImage
    }
}

public class ImageCache {
    private let cache = NSCache<NSString, PlatformImage>()
    private var keys = Set<NSString>()
    private let lock = NSLock()
    
    public init() {
        cache.countLimit = 100
        cache.totalCostLimit = 200 * 1024 * 1024 // 200MB default
    }
    
    public func setCostLimit(_ bytes: Int) {
        cache.totalCostLimit = bytes
    }
    
    public func get(forKey key: NSString) -> PlatformImage? {
        return cache.object(forKey: key)
    }
    
    public func set(_ image: PlatformImage, forKey key: NSString) {
        lock.lock()
        keys.insert(key)
        lock.unlock()
        
        // Estimate cost based on pixels: width * height * 4 bytes
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key, cost: cost)
    }
    
    public func clear() {
        lock.lock()
        keys.removeAll()
        lock.unlock()
        cache.removeAllObjects()
    }
    
    public func keepOnly(prefixes: Set<String>) {
        lock.lock()
        let keysToRemove = keys.filter { key in
            !prefixes.contains(where: { key.hasPrefix($0) })
        }
        for key in keysToRemove {
            cache.removeObject(forKey: key)
            keys.remove(key)
        }
        lock.unlock()
    }
}

public class PreloadManager {
    public static let shared = PreloadManager()
    private var preheatTask: Task<Void, Never>?
    private var currentTargetIndices: [Int] = []

    public func updatePreload(currentIndex: Int, pages: [ComicPage], prefetchCount: Int, targetSize: CGSize, direction: Int = 1) {
        // Memory-aware window shrinking
        let memoryUsed = Double(reportMemoryUsage()) / (1024 * 1024)
        var actualCount = prefetchCount

        if memoryUsed > 400 {
            ImageProvider.clearCache()
            cancelAll()
            return // Stop preloading under high pressure
        } else if memoryUsed > 300 {
            actualCount = min(1, prefetchCount) // Shrink window
        }

        let nextRange = (currentIndex + 1)...min(pages.count - 1, currentIndex + actualCount)
        let prevRange = max(0, currentIndex - actualCount)..<currentIndex

        let prioritizedIndices = direction >= 0
            ? Array(nextRange) + Array(prevRange).reversed()
            : Array(prevRange).reversed() + Array(nextRange)

        if currentTargetIndices == prioritizedIndices {
            return // No need to restart if targets are the same
        }

        currentTargetIndices = prioritizedIndices
        preheatTask?.cancel()

        preheatTask = Task.detached(priority: .background) {
            let scale = await MainActor.run { UIScreen.main.scale }

            for i in prioritizedIndices {
                if Task.isCancelled { return }

                let url = pages[i].imageURL
                let key = ImageProvider.getCacheKey(url: url, targetSize: targetSize, scale: scale)

                // Skip if already in cache
                if ImageProvider.cache.get(forKey: key) != nil {
                    continue
                }

                _ = ImageProvider.downsample(imageAt: url, to: targetSize, scale: scale)

                // Small throttle after actual work to prevent maxing out CPU
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms throttle
            }
        }
    }

    public func cancelAll() {
        preheatTask?.cancel()
        currentTargetIndices = []
    }

    private func reportMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
public struct LocalAsyncImage<Placeholder: View>: View {
    public let url: URL?
    public let targetSize: CGSize
    public let placeholder: () -> Placeholder
    
    @State private var loadedImage: PlatformImage?
    @Environment(\.displayScale) var displayScale
    
    public init(url: URL?, targetSize: CGSize, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.targetSize = targetSize
        self.placeholder = placeholder
    }
    
    public var body: some View {
        Group {
            if let img = currentImage {
                Image(platformImage: img)
                    .resizable()
            } else {
                placeholder()
            }
        }
        .onAppear(perform: performLoad)
        .onChange(of: url) { _ in performLoad() }
    }
    
    private var currentImage: PlatformImage? {
        // High-priority synchronous check during render
        if let loaded = loadedImage { return loaded }
        guard let url = url else { return nil }
        let key = ImageProvider.getCacheKey(url: url, targetSize: targetSize, scale: displayScale)
        return ImageProvider.cache.get(forKey: key)
    }
    
    private func performLoad() {
        guard let url = url else { return }
        
        let key = ImageProvider.getCacheKey(url: url, targetSize: targetSize, scale: displayScale)
        if let cached = ImageProvider.cache.get(forKey: key) {
            self.loadedImage = cached
            return
        }

        let currentScale = displayScale
        Task.detached(priority: .userInitiated) {
            if let img = ImageProvider.downsample(imageAt: url, to: targetSize, scale: currentScale) {
                await MainActor.run {
                    self.loadedImage = img
                }
            }
        }
        }}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
