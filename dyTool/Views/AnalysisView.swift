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
    @State private var skipAnalyzed: Bool = true

    // 状态
    @State private var videosToAnalyze: [String] = []
    @State private var analysisResults: [VideoAnalysis] = []
    @State private var selectedTab: AnalysisTab = .config

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

                        Toggle("跳过已分析视频", isOn: $skipAnalyzed)
                            .onChange(of: skipAnalyzed) { _, _ in
                                scanVideos()
                            }
                    }
                    .padding(.vertical, 4)
                }

                // 视频列表
                GroupBox("待分析视频 (\(videosToAnalyze.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("刷新列表") {
                                scanVideos()
                            }

                            Spacer()

                            Text(databaseService.settings.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if videosToAnalyze.isEmpty {
                            Text("没有找到视频文件")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(videosToAnalyze.prefix(50), id: \.self) { path in
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    if videosToAnalyze.count > 50 {
                                        Text("... 还有 \(videosToAnalyze.count - 50) 个视频")
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
                    .disabled(apiKey.isEmpty || videosToAnalyze.isEmpty)
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
            videosToAnalyze = []
            return
        }

        var videos: [String] = []
        let extensions = ["mp4", "mov", "webm", "m4v"]

        if let enumerator = FileManager.default.enumerator(
            at: downloadDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if extensions.contains(fileURL.pathExtension.lowercased()) {
                    videos.append(fileURL.path)
                }
            }
        }

        // 过滤已分析的
        if skipAnalyzed {
            let analyzed = databaseService.getAnalyzedAwemeIds()
            videos = videos.filter { path in
                let awemeId = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                return !analyzed.contains(awemeId)
            }
        }

        videosToAnalyze = videos.sorted()
    }

    private func startAnalysis() {
        let config = AnalysisConfig(
            provider: provider,
            apiKey: apiKey,
            endpoint: endpoint,
            model: model,
            frameCount: frameCount,
            concurrency: concurrency,
            requestDelay: requestDelay,
            skipAnalyzed: skipAnalyzed
        )

        analysisService.analyzeVideos(
            videoPaths: videosToAnalyze,
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
                Text(analysis.awemeId)
                    .font(.headline)
                    .lineLimit(1)

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
