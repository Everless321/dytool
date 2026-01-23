//
//  VideoGalleryView.swift
//  dyTool
//
//  视频浏览视图 - 本地文件扫描
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoGalleryView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @State private var folders: [LocalFolder] = []
    @State private var videos: [LocalVideo] = []
    @State private var selectedFolder: String?
    @State private var isLoading = false
    @State private var viewMode: ViewMode = .grid
    @State private var playingVideo: LocalVideo?
    @State private var player: AVPlayer?

    // 图集查看
    @State private var viewingImageSet: LocalVideo?

    // 分页加载
    @State private var allVideoPaths: [URL] = []  // 符合过滤条件的视频/图集路径
    @State private var loadedCount: Int = 0
    @State private var isLoadingMore = false
    @State private var loadedPathSet: Set<String> = []  // 已加载路径集合，防止重复
    @State private var isFiltering = false  // 过滤加载状态
    private let pageSize = 50  // 每页加载数量

    // 分析数据
    @State private var analysisMap: [String: VideoAnalysis] = [:]

    // 过滤器
    @State private var showFilters = false
    @State private var minSexyLevel: Int = 0
    @State private var maxSexyLevel: Int = 10
    @State private var selectedTags: Set<String> = []
    @State private var selectedCategory: String?
    @State private var selectedAuthor: String?
    @State private var onlyAnalyzed: Bool = false

    // 所有可选标签
    @State private var availableTags: [String] = []
    @State private var availableCategories: [String] = []
    @State private var tagSearchText: String = ""  // 标签搜索

    enum ViewMode {
        case grid, list
    }

    // 是否有活跃的过滤条件（用于UI显示）
    private var hasActiveFilters: Bool {
        (selectedAuthor != nil && !selectedAuthor!.isEmpty) ||
        onlyAnalyzed ||
        minSexyLevel > 0 ||
        maxSexyLevel < 10 ||
        !selectedTags.isEmpty ||
        (selectedCategory != nil && !selectedCategory!.isEmpty)
    }

    // 搜索过滤后的标签
    private var filteredTags: [String] {
        if tagSearchText.isEmpty {
            return availableTags
        }
        return availableTags.filter { $0.localizedCaseInsensitiveContains(tagSearchText) }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
    ]

    var body: some View {
        ZStack {
        HSplitView {
            // 文件夹列表
            VStack(alignment: .leading, spacing: 0) {
                Text("用户文件夹")
                    .font(.headline)
                    .padding()

                Divider()

                List(selection: $selectedFolder) {
                    Button {
                        selectedFolder = nil
                        loadVideos()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("全部视频")
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedFolder == nil ? Color.accentColor.opacity(0.2) : Color.clear)

                    ForEach(folders) { folder in
                        Button {
                            selectedFolder = folder.name
                            loadVideos()
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                Text(folder.name)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(folder.videoCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedFolder == folder.name ? Color.accentColor.opacity(0.2) : Color.clear)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 180, maxWidth: 250)

            // 视频网格
            VStack(spacing: 0) {
                // 工具栏
                HStack {
                    Text(selectedFolder ?? "全部视频")
                        .font(.headline)

                    Spacer()

                    Text("\(videos.count) / \(allVideoPaths.count) 个")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // 过滤加载中
                    if isFiltering {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    // 过滤器按钮
                    Button {
                        showFilters.toggle()
                    } label: {
                        Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .help("过滤器")

                    Picker("", selection: $viewMode) {
                        Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                        Image(systemName: "list.bullet").tag(ViewMode.list)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 80)

                    Button {
                        loadFolders()
                        loadVideos()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding()

                // 过滤器面板
                if showFilters {
                    filterPanel
                }

                Divider()

                // 视频内容
                if isLoading && videos.isEmpty {
                    Spacer()
                    ProgressView("加载中...")
                    Spacer()
                } else if isFiltering {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在筛选...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if videos.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(hasActiveFilters ? "无匹配视频" : "暂无视频")
                            .font(.headline)
                        Text(hasActiveFilters ? "调整过滤条件查看更多视频" : "下载视频后会在这里显示")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        switch viewMode {
                        case .grid:
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                                    LocalVideoGridItem(video: video, onPlay: {
                                        if video.isImageSet {
                                            viewingImageSet = video
                                        } else {
                                            playVideo(video)
                                        }
                                    }, onDelete: {
                                        deleteVideo(video)
                                    }, onAuthorTap: { author in
                                        // 跳转到该作者的视频
                                        selectedAuthor = author
                                        showFilters = true
                                    }, onTagTap: { tag in
                                        // 添加标签过滤
                                        selectedTags.insert(tag)
                                        showFilters = true
                                    })
                                    .onAppear {
                                        // 当显示最后几个元素时触发加载更多
                                        if index >= videos.count - 6 {
                                            loadMoreVideos()
                                        }
                                    }
                                }

                                // 加载状态显示
                                if hasMoreVideos {
                                    loadingIndicator
                                }
                            }
                            .padding()
                        case .list:
                            LazyVStack(spacing: 8) {
                                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                                    LocalVideoListItem(video: video, onPlay: {
                                        if video.isImageSet {
                                            viewingImageSet = video
                                        } else {
                                            playVideo(video)
                                        }
                                    }, onDelete: {
                                        deleteVideo(video)
                                    }, onAuthorTap: { author in
                                        selectedAuthor = author
                                        showFilters = true
                                    }, onTagTap: { tag in
                                        selectedTags.insert(tag)
                                        showFilters = true
                                    })
                                    .onAppear {
                                        // 当显示最后几个元素时触发加载更多
                                        if index >= videos.count - 6 {
                                            loadMoreVideos()
                                        }
                                    }
                                }

                                // 加载状态显示
                                if hasMoreVideos {
                                    loadingIndicator
                                }
                            }
                            .padding()
                        }

                        // 底部状态
                        if !hasMoreVideos && !videos.isEmpty {
                            HStack {
                                Spacer()
                                Text("已加载全部 \(allVideoPaths.count) 个")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                }
            }
        }

            // 视频播放器覆盖层
            if let video = playingVideo, let player = player {
                VideoPlayerOverlay(
                    video: video,
                    player: player,
                    onClose: {
                        stopVideo()
                    }
                )
            }

            // 图集查看器覆盖层
            if let imageSet = viewingImageSet {
                ImageSetViewer(
                    imageSet: imageSet,
                    onClose: {
                        viewingImageSet = nil
                    }
                )
            }
        }
        .onAppear {
            loadFolders()
            loadVideos()
            loadAnalysisData()
        }
        .onChange(of: selectedFolder) { _, _ in
            applyFilters()
        }
        .onChange(of: selectedAuthor) { _, _ in
            applyFilters()
        }
        .onChange(of: selectedTags) { _, _ in
            applyFilters()
        }
        .onChange(of: selectedCategory) { _, _ in
            applyFilters()
        }
        .onChange(of: minSexyLevel) { _, _ in
            applyFilters()
        }
        .onChange(of: maxSexyLevel) { _, _ in
            applyFilters()
        }
        .onChange(of: onlyAnalyzed) { _, _ in
            applyFilters()
        }
    }

    // MARK: - 加载指示器

    @ViewBuilder
    private var loadingIndicator: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView()
                    .scaleEffect(0.8)
                Text("加载中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("已加载 \(videos.count) / \(allVideoPaths.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - 过滤器面板

    private var filterPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // 作者过滤
                VStack(alignment: .leading, spacing: 4) {
                    Text("作者")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { selectedAuthor ?? "" },
                        set: { selectedAuthor = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("全部").tag("")
                        ForEach(folders) { folder in
                            Text(folder.name).tag(folder.name)
                        }
                    }
                    .frame(width: 140)
                }

                Divider()
                    .frame(height: 30)

                // 擦边等级范围
                VStack(alignment: .leading, spacing: 4) {
                    Text("擦边等级")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Text("\(minSexyLevel)")
                            .frame(width: 20)
                        Slider(value: Binding(
                            get: { Double(minSexyLevel) },
                            set: { minSexyLevel = Int($0) }
                        ), in: 0...10, step: 1)
                        .frame(width: 80)
                        Text("~")
                        Slider(value: Binding(
                            get: { Double(maxSexyLevel) },
                            set: { maxSexyLevel = Int($0) }
                        ), in: 0...10, step: 1)
                        .frame(width: 80)
                        Text("\(maxSexyLevel)")
                            .frame(width: 20)
                    }
                }

                Divider()
                    .frame(height: 30)

                // 分类过滤
                VStack(alignment: .leading, spacing: 4) {
                    Text("分类")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { selectedCategory ?? "" },
                        set: { selectedCategory = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("全部").tag("")
                        ForEach(availableCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .frame(width: 100)
                }

                Divider()
                    .frame(height: 30)

                // 只显示已分析
                Toggle("仅已分析", isOn: $onlyAnalyzed)

                Spacer()

                // 重置过滤器
                Button("重置") {
                    minSexyLevel = 0
                    maxSexyLevel = 10
                    selectedTags.removeAll()
                    selectedCategory = nil
                    selectedAuthor = nil
                    onlyAnalyzed = false
                    tagSearchText = ""
                }
            }

            // 标签选择
            if !availableTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // 标签搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索标签...", text: $tagSearchText)
                            .textFieldStyle(.plain)
                        if !tagSearchText.isEmpty {
                            Button {
                                tagSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .frame(width: 200)

                    // 标签列表
                    ScrollView {
                        FlowLayout(spacing: 6) {
                            ForEach(filteredTags, id: \.self) { tag in
                                TagFilterChip(
                                    tag: tag,
                                    isSelected: selectedTags.contains(tag),
                                    onToggle: {
                                        if selectedTags.contains(tag) {
                                            selectedTags.remove(tag)
                                        } else {
                                            selectedTags.insert(tag)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func loadFolders() {
        let path = databaseService.settings.path
        let downloadDir = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: downloadDir.path) else {
            folders = []
            return
        }

        var allFolders: [LocalFolder] = []

        do {
            // 目录结构: Downloads/douyin/post/作者/作品
            // 需要遍历到第三级目录获取作者
            let topDirs = try FileManager.default.contentsOfDirectory(
                at: downloadDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )

            for topDir in topDirs {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: topDir.path, isDirectory: &isDir),
                      isDir.boolValue else {
                    continue
                }

                // 跳过 log 等非作品目录
                let dirName = topDir.lastPathComponent.lowercased()
                if dirName == "log" || dirName == "logs" || dirName.hasPrefix(".") {
                    continue
                }

                // 获取二级目录 (如 post, like 等)
                let secondLevelDirs = try FileManager.default.contentsOfDirectory(
                    at: topDir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: .skipsHiddenFiles
                )

                for secondDir in secondLevelDirs {
                    var isSecondDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: secondDir.path, isDirectory: &isSecondDir),
                          isSecondDir.boolValue else {
                        continue
                    }

                    // 获取三级目录（作者目录）
                    let authorDirs = try FileManager.default.contentsOfDirectory(
                        at: secondDir,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: .skipsHiddenFiles
                    )

                    for authorDir in authorDirs {
                        var isAuthorDir: ObjCBool = false
                        guard FileManager.default.fileExists(atPath: authorDir.path, isDirectory: &isAuthorDir),
                              isAuthorDir.boolValue else {
                            continue
                        }

                        let videoCount = countVideos(in: authorDir)
                        if videoCount > 0 {
                            allFolders.append(LocalFolder(
                                name: authorDir.lastPathComponent,
                                path: authorDir.path,
                                videoCount: videoCount
                            ))
                        }
                    }
                }
            }

            folders = allFolders.sorted { $0.name < $1.name }
        } catch {
            print("加载文件夹失败: \(error)")
            folders = []
        }
    }

    private func countVideos(in folder: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let fileURL as URL in enumerator {
            if isVideoFile(fileURL) || isImageSetCover(fileURL) {
                count += 1
            }
        }
        return count
    }

    // 应用过滤器 - 重新扫描文件
    private func applyFilters() {
        loadVideos()
    }

    private func loadVideos() {
        isLoading = videos.isEmpty
        isFiltering = !videos.isEmpty
        videos = []
        allVideoPaths = []
        loadedCount = 0
        loadedPathSet.removeAll()

        // 获取符合分析条件的 awemeId 集合
        let matchingAwemeIds = getMatchingAwemeIds()

        DispatchQueue.global(qos: .userInitiated).async {
            let path = databaseService.settings.path
            let downloadDir = URL(fileURLWithPath: path)

            // 确定搜索目录
            var searchDirs: [URL] = []

            if let author = selectedAuthor, !author.isEmpty {
                // 作者过滤：只扫描该作者的文件夹
                if let folder = folders.first(where: { $0.name == author }) {
                    searchDirs = [URL(fileURLWithPath: folder.path)]
                }
            } else if let folderName = selectedFolder,
                      let folder = folders.first(where: { $0.name == folderName }) {
                // 文件夹选择
                searchDirs = [URL(fileURLWithPath: folder.path)]
            } else {
                // 全部：扫描所有作者文件夹
                searchDirs = folders.map { URL(fileURLWithPath: $0.path) }
            }

            // 如果没有文件夹，扫描整个下载目录
            if searchDirs.isEmpty {
                searchDirs = [downloadDir]
            }

            // 收集符合条件的文件路径
            var paths: [(url: URL, date: Date)] = []

            for searchDir in searchDirs {
                guard FileManager.default.fileExists(atPath: searchDir.path) else { continue }

                if let enumerator = FileManager.default.enumerator(
                    at: searchDir,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        if isVideoFile(fileURL) || isImageSetCover(fileURL) {
                            // 如果有分析条件过滤，检查 awemeId 是否匹配
                            if let matchingIds = matchingAwemeIds {
                                let awemeId = fileURL.deletingPathExtension().lastPathComponent
                                if !matchingIds.contains(awemeId) {
                                    continue
                                }
                            }

                            let date = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                            paths.append((fileURL, date))
                        }
                    }
                }
            }

            // 按创建时间排序
            paths.sort { $0.date > $1.date }
            let sortedPaths = paths.map { $0.url }

            DispatchQueue.main.async {
                self.allVideoPaths = sortedPaths
                self.isLoading = false
                self.isFiltering = false
                // 更新可用的过滤选项
                self.updateAvailableFilters()
                // 加载第一页
                self.loadMoreVideos()
            }
        }
    }

    // 根据分析条件获取匹配的 awemeId 集合
    private func getMatchingAwemeIds() -> Set<String>? {
        let hasAnalysisFilters = onlyAnalyzed ||
            minSexyLevel > 0 ||
            maxSexyLevel < 10 ||
            !selectedTags.isEmpty ||
            (selectedCategory != nil && !selectedCategory!.isEmpty)

        guard hasAnalysisFilters else { return nil }

        var matchingIds = Set<String>()

        for (awemeId, analysis) in analysisMap {
            // 擦边等级过滤
            if analysis.sexyLevel < minSexyLevel || analysis.sexyLevel > maxSexyLevel {
                continue
            }

            // 标签过滤
            if !selectedTags.isEmpty {
                let videoTags = Set(analysis.tags)
                if videoTags.isDisjoint(with: selectedTags) {
                    continue
                }
            }

            // 分类过滤
            if let category = selectedCategory, !category.isEmpty {
                if analysis.category != category {
                    continue
                }
            }

            matchingIds.insert(awemeId)
        }

        // 如果只显示已分析的，直接返回匹配的 ID
        // 如果不是，但有其他分析条件，也返回匹配的 ID
        return matchingIds
    }

    private func loadMoreVideos() {
        guard !isLoadingMore else { return }
        guard loadedCount < allVideoPaths.count else { return }

        isLoadingMore = true
        let startIndex = loadedCount
        let endIndex = min(loadedCount + pageSize, allVideoPaths.count)
        let pathsToLoad = Array(allVideoPaths[startIndex..<endIndex])

        DispatchQueue.global(qos: .userInitiated).async {
            let basePath = databaseService.settings.path
            var newVideos: [LocalVideo] = []

            for fileURL in pathsToLoad {
                if isVideoFile(fileURL) {
                    var video = createLocalVideo(from: fileURL, basePath: basePath)
                    video.analysis = self.analysisMap[video.awemeId]
                    newVideos.append(video)
                } else if isImageSetCover(fileURL) {
                    if var imageSet = createLocalImageSet(from: fileURL, basePath: basePath) {
                        imageSet.analysis = self.analysisMap[imageSet.awemeId]
                        newVideos.append(imageSet)
                    }
                }
            }

            DispatchQueue.main.async {
                // 过滤掉已加载的视频
                let uniqueVideos = newVideos.filter { !self.loadedPathSet.contains($0.path) }
                for video in uniqueVideos {
                    self.loadedPathSet.insert(video.path)
                }
                self.videos.append(contentsOf: uniqueVideos)
                self.loadedCount = endIndex
                self.isLoadingMore = false
            }
        }
    }

    private var hasMoreVideos: Bool {
        loadedCount < allVideoPaths.count
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    private func isImageSetCover(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        let imageExtensions = ["jpeg", "jpg", "webp", "png"]
        let ext = url.pathExtension.lowercased()

        // 检查是否是 _cover 文件
        return imageExtensions.contains(ext) && filename.contains("_cover.")
    }

    private func createLocalImageSet(from coverURL: URL, basePath: String) -> LocalVideo? {
        let folder = coverURL.deletingLastPathComponent()
        let coverFilename = coverURL.deletingPathExtension().lastPathComponent

        // 获取基础名（去掉 _cover 后缀）
        guard let range = coverFilename.range(of: "_cover", options: .backwards) else {
            return nil
        }
        let baseName = String(coverFilename[..<range.lowerBound])

        // 查找所有关联的图片
        var imagePaths: [String] = []
        if let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for file in contents {
                let fileName = file.lastPathComponent
                // 匹配 baseName_image_N.webp 格式
                if fileName.hasPrefix(baseName + "_image_") {
                    imagePaths.append(file.path)
                }
            }
        }

        // 没有图片则跳过
        guard !imagePaths.isEmpty else { return nil }

        // 按数字排序
        imagePaths.sort { path1, path2 in
            let num1 = extractImageNumber(from: path1)
            let num2 = extractImageNumber(from: path2)
            return num1 < num2
        }

        let authorFolder = coverURL.deletingLastPathComponent().lastPathComponent

        var size: Int = 0
        var createdAt = Date()

        // 计算总大小
        for imagePath in imagePaths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: imagePath) {
                size += (attrs[.size] as? Int) ?? 0
            }
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: coverURL.path) {
            createdAt = (attrs[.creationDate] as? Date) ?? Date()
        }

        return LocalVideo(
            path: coverURL.path,
            filename: baseName,
            folder: authorFolder,
            size: size,
            createdAt: createdAt,
            coverPath: coverURL.path,
            isImageSet: true,
            imagePaths: imagePaths
        )
    }

    private func extractImageNumber(from path: String) -> Int {
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if let range = filename.range(of: "_image_", options: .backwards) {
            let numStr = String(filename[range.upperBound...])
            return Int(numStr) ?? 0
        }
        return 0
    }

    private func createLocalVideo(from url: URL, basePath: String) -> LocalVideo {
        // 获取视频所在的直接父目录名作为作者名
        let folder = url.deletingLastPathComponent().lastPathComponent

        var size: Int = 0
        var createdAt = Date()

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            size = (attrs[.size] as? Int) ?? 0
            createdAt = (attrs[.creationDate] as? Date) ?? Date()
        }

        // 查找封面
        let coverPath = findCover(for: url)

        return LocalVideo(
            path: url.path,
            filename: url.deletingPathExtension().lastPathComponent,
            folder: folder,
            size: size,
            createdAt: createdAt,
            coverPath: coverPath
        )
    }

    private func findCover(for videoURL: URL) -> String? {
        var baseName = videoURL.deletingPathExtension().lastPathComponent
        let folder = videoURL.deletingLastPathComponent()

        // 如果文件名以 _video 结尾，去掉这个后缀
        if baseName.hasSuffix("_video") {
            baseName = String(baseName.dropLast(6))
        }

        let coverExtensions = ["webp", "jpg", "jpeg", "png"]

        // 查找 _cover 后缀格式
        for ext in coverExtensions {
            let coverURL = folder.appendingPathComponent(baseName + "_cover." + ext)
            if FileManager.default.fileExists(atPath: coverURL.path) {
                return coverURL.path
            }
        }

        // 兼容无后缀格式
        for ext in coverExtensions {
            let coverURL = folder.appendingPathComponent(baseName + "." + ext)
            if FileManager.default.fileExists(atPath: coverURL.path) {
                return coverURL.path
            }
        }
        return nil
    }

    private func deleteVideo(_ video: LocalVideo) {
        do {
            try FileManager.default.removeItem(atPath: video.path)
            if let coverPath = video.coverPath {
                try? FileManager.default.removeItem(atPath: coverPath)
            }
            videos.removeAll { $0.id == video.id }
        } catch {
            print("删除失败: \(error)")
        }
    }

    private func loadAnalysisData() {
        let allAnalysis = databaseService.getAllAnalysis()
        analysisMap = Dictionary(uniqueKeysWithValues: allAnalysis.map { ($0.awemeId, $0) })
        // 标签和分类会在视频加载后更新
    }

    // 根据实际存在的视频更新可用标签
    private func updateAvailableFilters() {
        var tags = Set<String>()
        var categories = Set<String>()

        // 从所有视频路径中提取 awemeId，检查是否有分析数据
        for path in allVideoPaths {
            let awemeId = path.deletingPathExtension().lastPathComponent
            if let analysis = analysisMap[awemeId] {
                tags.formUnion(analysis.tags)
                if !analysis.category.isEmpty {
                    categories.insert(analysis.category)
                }
            }
        }

        availableTags = Array(tags).sorted()
        availableCategories = Array(categories).sorted()
    }

    private func playVideo(_ video: LocalVideo) {
        let url = URL(fileURLWithPath: video.path)
        guard FileManager.default.fileExists(atPath: video.path) else {
            print("[错误] 视频文件不存在: \(video.path)")
            return
        }
        player = AVPlayer(url: url)
        playingVideo = video
        player?.play()
    }

    private func stopVideo() {
        player?.pause()
        player = nil
        playingVideo = nil
    }
}

// MARK: - 本地数据模型

struct LocalFolder: Identifiable {
    let name: String
    let path: String
    let videoCount: Int

    var id: String { name }
}

struct LocalVideo: Identifiable {
    let path: String
    let filename: String
    let folder: String
    let size: Int
    let createdAt: Date
    let coverPath: String?
    var analysis: VideoAnalysis?

    // 图集支持
    var isImageSet: Bool = false
    var imagePaths: [String] = []

    var id: String { path }

    var awemeId: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: createdAt)
    }

    var imageCount: Int {
        imagePaths.count
    }
}

// MARK: - 视频网格项

struct LocalVideoGridItem: View {
    let video: LocalVideo
    let onPlay: () -> Void
    let onDelete: () -> Void
    var onAuthorTap: ((String) -> Void)?
    var onTagTap: ((String) -> Void)?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(9/16, contentMode: .fit)

                    VideoThumbnailView(
                        videoPath: video.path,
                        coverPath: video.coverPath,
                        cornerRadius: 8
                    )

                    // 悬停遮罩
                    if isHovering {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.4))

                        Button {
                            onPlay()
                        } label: {
                            Image(systemName: video.isImageSet ? "photo.stack" : "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 图集角标
                if video.isImageSet {
                    HStack(spacing: 2) {
                        Image(systemName: "photo.stack.fill")
                            .font(.caption2)
                        Text("\(video.imageCount)")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .cornerRadius(4)
                    .padding(4)
                }

                // 擦边等级角标
                if let analysis = video.analysis, analysis.sexyLevel > 0 {
                    SexyLevelBadge(level: analysis.sexyLevel)
                        .padding(4)
                        .offset(y: video.isImageSet ? 28 : 0)
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                onPlay()
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(video.filename)
                    .font(.caption)
                    .lineLimit(1)

                // 作者名称 - 可点击
                Text(video.folder)
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .onTapGesture {
                        onAuthorTap?(video.folder)
                    }

                // 分析标签
                if let analysis = video.analysis {
                    HStack(spacing: 4) {
                        if !analysis.category.isEmpty {
                            Text(analysis.category)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(3)
                        }
                        Spacer()
                        Text(video.formattedSize)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // 显示前3个标签 - 可点击
                    if !analysis.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(analysis.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(2)
                                    .onTapGesture {
                                        onTagTap?(tag)
                                    }
                            }
                            if analysis.tags.count > 3 {
                                Text("+\(analysis.tags.count - 3)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    HStack {
                        Text(video.formattedSize)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .contextMenu {
            Button("播放") {
                onPlay()
            }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.selectFile(video.path, inFileViewerRootedAtPath: "")
            }
            Divider()
            Button("删除", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - 视频列表项

struct LocalVideoListItem: View {
    let video: LocalVideo
    let onPlay: () -> Void
    let onDelete: () -> Void
    var onAuthorTap: ((String) -> Void)?
    var onTagTap: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // 缩略图
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 60)

                    VideoThumbnailView(
                        videoPath: video.path,
                        coverPath: video.coverPath,
                        cornerRadius: 6
                    )
                    .frame(width: 80, height: 60)
                }

                // 擦边等级角标
                if let analysis = video.analysis, analysis.sexyLevel > 0 {
                    SexyLevelBadge(level: analysis.sexyLevel, compact: true)
                        .padding(2)
                }
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(video.filename)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    // 作者名称 - 可点击
                    Text(video.folder)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .onTapGesture {
                            onAuthorTap?(video.folder)
                        }

                    Text(video.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(video.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 分类
                    if let analysis = video.analysis, !analysis.category.isEmpty {
                        Text(analysis.category)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                // 标签 - 可点击
                if let analysis = video.analysis, !analysis.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(analysis.tags.prefix(5), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(3)
                                .onTapGesture {
                                    onTagTap?(tag)
                                }
                        }
                        if analysis.tags.count > 5 {
                            Text("+\(analysis.tags.count - 5)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 8) {
                Button {
                    onPlay()
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.selectFile(video.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .onTapGesture(count: 2) {
            onPlay()
        }
        .contextMenu {
            Button("播放") {
                onPlay()
            }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.selectFile(video.path, inFileViewerRootedAtPath: "")
            }
            Divider()
            Button("删除", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - 视频播放器覆盖层

struct VideoPlayerOverlay: View {
    let video: LocalVideo
    let player: AVPlayer
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            HStack(spacing: 16) {
                // 左侧：视频播放器
                VStack(spacing: 0) {
                    // 顶部工具栏
                    HStack {
                        Text(video.filename)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()

                    Spacer()

                    // 视频播放器
                    VideoPlayer(player: player)
                        .frame(maxWidth: 400, maxHeight: 700)
                        .cornerRadius(12)

                    Spacer()
                }

                // 右侧：视频详情面板
                if video.analysis != nil {
                    videoDetailPanel
                }
            }
            .padding()
        }
    }

    // 视频详情面板
    @ViewBuilder
    private var videoDetailPanel: some View {
        if let analysis = video.analysis {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 标题
                    Text("视频分析")
                        .font(.headline)
                        .foregroundColor(.white)

                    Divider().background(Color.white.opacity(0.3))

                    // 分类和擦边等级
                    HStack {
                        if !analysis.category.isEmpty {
                            Text(analysis.category)
                                .font(.subheadline)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }

                        Spacer()

                        SexyLevelBadge(level: analysis.sexyLevel)
                    }

                    // 摘要
                    if !analysis.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("摘要")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Text(analysis.summary)
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                    }

                    // 场景
                    if !analysis.scene.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("场景")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Text(analysis.scene)
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                    }

                    // 全部标签
                    if !analysis.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("标签 (\(analysis.tags.count))")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))

                            FlowLayout(spacing: 6) {
                                ForEach(analysis.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.2))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .frame(width: 280)
            .background(Color.black.opacity(0.5))
            .cornerRadius(12)
        }
    }
}

// MARK: - 擦边等级角标

struct SexyLevelBadge: View {
    let level: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(compact ? .system(size: 8) : .caption2)
            if !compact {
                Text("\(level)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 3 : 4)
        .padding(.vertical, compact ? 2 : 2)
        .background(levelColor)
        .cornerRadius(compact ? 3 : 4)
    }

    private var levelColor: Color {
        switch level {
        case 1...2: return .green
        case 3...4: return .yellow.opacity(0.9)
        case 5...6: return .orange
        case 7...8: return .red
        case 9...10: return .purple
        default: return .gray
        }
    }
}

// MARK: - 标签过滤芯片

struct TagFilterChip: View {
    let tag: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Text(tag)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 视频缩略图视图

struct VideoThumbnailView: View {
    let videoPath: String
    let coverPath: String?
    let cornerRadius: CGFloat

    @State private var thumbnail: NSImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let coverPath = coverPath {
                AsyncImage(url: URL(fileURLWithPath: coverPath)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        fallbackThumbnail
                    case .empty:
                        ProgressView()
                    @unknown default:
                        fallbackThumbnail
                    }
                }
            } else {
                fallbackThumbnail
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var fallbackThumbnail: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if isLoading {
            ProgressView()
        } else {
            Image(systemName: "video")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .onAppear {
                    generateThumbnail()
                }
        }
    }

    private func generateThumbnail() {
        guard !isLoading else { return }
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: videoPath)
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)

            // 取第3秒的画面
            let time = CMTime(seconds: 3, preferredTimescale: 600)

            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                DispatchQueue.main.async {
                    self.thumbnail = nsImage
                    self.isLoading = false
                }
            } catch {
                // 如果3秒失败，尝试0秒
                do {
                    let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    DispatchQueue.main.async {
                        self.thumbnail = nsImage
                        self.isLoading = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
            }
        }
    }
}

// MARK: - 图集查看器

struct ImageSetViewer: View {
    let imageSet: LocalVideo
    let onClose: () -> Void

    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack {
            // 背景
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            VStack(spacing: 0) {
                // 顶部栏
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(imageSet.filename)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("\(currentIndex + 1) / \(imageSet.imageCount) 张")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    Button {
                        if let path = imageSet.imagePaths[safe: currentIndex] {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    } label: {
                        Image(systemName: "folder")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help("在访达中显示")

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding()

                // 图片显示区域
                ZStack {
                    if let imagePath = imageSet.imagePaths[safe: currentIndex],
                       let nsImage = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("无法加载图片")
                            .foregroundColor(.white)
                    }

                    // 左右切换按钮
                    HStack {
                        Button {
                            if currentIndex > 0 {
                                currentIndex -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(currentIndex > 0 ? 0.8 : 0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex == 0)
                        .keyboardShortcut(.leftArrow, modifiers: [])

                        Spacer()

                        Button {
                            if currentIndex < imageSet.imageCount - 1 {
                                currentIndex += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(currentIndex < imageSet.imageCount - 1 ? 0.8 : 0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex >= imageSet.imageCount - 1)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    }
                    .padding(.horizontal, 20)
                }

                // 底部缩略图栏
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(imageSet.imagePaths.enumerated()), id: \.offset) { index, path in
                                if let nsImage = NSImage(contentsOfFile: path) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(currentIndex == index ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                        .opacity(currentIndex == index ? 1 : 0.6)
                                        .onTapGesture {
                                            currentIndex = index
                                        }
                                        .id(index)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 100)
                    .onChange(of: currentIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

// 安全数组访问扩展
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    VideoGalleryView()
        .environmentObject(DatabaseService.shared)
}
