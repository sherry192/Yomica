import SwiftUI

enum ReadingDirection: String, CaseIterable, Identifiable {
    case topToBottomContinuous = "从上至下（连续）"
    case leftToRightSingle = "从左至右（单页）"
    case leftToRightContinuous = "从左至右（连续）"
    case rightToLeftSingle = "从右至左（单页）"
    case rightToLeftContinuous = "从右至左（连续）"
    
    var id: String { self.rawValue }
    
    var isRTL: Bool {
        self == .rightToLeftSingle || self == .rightToLeftContinuous
    }
    
    var isHorizontalContinuous: Bool {
        self == .leftToRightContinuous || self == .rightToLeftContinuous
    }
}

enum LongPressZoomPosition: String, CaseIterable, Identifiable {
    case pressPosition = "按压位置"
    case screenCenter = "屏幕中心"
    var id: String { self.rawValue }
}

struct ReaderView: View {
    let comic: ComicBook
    @State var currentIndex: Int
    @State private var showControls = false
    @State private var showingSettings = false
    @EnvironmentObject var manager: ComicManager
    @Environment(\.dismiss) var dismiss
    
    // 读取共享设置
    @AppStorage("reading_direction") private var readingDirection: ReadingDirection = .leftToRightSingle
    @AppStorage("reading_isMultiPageEnabled") private var isMultiPageEnabled = false
    @AppStorage("reading_landscapeColumnCount") private var landscapeColumnCount = 2
    @AppStorage("reading_enablePageAnimation") private var enablePageAnimation = true
    @AppStorage("reading_doubleTapToZoom") private var doubleTapToZoom = true
    @AppStorage("reading_longPressToZoom") private var longPressToZoom = true
    @AppStorage("reading_longPressZoomPosition") private var longPressZoomPosition: LongPressZoomPosition = .pressPosition
    @AppStorage("reading_showPageNumber") private var showPageNumber = true
    @AppStorage("reading_enablePrefetch") private var enablePrefetch = true
    @AppStorage("reading_prefetchCount") private var prefetchCount = 3
    @AppStorage("reading_enableAutoTurn") private var enableAutoTurn = false
    @AppStorage("reading_autoTurnInterval") private var autoTurnInterval = 5
    
    @State private var scrollTargetId: Int?
    @State private var autoTurnCounter: Int = 0
    @State private var visibleIndices: Set<Int> = []
    @State private var lastIndexForDirection: Int = 0
    
    init(comic: ComicBook, initialIndex: Int) {
        self.comic = comic
        _currentIndex = State(initialValue: initialIndex)
    }
    
    private func getEffectiveColumnCount(for size: CGSize) -> Int {
        if !isMultiPageEnabled { return 1 }
        #if os(macOS)
        return landscapeColumnCount
        #else
        let isLandscape = size.width > size.height || UIDevice.current.userInterfaceIdiom == .pad
        return isLandscape ? landscapeColumnCount : 1
        #endif
    }
    
    private func getPageGroups(columnCount: Int) -> [[Int]] {
        var groups: [[Int]] = []
        var i = 0
        while i < comic.pages.count {
            var group: [Int] = []
            for j in 0..<columnCount {
                if i + j < comic.pages.count { group.append(i + j) }
            }
            groups.append(group)
            i += columnCount
        }
        return groups
    }
    
    var body: some View {
        GeometryReader { screenGeo in
            let colCount = getEffectiveColumnCount(for: screenGeo.size)
            let groups = getPageGroups(columnCount: colCount)
            let currentGroupIndex = groups.firstIndex(where: { $0.contains(currentIndex) }) ?? 0
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                ReaderContentLayer(
                    comic: comic,
                    currentIndex: $currentIndex,
                    scrollTargetId: $scrollTargetId,
                    readingDirection: readingDirection,
                    colCount: colCount,
                    size: screenGeo.size,
                    groups: groups,
                    currentGroupIndex: currentGroupIndex,
                    handleAction: { action, c, g in
                        handleAction(action, colCount: c, groups: g, size: screenGeo.size)
                    }
                )
                .id("\(readingDirection.rawValue)-\(colCount)-\(screenGeo.size.width)-\(screenGeo.size.height)")
                .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    HStack {
                        Text("\(currentIndex + 1) / \(comic.pages.count)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(4)
                            .padding(.leading, 24)
                            .padding(.bottom, 40)
                        Spacer()
                    }
                }
                .opacity(showPageNumber && !showControls && !showingSettings ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showControls)
                
                if showControls {
                    VStack {
                        headerView.padding(.top, 40)
                        Spacer()
                        footerView.padding(.bottom, 40)
                    }
                    .transition(.opacity)
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                let colCount = getEffectiveColumnCount(for: screenGeo.size)
                guard enableAutoTurn && colCount == 1 && (readingDirection == .leftToRightSingle || readingDirection == .rightToLeftSingle) else { return }
                if showControls || showingSettings { return }
                
                autoTurnCounter += 1
                if autoTurnCounter >= autoTurnInterval {
                    autoTurnCounter = 0
                    let groups = getPageGroups(columnCount: colCount)
                    handleAction(.pageTurn(1), colCount: colCount, groups: groups, size: screenGeo.size)
                }
            }
            .onChange(of: currentIndex) { newValue in
                autoTurnCounter = 0
                let colCount = getEffectiveColumnCount(for: screenGeo.size)
                updateCacheWindow(for: newValue, size: screenGeo.size, colCount: colCount)
            }
            .onAppear {
                let colCount = getEffectiveColumnCount(for: screenGeo.size)
                updateCacheWindow(for: currentIndex, size: screenGeo.size, colCount: colCount)
            }
            .onDisappear {
                PreloadManager.shared.cancelAll()
                ImageProvider.cache.clear()
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .background(
            EmptyView()
                .sheet(isPresented: $showingSettings) {
                    ReadingSettingsView(isSheet: true)
                        .presentationDetents([.fraction(0.55), .medium, .large])
                        .presentationDragIndicator(.visible)
                }
        )
    }

    private func updateCacheWindow(for index: Int, size: CGSize, colCount: Int) {
        let count = enablePrefetch ? prefetchCount : 1
        let start = max(0, index - count)
        let end = min(comic.pages.count - 1, index + count)
        let range = start...end
        
        var prefixes = Set<String>()
        for i in range {
            prefixes.insert(comic.pages[i].imageURL.path)
        }
        
        // Evict images outside of the window
        ImageProvider.cache.keepOnly(prefixes: prefixes)
        
        if enablePrefetch {
            let direction = index >= lastIndexForDirection ? 1 : -1
            let effectiveColCount = (readingDirection.isHorizontalContinuous || readingDirection == .topToBottomContinuous) ? 1 : colCount
            let targetPageSize = CGSize(width: size.width / CGFloat(effectiveColCount), height: size.height)
            PreloadManager.shared.updatePreload(currentIndex: index, pages: comic.pages, prefetchCount: prefetchCount, targetSize: targetPageSize, direction: direction)
            lastIndexForDirection = index
        }
    }
    
    private func handleAction(_ action: ZoomableAction, colCount: Int, groups: [[Int]], size: CGSize) {
        switch action {
        case .pageTurn(let direction):
            let adjustedDirection = readingDirection.isRTL ? -direction : direction
            
            var nextIndex = currentIndex
            if colCount > 1 && (readingDirection == .leftToRightSingle || readingDirection == .rightToLeftSingle) {
                let currentGroupIdx = groups.firstIndex(where: { $0.contains(currentIndex) }) ?? 0
                let nextGroupIndex = currentGroupIdx + adjustedDirection
                if nextGroupIndex >= 0 && nextGroupIndex < groups.count {
                    nextIndex = groups[nextGroupIndex][0]
                }
            } else {
                if adjustedDirection == -1 && currentIndex > 0 {
                    nextIndex -= 1
                } else if adjustedDirection == 1 && currentIndex < comic.pages.count - 1 {
                    nextIndex += 1
                }
            }
            
            if nextIndex == currentIndex { return }
            
            let applyTurn = {
                currentIndex = nextIndex
                scrollTargetId = nextIndex
            }
            
            if enablePageAnimation || readingDirection.isHorizontalContinuous || readingDirection == .topToBottomContinuous {
                withAnimation { applyTurn() }
            } else {
                // Phase 3: Double Buffering mechanism
                // Prevent View from updating to the new index until the image is decoded and cached.
                // This keeps the previous page visible instead of showing a black flash.
                let targetPageSize = CGSize(width: size.width / CGFloat(colCount), height: size.height)
                let scale = UIScreen.main.scale
                
                let nextGroupIdx = groups.firstIndex(where: { $0.contains(nextIndex) }) ?? 0
                let nextGroup = groups[nextGroupIdx]
                let urls = nextGroup.map { comic.pages[$0].imageURL }
                
                let allCached = urls.allSatisfy { url in
                    let key = ImageProvider.getCacheKey(url: url, targetSize: targetPageSize, scale: scale)
                    return ImageProvider.cache.get(forKey: key) != nil
                }
                
                if allCached {
                    applyTurn()
                } else {
                    Task.detached(priority: .userInitiated) {
                        for url in urls {
                            _ = ImageProvider.downsample(imageAt: url, to: targetPageSize, scale: scale)
                        }
                        await MainActor.run { applyTurn() }
                    }
                }
            }
        case .toggleControls:
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .foregroundColor(.white)
            }
            Spacer()
            Button(action: {
                manager.toggleFavorite(pageAt: currentIndex, in: comic)
            }) {
                Image(systemName: manager.isFavorite(pageAt: currentIndex, in: comic) ? "star.fill" : "star")
                    .font(.title3.bold())
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .foregroundColor(manager.isFavorite(pageAt: currentIndex, in: comic) ? .yellow : .white)
            }
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3.bold())
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 24)
    }
    
    private var footerView: some View {
        VStack(spacing: 12) {
            HStack {
                Text(LocalizedStringKey("第 \(currentIndex + 1) 页"))
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
                Text(LocalizedStringKey("共 \(comic.pages.count) 页"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 4)
            
            Slider(value: Binding(
                get: { Double(currentIndex) },
                set: { 
                    currentIndex = Int($0)
                    scrollTargetId = currentIndex
                }
            ), in: 0...Double(max(0, comic.pages.count - 1)), step: 1)
            .accentColor(.blue)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .shadow(radius: 10)
        )
        .padding(.horizontal, 24)
    }
}

struct ReaderContentLayer: View {
    let comic: ComicBook
    @Binding var currentIndex: Int
    @Binding var scrollTargetId: Int?
    let readingDirection: ReadingDirection
    let colCount: Int
    let size: CGSize
    let groups: [[Int]]
    let currentGroupIndex: Int
    let handleAction: (ZoomableAction, Int, [[Int]]) -> Void

    var body: some View {
        if readingDirection == .topToBottomContinuous {
            ReaderVerticalScrollView(comic: comic, currentIndex: $currentIndex, scrollTargetId: $scrollTargetId, size: size, handleAction: handleAction)
        } else if readingDirection.isHorizontalContinuous {
            ReaderHorizontalScrollView(comic: comic, currentIndex: $currentIndex, scrollTargetId: $scrollTargetId, size: size, readingDirection: readingDirection, handleAction: handleAction)
        } else {
            ReaderPagedTabView(comic: comic, currentIndex: $currentIndex, readingDirection: readingDirection, colCount: colCount, size: size, groups: groups, currentGroupIndex: currentGroupIndex, handleAction: handleAction)
        }
    }
}

struct ReaderVerticalScrollView: View {
    let comic: ComicBook
    @Binding var currentIndex: Int
    @Binding var scrollTargetId: Int?
    let size: CGSize
    let handleAction: (ZoomableAction, Int, [[Int]]) -> Void
    @State private var visibleIndices: Set<Int> = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(comic.pages.enumerated()), id: \.element.id) { index, page in
                        ZoomableView(imageURL: page.imageURL, isContinuous: true, screenSize: size) { action in
                            handleAction(action, 1, [])
                        }
                        .frame(width: size.width)
                        .id(index)
                        .onAppear {
                            visibleIndices.insert(index)
                            if scrollTargetId == nil { currentIndex = visibleIndices.min() ?? index }
                        }
                        .onDisappear {
                            visibleIndices.remove(index)
                            if scrollTargetId == nil { currentIndex = visibleIndices.min() ?? currentIndex }
                        }
                    }
                }
            }
            .onAppear { proxy.scrollTo(currentIndex, anchor: .top) }
            .onChange(of: scrollTargetId) { newValue in
                if let target = newValue {
                    proxy.scrollTo(target, anchor: .top)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if scrollTargetId == target { scrollTargetId = nil }
                    }
                }
            }
        }
    }
}

struct ReaderHorizontalScrollView: View {
    let comic: ComicBook
    @Binding var currentIndex: Int
    @Binding var scrollTargetId: Int?
    let size: CGSize
    let readingDirection: ReadingDirection
    let handleAction: (ZoomableAction, Int, [[Int]]) -> Void
    @State private var visibleIndices: Set<Int> = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(comic.pages.enumerated()), id: \.element.id) { index, page in
                        ZoomableView(imageURL: page.imageURL, isContinuous: true, screenSize: size) { action in
                            handleAction(action, 1, [])
                        }
                        .frame(height: size.height)
                        .id(index)
                        .onAppear {
                            visibleIndices.insert(index)
                            if scrollTargetId == nil { currentIndex = visibleIndices.min() ?? index }
                        }
                        .onDisappear {
                            visibleIndices.remove(index)
                            if scrollTargetId == nil { currentIndex = visibleIndices.min() ?? currentIndex }
                        }
                    }
                }
            }
            .environment(\.layoutDirection, readingDirection.isRTL ? .rightToLeft : .leftToRight)
            .onAppear { proxy.scrollTo(currentIndex, anchor: readingDirection.isRTL ? .trailing : .leading) }
            .onChange(of: scrollTargetId) { newValue in
                if let target = newValue {
                    proxy.scrollTo(target, anchor: readingDirection.isRTL ? .trailing : .leading)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if scrollTargetId == target { scrollTargetId = nil }
                    }
                }
            }
        }
    }
}

struct ReaderPagedTabView: View {
    let comic: ComicBook
    @Binding var currentIndex: Int
    let readingDirection: ReadingDirection
    let colCount: Int
    let size: CGSize
    let groups: [[Int]]
    let currentGroupIndex: Int
    let handleAction: (ZoomableAction, Int, [[Int]]) -> Void

    var body: some View {
        TabView(selection: Binding(
            get: { currentGroupIndex },
            set: { newGroupIndex in
                if newGroupIndex < groups.count {
                    currentIndex = groups[newGroupIndex][0]
                }
            }
        )) {
            ForEach(0..<groups.count, id: \.self) { gIndex in
                let group = groups[gIndex]
                HStack(spacing: 0) {
                    ForEach(group.indices, id: \.self) { i in
                        let pIndex = group[i]
                        ZoomableView(
                            imageURL: comic.pages[pIndex].imageURL,
                            screenSize: CGSize(width: size.width / CGFloat(colCount), height: size.height),
                            multiPageInfo: ZoomableMultiPageInfo(
                                isMultiPage: colCount > 1,
                                pageIndexInGroup: i,
                                totalPagesInGroup: group.count
                            )
                        ) { action in
                            handleAction(action, colCount, groups)
                        }
                    }
                }
                .tag(gIndex)
            }
        }
        .environment(\.layoutDirection, readingDirection.isRTL ? .rightToLeft : .leftToRight)
        #if os(iOS)
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        #endif
    }
}

// MARK: - 公用阅读设置页
struct ReadingSettingsView: View {
    @Environment(\.dismiss) var dismiss
    var isSheet: Bool = false
    
    @AppStorage("reading_direction") private var readingDirection: ReadingDirection = .leftToRightSingle
    @AppStorage("reading_isMultiPageEnabled") private var isMultiPageEnabled = false
    @AppStorage("reading_landscapeColumnCount") private var landscapeColumnCount = 2
    @AppStorage("reading_brightnessFollowSystem") private var brightnessFollowSystem = true
    @AppStorage("reading_enablePageAnimation") private var enablePageAnimation = true
    @AppStorage("reading_doubleTapToZoom") private var doubleTapToZoom = true
    @AppStorage("reading_longPressToZoom") private var longPressToZoom = true
    @AppStorage("reading_longPressZoomPosition") private var longPressZoomPosition: LongPressZoomPosition = .pressPosition
    @AppStorage("reading_showPageNumber") private var showPageNumber = true
    @AppStorage("reading_enablePrefetch") private var enablePrefetch = true
    @AppStorage("reading_useOptimizedEngine") private var useOptimizedEngine = false
    @AppStorage("reading_prefetchCount") private var prefetchCount = 3
    @AppStorage("reading_enableAutoTurn") private var enableAutoTurn = false
    @AppStorage("reading_autoTurnInterval") private var autoTurnInterval = 5

    var body: some View {
        let content = Form {
            Section(header: Text(LocalizedStringKey("翻页方式"))) {
                Picker(LocalizedStringKey("阅读方向"), selection: $readingDirection) {
                    ForEach(ReadingDirection.allCases) { direction in
                        Text(LocalizedStringKey(direction.rawValue)).tag(direction)
                    }
                }
                
                if readingDirection == .leftToRightSingle || readingDirection == .rightToLeftSingle {
                    Toggle(LocalizedStringKey("多页展示 (横屏)"), isOn: $isMultiPageEnabled)
                    if isMultiPageEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizedStringKey("横屏同屏幕图片数量 (仅画廊模式)"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(landscapeColumnCount) },
                                    set: { landscapeColumnCount = Int($0) }
                                ), in: 2...5, step: 1)
                                Text("\(landscapeColumnCount).0")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 35)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Toggle(LocalizedStringKey("自动翻页"), isOn: $enableAutoTurn)
                        if enableAutoTurn {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(LocalizedStringKey("翻页间隔（秒）"))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Slider(value: Binding(
                                        get: { Double(autoTurnInterval) },
                                        set: { autoTurnInterval = Int($0) }
                                    ), in: 1...10, step: 1)
                                    Text("\(autoTurnInterval)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 30)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Toggle(LocalizedStringKey("开启翻页动画"), isOn: $enablePageAnimation)
                }
            }
            
            Section(header: Text(LocalizedStringKey("交互"))) {
                Toggle(LocalizedStringKey("双击放大"), isOn: $doubleTapToZoom)
                Toggle(LocalizedStringKey("长按缩放"), isOn: $longPressToZoom)
                if longPressToZoom {
                    Picker(LocalizedStringKey("长按缩放位置"), selection: $longPressZoomPosition) {
                        ForEach(LongPressZoomPosition.allCases) { pos in
                            Text(LocalizedStringKey(pos.rawValue)).tag(pos)
                        }
                    }
                }
            }
            
            Section(header: Text(LocalizedStringKey("显示"))) {
                Toggle(LocalizedStringKey("显示页数"), isOn: $showPageNumber)
                Toggle(LocalizedStringKey("亮度跟随系统"), isOn: $brightnessFollowSystem)
            }
            
            Section(header: Text(LocalizedStringKey("性能"))) {
                Toggle(LocalizedStringKey("开启预加载页面数量"), isOn: $enablePrefetch)
                if enablePrefetch {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey("预加载页面数量"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        HStack {
                            Slider(value: Binding(
                                get: { Double(prefetchCount) },
                                set: { prefetchCount = Int($0) }
                            ), in: 1...10, step: 1)
                            Text("\(prefetchCount)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 30)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        
        if isSheet {
            NavigationStack {
                content
                    .navigationTitle(LocalizedStringKey("阅读"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(LocalizedStringKey("完成")) { dismiss() }
                        }
                    }
            }
        } else {
            content
                .navigationTitle(LocalizedStringKey("阅读"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }
}

enum ZoomableAction {
    case pageTurn(Int)
    case toggleControls
}

struct ZoomableMultiPageInfo {
    var isMultiPage: Bool
    var pageIndexInGroup: Int
    var totalPagesInGroup: Int
}

struct ZoomableView: View {
    let imageURL: URL
    var isContinuous: Bool = false
    var screenSize: CGSize = .zero
    var multiPageInfo: ZoomableMultiPageInfo = ZoomableMultiPageInfo(isMultiPage: false, pageIndexInGroup: 0, totalPagesInGroup: 1)
    var onAction: ((ZoomableAction) -> Void)? = nil
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    @AppStorage("reading_doubleTapToZoom") private var doubleTapToZoom = true
    @AppStorage("reading_longPressToZoom") private var longPressToZoom = true
    
    var body: some View {
        if isContinuous {
            LocalAsyncImage(url: imageURL, targetSize: screenSize) {
                ProgressView()
                    .frame(width: screenSize.width, height: screenSize.width * 1.5)
            }
            .scaledToFit()
            .onTapGesture {
                onAction?(.toggleControls)
            }
        } else {
            GeometryReader { geometry in
                let targetSize = screenSize == .zero ? geometry.size : screenSize
                LocalAsyncImage(url: imageURL, targetSize: targetSize) {
                    ProgressView()
                        .frame(width: targetSize.width, height: targetSize.height)
                }
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let width = geometry.size.width
                    let x = location.x
                    
                    if multiPageInfo.isMultiPage {
                        if multiPageInfo.pageIndexInGroup == 0 {
                            if x < width * 0.5 { onAction?(.pageTurn(-1)) }
                            else { onAction?(.toggleControls) }
                        } else if multiPageInfo.pageIndexInGroup == multiPageInfo.totalPagesInGroup - 1 {
                            if x > width * 0.5 { onAction?(.pageTurn(1)) }
                            else { onAction?(.toggleControls) }
                        } else {
                            onAction?(.toggleControls)
                        }
                    } else {
                        if x < width * 0.35 { onAction?(.pageTurn(-1)) }
                        else if x > width * 0.65 { onAction?(.pageTurn(1)) }
                        else { onAction?(.toggleControls) }
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { value in
                            lastScale = scale
                            if scale < 1.0 { resetZoom() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.0 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { value in
                            if scale > 1.0 { lastOffset = offset }
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            if longPressToZoom {
                                withAnimation {
                                    if scale > 1.0 { resetZoom() } else {
                                        scale = 2.5
                                        lastScale = 2.5
                                    }
                                }
                            }
                        }
                )
            }
        }
    }
    
    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}
