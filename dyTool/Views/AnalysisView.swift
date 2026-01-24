//
//  AnalysisView.swift
//  dyTool
//
//  视频内容分析页面
//

import SwiftUI

struct AnalysisView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @StateObject private var analysisService = AnalysisService.shared

    // 配置
    @State private var provider: AnalysisConfig.AIProvider = .gemini
    @State private var apiKey: String = ""
    @State private var endpoint: String = ""
    @State private var model: String = ""
    @State private var frameCount: Int = 4
    @State private var concurrency: Int = 1
    @State private var requestDelay: Double = 2.0
    @State private var rpm: Int = 0  // 每分钟请求数限制
    @State private var skipAnalyzed: Bool = true
    @State private var selectedAuthor: String = ""  // 按作者筛选

    // 状态
    @State private var itemsToAnalyze: [AnalysisItem] = []
    @State private var analysisResults: [VideoAnalysis] = []
    @State private var selectedTab: AnalysisTab = .config
    @State private var availableAuthors: [String] = []  // 可选作者列表

    enum AnalysisTab {
        case config, results
    }

    var body: some View {
        HSplitView {
            // 左侧配置面板
            configPanel
                .frame(minWidth: 280, maxWidth: 350)

            // 右侧内容
            VStack(spacing: 0) {
                // 标签页切换
                Picker("", selection: $selectedTab) {
                    Text("分析日志").tag(AnalysisTab.config)
                    Text("分析结果 (\(analysisResults.count))").tag(AnalysisTab.results)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // 内容
                switch selectedTab {
                case .config:
                    logView
                case .results:
                    resultsView
                }
            }
        }
        .onAppear {
            loadSettings()
            loadResults()
            scanVideos()
        }
    }

    // MARK: - 配置面板

    private var configPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题
                Text("视频内容分析")
                    .font(.headline)

                Divider()

                // API 配置
                GroupBox("API 配置") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("提供商", selection: $provider) {
                            ForEach(AnalysisConfig.AIProvider.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .onChange(of: provider) { _, newValue in
                            saveProvider(newValue)
                            loadApiKey()
                            loadEndpoint()
                            loadModel()
                        }

                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: apiKey) { _, newValue in
                                saveApiKey(newValue)
                            }

                        TextField("API 端点（可选）", text: $endpoint)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: endpoint) { _, newValue in
                                saveEndpoint(newValue)
                            }

                        Text("端点留空使用默认：\(provider.defaultEndpoint)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("模型名称（可选）", text: $model)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model) { _, newValue in
                                saveModel(newValue)
                            }

                        Text("模型留空使用默认：\(provider.defaultModel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // 分析配置
                GroupBox("分析配置") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("抽帧数量")
                            Spacer()
                            TextField("", value: $frameCount, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("帧")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("并发数")
                            Spacer()
                            TextField("", value: $concurrency, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("个")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("请求间隔")
                            Spacer()
                            TextField("", value: $requestDelay, format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("秒")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("RPM 限制")
                            Spacer()
                            TextField("", value: $rpm, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("次/分")
                                .foregroundColor(.secondary)
                        }

                        Text("RPM=0 表示不限制，优先使用 RPM，会自动计算请求间隔")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("跳过已分析视频", isOn: $skipAnalyzed)
                            .onChange(of: skipAnalyzed) { _, _ in
                                scanVideos()
                            }
                    }
                    .padding(.vertical, 4)
                }

                // 作者筛选
                GroupBox("作者筛选") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("选择作者", selection: $selectedAuthor) {
                            Text("全部作者").tag("")
                            ForEach(availableAuthors, id: \.self) { author in
                                Text(author).tag(author)
                            }
                        }
                        .onChange(of: selectedAuthor) { _, _ in
                            scanVideos()
                        }

                        if !selectedAuthor.isEmpty {
                            Text("仅分析 \(selectedAuthor) 的视频")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 待分析列表
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            let videoCount = itemsToAnalyze.filter { if case .video = $0 { return true } else { return false } }.count
                            let imageSetCount = itemsToAnalyze.count - videoCount
                            Text("待分析 (视频:\(videoCount) 图集:\(imageSetCount))")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Button("刷新") {
                                scanVideos()
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)

                            Spacer()

                            Text(databaseService.settings.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if itemsToAnalyze.isEmpty {
                            Text("没有找到可分析的内容")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(itemsToAnalyze.prefix(50), id: \.id) { item in
                                        HStack(spacing: 4) {
                                            Image(systemName: item.isImageSet ? "photo.stack" : "video")
                                                .font(.caption2)
                                                .foregroundColor(item.isImageSet ? .purple : .blue)
                                            Text(item.displayName)
                                                .font(.caption)
                                                .lineLimit(1)
                                        }
                                    }
                                    if itemsToAnalyze.count > 50 {
                                        Text("... 还有 \(itemsToAnalyze.count - 50) 个项目")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(maxHeight: 150)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 操作按钮
                if analysisService.isAnalyzing {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(analysisService.progress.current), total: Double(max(1, analysisService.progress.total))) {
                            Text("\(analysisService.progress.current)/\(analysisService.progress.total)")
                        }

                        Text(analysisService.currentVideo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Button("停止分析") {
                            analysisService.stopAnalysis()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                } else {
                    Button {
                        startAnalysis()
                    } label: {
                        Label("开始分析", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty || itemsToAnalyze.isEmpty)
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - 日志视图

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(analysisService.logs.enumerated()), id: \.offset) { index, log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(logColor(for: log))
                            .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: analysisService.logs.count) { _, _ in
                if let lastIndex = analysisService.logs.indices.last {
                    withAnimation {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func logColor(for log: String) -> Color {
        if log.contains("[错误]") { return .red }
        if log.contains("[完成]") { return .green }
        if log.contains("[信息]") { return .blue }
        return .primary
    }

    // MARK: - 结果视图

    private var resultsView: some View {
        List(analysisResults) { analysis in
            AnalysisResultRow(analysis: analysis)
        }
        .listStyle(.inset)
    }

    // MARK: - 方法

    private func loadSettings() {
        // 加载 provider
        if let savedProvider = databaseService.getAnalysisSetting(key: "provider"),
           let p = AnalysisConfig.AIProvider(rawValue: savedProvider) {
            provider = p
        }
        // 加载 API Key、端点和模型
        loadApiKey()
        loadEndpoint()
        loadModel()
    }

    private func loadApiKey() {
        apiKey = databaseService.getAnalysisApiKey(provider: provider.rawValue)
    }

    private func saveApiKey(_ key: String) {
        databaseService.setAnalysisApiKey(provider: provider.rawValue, key: key)
    }

    private func loadEndpoint() {
        endpoint = databaseService.getAnalysisSetting(key: "endpoint_\(provider.rawValue)") ?? ""
    }

    private func saveEndpoint(_ value: String) {
        databaseService.setAnalysisSetting(key: "endpoint_\(provider.rawValue)", value: value)
    }

    private func loadModel() {
        model = databaseService.getAnalysisSetting(key: "model_\(provider.rawValue)") ?? ""
    }

    private func saveModel(_ value: String) {
        databaseService.setAnalysisSetting(key: "model_\(provider.rawValue)", value: value)
    }

    private func saveProvider(_ p: AnalysisConfig.AIProvider) {
        databaseService.setAnalysisSetting(key: "provider", value: p.rawValue)
    }

    private func loadResults() {
        analysisResults = databaseService.getAllAnalysis()
    }

    private func scanVideos() {
        let downloadPath = databaseService.settings.path
        let downloadDir = URL(fileURLWithPath: downloadPath)

        guard FileManager.default.fileExists(atPath: downloadDir.path) else {
            itemsToAnalyze = []
            availableAuthors = []
            return
        }

        var items: [AnalysisItem] = []
        var authors = Set<String>()
        let videoExtensions = ["mp4", "mov", "webm", "m4v"]
        let imageExtensions = ["webp", "jpg", "jpeg", "png"]
        let knownModes = ["post", "like", "collection", "collects", "mix", "music"]

        // 获取已分析的 awemeId
        let analyzedIds: Set<String> = skipAnalyzed ? databaseService.getAnalyzedAwemeIds() : []

        // f2 目录结构: Downloads/douyin/{mode}/{author}/
        // 遍历平台目录（douyin）
        guard let platformDirs = try? FileManager.default.contentsOfDirectory(
            at: downloadDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            itemsToAnalyze = []
            availableAuthors = []
            return
        }

        for platformDir in platformDirs {
            guard (try? platformDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            // 跳过非平台目录（如 logs）
            let platformName = platformDir.lastPathComponent
            guard platformName == "douyin" else { continue }

            // 遍历模式目录（post, like 等）
            guard let modeDirs = try? FileManager.default.contentsOfDirectory(
                at: platformDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for modeDir in modeDirs {
                guard (try? modeDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let modeName = modeDir.lastPathComponent
                guard knownModes.contains(modeName) else { continue }

                // 遍历作者目录
                guard let authorDirs = try? FileManager.default.contentsOfDirectory(
                    at: modeDir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for authorDir in authorDirs {
                    guard (try? authorDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

                    let authorName = authorDir.lastPathComponent
                    authors.insert(authorName)

                    // 如果选择了作者过滤
                    guard selectedAuthor.isEmpty || authorName == selectedAuthor else { continue }

                    // 扫描该作者目录下的内容
                    guard let contents = try? FileManager.default.contentsOfDirectory(
                        at: authorDir,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    // 1. 识别图集
                    var imageGroups: [String: [String]] = [:]
                    for file in contents {
                        let ext = file.pathExtension.lowercased()
                        guard imageExtensions.contains(ext) else { continue }

                        let filename = file.deletingPathExtension().lastPathComponent
                        if filename.hasSuffix("_cover") { continue }

                        if let range = filename.range(of: "_image_\\d+$", options: .regularExpression) {
                            let prefix = String(filename[..<range.lowerBound])
                            if imageGroups[prefix] == nil {
                                imageGroups[prefix] = []
                            }
                            imageGroups[prefix]?.append(file.path)
                        }
                    }

                    // 添加图集（跳过已分析）
                    for (prefix, paths) in imageGroups {
                        if skipAnalyzed && analyzedIds.contains(prefix) { continue }
                        let sortedPaths = paths.sorted()
                        items.append(.imageSet(prefix: prefix, paths: sortedPaths))
                    }

                    // 2. 识别视频
                    let imageSetPrefixes = Set(imageGroups.keys)
                    for file in contents {
                        let ext = file.pathExtension.lowercased()
                        guard videoExtensions.contains(ext) else { continue }

                        let filename = file.deletingPathExtension().lastPathComponent
                        if skipAnalyzed && analyzedIds.contains(filename) { continue }
                        if imageSetPrefixes.contains(filename) { continue }

                        items.append(.video(path: file.path))
                    }
                }
            }
        }

        availableAuthors = Array(authors).sorted()
        itemsToAnalyze = items.sorted { $0.displayName < $1.displayName }
    }

    private func startAnalysis() {
        // 如果设置了 RPM，自动计算请求间隔
        var effectiveDelay = requestDelay
        if rpm > 0 {
            effectiveDelay = 60.0 / Double(rpm)
        }

        let config = AnalysisConfig(
            provider: provider,
            apiKey: apiKey,
            endpoint: endpoint,
            model: model,
            frameCount: frameCount,
            concurrency: concurrency,
            requestDelay: effectiveDelay,
            rpm: rpm,
            skipAnalyzed: skipAnalyzed
        )

        analysisService.analyzeItems(
            items: itemsToAnalyze,
            config: config,
            onProgress: { current, total, filename in
                // 进度更新已通过 @Published 自动处理
            },
            completion: { success, fail in
                loadResults()
                scanVideos()
            }
        )
    }
}

// MARK: - 分析结果行

struct AnalysisResultRow: View {
    let analysis: VideoAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack {
                // 图集/视频图标
                Image(systemName: analysis.isImageSet ? "photo.stack" : "video")
                    .font(.caption)
                    .foregroundColor(analysis.isImageSet ? .purple : .blue)

                Text(analysis.awemeId)
                    .font(.headline)
                    .lineLimit(1)

                // 图集数量
                if analysis.isImageSet && analysis.imageCount > 0 {
                    Text("(\(analysis.imageCount)张)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 分类标签
                if !analysis.category.isEmpty {
                    Text(analysis.category)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }

                // 擦边等级
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(sexyLevelColor)
                    Text("\(analysis.sexyLevel)")
                        .font(.caption)
                }
            }

            // 摘要
            if !analysis.summary.isEmpty {
                Text(analysis.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 标签
            if !analysis.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(analysis.tags.prefix(10), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }

            // 场景
            if !analysis.scene.isEmpty {
                Text("场景: \(analysis.scene)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var sexyLevelColor: Color {
        switch analysis.sexyLevel {
        case 1...2: return .green
        case 3...4: return .yellow
        case 5...6: return .orange
        case 7...8: return .red
        case 9...10: return .purple
        default: return .gray
        }
    }
}

// MARK: - 流式布局

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

#Preview {
    AnalysisView()
        .environmentObject(DatabaseService.shared)
}
