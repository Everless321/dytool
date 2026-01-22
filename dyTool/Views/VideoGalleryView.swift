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

    enum ViewMode {
        case grid, list
    }

    // 过滤后的视频
    private var filteredVideos: [LocalVideo] {
        videos.filter { video in
            // 作者过滤
            if let author = selectedAuthor, !author.isEmpty {
                if video.folder != author {
                    return false
                }
            }

            // 只显示已分析的
            if onlyAnalyzed && video.analysis == nil {
                return false
            }

            // 擦边等级过滤
            if let analysis = video.analysis {
                if analysis.sexyLevel < minSexyLevel || analysis.sexyLevel > maxSexyLevel {
                    return false
                }

                // 标签过滤
                if !selectedTags.isEmpty {
                    let videoTags = Set(analysis.tags)
                    if videoTags.isDisjoint(with: selectedTags) {
                        return false
                    }
                }

                // 分类过滤
                if let category = selectedCategory, !category.isEmpty {
                    if analysis.category != category {
                        return false
                    }
                }
            } else if minSexyLevel > 0 || !selectedTags.isEmpty || selectedCategory != nil {
                // 有过滤条件但没有分析数据，不显示
                return false
            }

            return true
        }
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

                    Text("\(filteredVideos.count) / \(videos.count) 个视频")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

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
                } else if filteredVideos.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(videos.isEmpty ? "暂无视频" : "无匹配视频")
                            .font(.headline)
                        Text(videos.isEmpty ? "下载视频后会在这里显示" : "调整过滤条件查看更多视频")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        switch viewMode {
                        case .grid:
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(filteredVideos) { video in
                                    LocalVideoGridItem(video: video, onPlay: {
                                        playVideo(video)
                                    }, onDelete: {
                                        deleteVideo(video)
                                    })
                                }
                            }
                            .padding()
                        case .list:
                            LazyVStack(spacing: 8) {
                                ForEach(filteredVideos) { video in
                                    LocalVideoListItem(video: video, onPlay: {
                                        playVideo(video)
                                    }, onDelete: {
                                        deleteVideo(video)
                                    })
                                }
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
        }
        .onAppear {
            loadFolders()
            loadVideos()
            loadAnalysisData()
        }
        .onChange(of: selectedFolder) { _, _ in
            loadVideos()
        }
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
                }
            }

            // 标签选择
            if !availableTags.isEmpty {
                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(availableTags, id: \.self) { tag in
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
            if isVideoFile(fileURL) {
                count += 1
            }
        }
        return count
    }

    private func loadVideos() {
        isLoading = true
        videos = []

        DispatchQueue.global(qos: .userInitiated).async {
            let path = databaseService.settings.path
            let downloadDir = URL(fileURLWithPath: path)

            var loadedVideos: [LocalVideo] = []

            let searchDir: URL
            if let folderName = selectedFolder,
               let folder = folders.first(where: { $0.name == folderName }) {
                // 使用文件夹的完整路径
                searchDir = URL(fileURLWithPath: folder.path)
            } else {
                searchDir = downloadDir
            }

            guard FileManager.default.fileExists(atPath: searchDir.path) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            if let enumerator = FileManager.default.enumerator(
                at: searchDir,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if isVideoFile(fileURL) {
                        var video = createLocalVideo(from: fileURL, basePath: downloadDir.path)
                        // 附加分析数据
                        video.analysis = self.analysisMap[video.awemeId]
                        loadedVideos.append(video)
                    }
                }
            }

            // 按修改时间排序
            loadedVideos.sort { $0.createdAt > $1.createdAt }

            DispatchQueue.main.async {
                self.videos = loadedVideos
                self.isLoading = false
            }
        }
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
        return videoExtensions.contains(url.pathExtension.lowercased())
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

        // 收集所有标签和分类
        var tags = Set<String>()
        var categories = Set<String>()
        for analysis in allAnalysis {
            tags.formUnion(analysis.tags)
            if !analysis.category.isEmpty {
                categories.insert(analysis.category)
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
}

// MARK: - 视频网格项

struct LocalVideoGridItem: View {
    let video: LocalVideo
    let onPlay: () -> Void
    let onDelete: () -> Void
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
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 擦边等级角标
                if let analysis = video.analysis, analysis.sexyLevel > 0 {
                    SexyLevelBadge(level: analysis.sexyLevel)
                        .padding(4)
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

                    // 显示前3个标签
                    if !analysis.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(analysis.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(2)
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
                    Text(video.folder)
                        .font(.caption)
                        .foregroundColor(.secondary)

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

                // 标签
                if let analysis = video.analysis, !analysis.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(analysis.tags.prefix(5), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(3)
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

#Preview {
    VideoGalleryView()
        .environmentObject(DatabaseService.shared)
}
