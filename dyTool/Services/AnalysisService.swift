//
//  AnalysisService.swift
//  dyTool
//
//  视频内容分析服务 - 使用 Gemini/Grok API 分析视频
//

import Foundation
import AVFoundation
import AppKit
import Combine

class AnalysisService: ObservableObject {
    static let shared = AnalysisService()

    @Published var isAnalyzing = false
    @Published var currentVideo: String = ""
    @Published var progress: (current: Int, total: Int) = (0, 0)
    @Published var logs: [String] = []

    private var cancelFlag = false

    private init() {}

    // MARK: - 分析提示词

    private let analysisPrompt = """
你是专业的视频内容分析助手。分析视频帧截图，输出标准化JSON。

## 标签规则（严格遵守）：
1. 只输出标签词本身，禁止带前缀（错误：「丝袜类: 黑丝」正确：「黑丝」）
2. 必须使用纯中文，禁止中英混用（错误：「热 pants」正确：「热裤」）
3. 标签内禁止有空格
4. 从下方标签库中选择，可组合多个

## 标签库：

【袜子/丝袜】颜色+厚度+长度+风格 组合
- 颜色：黑丝、白丝、肉丝、灰丝、彩丝、渐变丝
- 厚度：超薄、薄款、中厚、厚款、加绒
- 长度：短袜、中筒袜、过膝袜、大腿袜、连裤袜、九分袜
- 款式：堆堆袜、网袜、渔网袜、蕾丝袜、提花袜、条纹袜、波点袜
- 特征：脚尖透明、加档、T档、无缝

【腿部特征】
- 腿型：长腿、美腿、细腿、直腿、腿部线条
- 动作：抬腿、交叉腿、盘腿、侧躺、跪姿

【足部特征】
- 状态：裸足、半裸足、脚尖
- 细节：脚踝、足弓、脚背、脚趾
- 动作：踮脚、勾脚、足部特写

【鞋子】
- 类型：高跟鞋、细跟鞋、粗跟鞋、平底鞋、凉鞋、拖鞋、靴子、短靴、长靴、运动鞋、帆布鞋、玛丽珍鞋、乐福鞋
- 特征：尖头、圆头、鱼嘴、露趾、绑带

【下装】
- 裙子：短裙、超短裙、迷你裙、百褶裙、包臀裙、A字裙、长裙、开叉裙
- 裤子：热裤、牛仔裤、紧身裤、阔腿裤、打底裤、短裤、皮裤、休闲裤

【上装】
- 款式：吊带、抹胸、露脐装、衬衫、T恤、背心、外套、毛衣、卫衣、针织衫
- 领口：V领、深V、一字肩、露肩、低胸

【整体服装】
JK制服、水手服、旗袍、连衣裙、汉服、洛丽塔、女仆装、护士装、兔女郎、猫娘装、泳装、比基尼、睡衣、居家服

【风格】
甜美风、性感风、清纯风、御姐风、萝莉风、可爱风、冷艳风、日系、韩系

【内容类型】
舞蹈、宅舞、韩舞、热舞、穿搭展示、试穿、换装、Cosplay、写真、自拍、日常

## 擦边等级评判标准（sexy_level 1-10）：

综合以下维度评分：

**A. 穿搭暴露度（基础分）**
- 1-2分：正常日常穿搭，无暴露
- 3-4分：轻微暴露（短裙、吊带、露脐）
- 5-6分：中度暴露（超短裙、深V、热裤）
- 7-8分：较多暴露（比基尼、抹胸、大面积露肤）
- 9-10分：极度暴露（近乎裸露、仅遮挡关键部位）

**B. 特定穿搭加分（重要）**
- 肉丝/裸足/堆堆袜：+2~3分
- 黑丝/白丝+高跟鞋：+1~2分
- 超薄丝袜/脚尖透明：+1~2分
- 网袜/渔网袜：+1分
- 足部特写/脚趾可见：+1~2分

**C. 身体/镜头暴露度**
- 加分项：特写镜头对准胸部/臀部/腿部、低角度拍摄、身体曲线明显
- 加分项：大腿根部、臀部轮廓、胸部轮廓清晰可见

**D. 表情/神态**
- 加分项：媚眼、咬唇、舔唇、挑逗表情、娇喘姿态
- 加分项：眼神勾人、嘟嘴卖萌带暗示

**E. 动作/姿势诱惑度**
- 加分项：撩衣、弯腰、翘臀、M字腿、趴姿露沟
- 加分项：抚摸身体、挑逗性舞蹈动作、踮脚展示腿部

**评分原则**：基础分从穿搭暴露度开始，叠加B/C/D/E维度加分，上限10分。
注意：肉丝堆堆袜+裸足组合应至少6-7分起步。

## 输出字段：
- tags: 标签数组（5-15个，必须纯中文无空格）
- category: 主分类（舞蹈/穿搭展示/Cosplay/写真/日常/教程）
- summary: 一句话描述（15字内）
- scene: 场景（卧室/客厅/户外/舞房/其他）
- sexy_level: 擦边等级1-10（综合上述四维度评分）

## 输出格式（严格JSON，无其他文字）：
{"tags":["标签1","标签2"],"category":"分类","summary":"描述","scene":"场景","sexy_level":5}
"""

    // MARK: - 抽取视频帧 (使用 AVFoundation)

    private func extractFrames(videoPath: String, frameCount: Int = 4) async throws -> [URL] {
        let videoURL = URL(fileURLWithPath: videoPath)
        let asset = AVURLAsset(url: videoURL)

        // 获取视频时长
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw AnalysisError.frameExtractionFailed
        }

        // 创建临时目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 创建图像生成器
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1280, height: 1280) // 限制最大尺寸

        // 计算抽帧时间点 (均匀分布)
        let interval = durationSeconds / Double(frameCount + 1)
        var framePaths: [URL] = []

        for i in 0..<frameCount {
            let timestamp = interval * Double(i + 1)
            let time = CMTime(seconds: timestamp, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: time)

                // 转换为 NSImage 并保存为 JPEG
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                let outputPath = tempDir.appendingPathComponent("frame_\(String(format: "%02d", i)).jpg")

                if let tiffData = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    try jpegData.write(to: outputPath)
                    framePaths.append(outputPath)
                }
            } catch {
                print("[抽帧] 第 \(i) 帧提取失败: \(error)")
                // 继续处理其他帧
            }
        }

        return framePaths
    }

    // MARK: - 调用 Gemini API

    private func callGeminiAPI(apiKey: String, endpoint: String, model customModel: String, imagePaths: [URL]) async throws -> String {
        let model = customModel.isEmpty ? "gemini-2.0-flash" : customModel
        let baseUrl = endpoint.isEmpty ? "https://generativelanguage.googleapis.com" : endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(baseUrl)/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        // 构建请求体
        var parts: [[String: Any]] = [["text": analysisPrompt]]

        for imagePath in imagePaths {
            let imageData = try Data(contentsOf: imagePath)
            let base64 = imageData.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64
                ]
            ])
        }

        let payload: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "temperature": 0.2,
                "topP": 0.8,
                "maxOutputTokens": 4096
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.networkError("无效响应")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.apiError(httpResponse.statusCode, errorBody)
        }

        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]],
              let text = responseParts.first?["text"] as? String else {
            throw AnalysisError.parseError("无法解析 Gemini 响应")
        }

        return text
    }

    // MARK: - 调用 Grok API

    private func callGrokAPI(apiKey: String, endpoint: String, model customModel: String, imagePaths: [URL]) async throws -> String {
        let model = customModel.isEmpty ? "grok-2-vision-1212" : customModel
        let baseUrl = endpoint.isEmpty ? "https://api.x.ai" : endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(baseUrl)/v1/chat/completions")!
        let isHTTP = url.scheme == "http"

        // 调试日志
        addLog("[调试] URL: \(url), HTTP: \(isHTTP)")
        addLog("[调试] 模型: \(model)")
        addLog("[调试] API Key 长度: \(apiKey.count), 前缀: \(String(apiKey.prefix(5)))")

        // 构建消息内容
        var content: [[String: Any]] = [["type": "text", "text": analysisPrompt]]

        for imagePath in imagePaths {
            let imageData = try Data(contentsOf: imagePath)
            let base64 = imageData.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ])
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]],
            "temperature": 0.2,
            "max_tokens": 4096
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        // HTTP 请求需要用 curl，因为 URLSession 会剥离 Authorization 头
        if isHTTP {
            return try await callAPIWithCurl(url: url, apiKey: apiKey, body: bodyData)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.networkError("无效响应")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.apiError(httpResponse.statusCode, errorBody)
        }

        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AnalysisError.parseError("无法解析 Grok 响应")
        }

        return text
    }

    // MARK: - 使用 curl 调用 API（绕过 URLSession 的 HTTP 限制）

    private func callAPIWithCurl(url: URL, apiKey: String, body: Data) async throws -> String {
        // 写入临时文件
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try body.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-s", "-X", "POST", url.absoluteString,
            "-H", "Content-Type: application/json",
            "-H", "Authorization: Bearer \(apiKey)",
            "-d", "@\(tempFile.path)",
            "--max-time", "120"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw AnalysisError.networkError("curl 无输出")
        }

        // 检查是否是错误响应
        if let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AnalysisError.apiError(0, message)
        }

        // 解析成功响应
        guard let json = try JSONSerialization.jsonObject(with: outputData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AnalysisError.parseError("无法解析响应: \(output.prefix(200))")
        }

        return text
    }

    // MARK: - 解析分析结果

    private func parseResponse(_ response: String) -> AnalysisResponse? {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // 提取 JSON 块
        if text.contains("```json") {
            if let start = text.range(of: "```json"),
               let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
                text = String(text[start.upperBound..<end.lowerBound])
            }
        } else if text.contains("```") {
            if let start = text.range(of: "```"),
               let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
                text = String(text[start.upperBound..<end.lowerBound])
            }
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果以 [ 开头，可能是数组，尝试提取第一个对象
        if text.hasPrefix("[") {
            if let data = text.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = array.first,
               let firstData = try? JSONSerialization.data(withJSONObject: first) {
                text = String(data: firstData, encoding: .utf8) ?? text
            }
        }

        guard let data = text.data(using: .utf8) else { return nil }

        // 先尝试用 JSONSerialization 解析，更灵活
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return AnalysisResponse(
                tags: json["tags"] as? [String],
                category: json["category"] as? String,
                summary: json["summary"] as? String,
                objects: json["objects"] as? [String],
                scene: json["scene"] as? String,
                sexy_level: json["sexy_level"] as? Int ?? (json["sexyLevel"] as? Int)
            )
        }

        // 备选：用 Codable 解析
        do {
            return try JSONDecoder().decode(AnalysisResponse.self, from: data)
        } catch {
            print("[分析] JSON 解析失败: \(error)")
            print("[分析] 原始响应: \(text.prefix(500))")
            return nil
        }
    }

    // MARK: - 分析单个视频

    func analyzeVideo(
        videoPath: String,
        config: AnalysisConfig
    ) async -> VideoAnalysis {
        let awemeId = URL(fileURLWithPath: videoPath).deletingPathExtension().lastPathComponent
        var result = VideoAnalysis(
            awemeId: awemeId,
            filePath: videoPath,
            tags: [],
            category: "",
            summary: "",
            objects: [],
            scene: "",
            sexyLevel: 0,
            analyzedAt: Date()
        )

        do {
            // 1. 抽取关键帧
            addLog("[帧提取] \(URL(fileURLWithPath: videoPath).lastPathComponent)")
            let framePaths = try await extractFrames(videoPath: videoPath, frameCount: config.frameCount)

            guard !framePaths.isEmpty else {
                result.error = "无法抽取视频帧"
                return result
            }

            addLog("[帧提取] 成功抽取 \(framePaths.count) 帧")

            // 2. 调用 API
            addLog("[API] 调用 \(config.provider.displayName) API...")
            let response: String

            switch config.provider {
            case .gemini:
                response = try await callGeminiAPI(apiKey: config.apiKey, endpoint: config.endpoint, model: config.model, imagePaths: framePaths)
            case .grok:
                response = try await callGrokAPI(apiKey: config.apiKey, endpoint: config.endpoint, model: config.model, imagePaths: framePaths)
            }

            // 3. 解析结果
            guard let parsed = parseResponse(response) else {
                result.error = "API 返回内容无法解析"
                addLog("[错误] 解析失败")
                return result
            }

            result.tags = parsed.tags ?? []
            result.category = parsed.category ?? ""
            result.summary = parsed.summary ?? ""
            result.objects = parsed.objects ?? []
            result.scene = parsed.scene ?? ""
            result.sexyLevel = parsed.sexy_level ?? 0

            addLog("[完成] \(result.category) | 擦边\(result.sexyLevel) | \(result.tags.prefix(3).joined(separator: ", "))")

            // 清理临时文件
            for path in framePaths {
                try? FileManager.default.removeItem(at: path)
            }
            if let tempDir = framePaths.first?.deletingLastPathComponent() {
                try? FileManager.default.removeItem(at: tempDir)
            }

        } catch {
            result.error = error.localizedDescription
            addLog("[错误] \(error.localizedDescription)")
        }

        return result
    }

    // MARK: - 批量分析

    func analyzeVideos(
        videoPaths: [String],
        config: AnalysisConfig,
        onProgress: @escaping (Int, Int, String) -> Void,
        completion: @escaping (Int, Int) -> Void
    ) {
        guard !isAnalyzing else {
            addLog("[错误] 已有分析任务在执行")
            return
        }

        isAnalyzing = true
        cancelFlag = false
        logs.removeAll()

        let total = videoPaths.count
        progress = (0, total)

        addLog("[信息] 开始分析 \(total) 个视频")
        addLog("[信息] API: \(config.provider.displayName)")

        if config.concurrency > 1 {
            addLog("[信息] 并发数: \(config.concurrency)")
            analyzeVideosParallel(videoPaths: videoPaths, config: config, onProgress: onProgress, completion: completion)
        } else {
            addLog("[信息] 串行模式")
            analyzeVideosSerial(videoPaths: videoPaths, config: config, onProgress: onProgress, completion: completion)
        }
    }

    // MARK: - 串行分析

    private func analyzeVideosSerial(
        videoPaths: [String],
        config: AnalysisConfig,
        onProgress: @escaping (Int, Int, String) -> Void,
        completion: @escaping (Int, Int) -> Void
    ) {
        let total = videoPaths.count

        Task {
            var successCount = 0
            var failCount = 0

            for (index, path) in videoPaths.enumerated() {
                guard !cancelFlag else { break }

                let filename = URL(fileURLWithPath: path).lastPathComponent
                await MainActor.run {
                    currentVideo = filename
                    progress = (index + 1, total)
                    onProgress(index + 1, total, filename)
                }

                addLog("[\(index + 1)/\(total)] 分析: \(filename)")

                let result = await analyzeVideo(videoPath: path, config: config)

                // 保存结果
                DatabaseService.shared.saveAnalysis(result)

                if result.error == nil {
                    successCount += 1
                } else {
                    failCount += 1
                }

                // 请求间隔
                if index < total - 1 && !cancelFlag {
                    try? await Task.sleep(nanoseconds: UInt64(config.requestDelay * 1_000_000_000))
                }
            }

            await MainActor.run {
                isAnalyzing = false
                currentVideo = ""
                addLog("[完成] 分析完成 - 成功: \(successCount), 失败: \(failCount)")
                completion(successCount, failCount)
            }
        }
    }

    // MARK: - 并发分析

    private func analyzeVideosParallel(
        videoPaths: [String],
        config: AnalysisConfig,
        onProgress: @escaping (Int, Int, String) -> Void,
        completion: @escaping (Int, Int) -> Void
    ) {
        let total = videoPaths.count
        let counter = AnalysisCounter()

        Task {
            await withTaskGroup(of: (Int, VideoAnalysis).self) { group in
                var runningTasks = 0
                var nextIndex = 0

                // 初始启动 concurrency 个任务
                while nextIndex < videoPaths.count && runningTasks < config.concurrency {
                    let index = nextIndex
                    let path = videoPaths[index]
                    nextIndex += 1
                    runningTasks += 1

                    group.addTask {
                        let result = await self.analyzeVideo(videoPath: path, config: config)
                        return (index, result)
                    }

                    let filename = URL(fileURLWithPath: path).lastPathComponent
                    addLog("[启动] \(filename)")
                }

                // 处理完成的任务并启动新任务
                for await (index, result) in group {
                    guard !cancelFlag else { break }

                    // 保存结果
                    DatabaseService.shared.saveAnalysis(result)

                    // 更新计数
                    let counts = await counter.increment(success: result.error == nil)

                    let filename = URL(fileURLWithPath: videoPaths[index]).lastPathComponent
                    await MainActor.run {
                        progress = (counts.completed, total)
                        onProgress(counts.completed, total, filename)
                    }

                    if result.error == nil {
                        addLog("[完成] \(filename) - \(result.category)")
                    } else {
                        addLog("[失败] \(filename) - \(result.error ?? "未知错误")")
                    }

                    // 启动下一个任务
                    if nextIndex < videoPaths.count && !cancelFlag {
                        let newIndex = nextIndex
                        let newPath = videoPaths[newIndex]
                        nextIndex += 1

                        group.addTask {
                            // 请求间隔
                            try? await Task.sleep(nanoseconds: UInt64(config.requestDelay * 1_000_000_000))
                            let result = await self.analyzeVideo(videoPath: newPath, config: config)
                            return (newIndex, result)
                        }

                        let newFilename = URL(fileURLWithPath: newPath).lastPathComponent
                        addLog("[启动] \(newFilename)")
                    }
                }
            }

            let finalCounts = await counter.getCounts()
            await MainActor.run {
                isAnalyzing = false
                currentVideo = ""
                addLog("[完成] 分析完成 - 成功: \(finalCounts.success), 失败: \(finalCounts.fail)")
                completion(finalCounts.success, finalCounts.fail)
            }
        }
    }

    // MARK: - 停止分析

    func stopAnalysis() {
        cancelFlag = true
        addLog("[信息] 正在停止分析...")
    }

    // MARK: - 日志

    private func addLog(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(message)
            if self.logs.count > 500 {
                self.logs.removeFirst(100)
            }
        }
    }
}

// MARK: - 错误类型

enum AnalysisError: LocalizedError {
    case networkError(String)
    case apiError(Int, String)
    case parseError(String)
    case frameExtractionFailed

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "网络错误: \(msg)"
        case .apiError(let code, let msg): return "API 错误 (\(code)): \(msg)"
        case .parseError(let msg): return "解析错误: \(msg)"
        case .frameExtractionFailed: return "帧提取失败"
        }
    }
}

// MARK: - 线程安全计数器

private actor AnalysisCounter {
    private var completed = 0
    private var success = 0
    private var fail = 0

    func increment(success isSuccess: Bool) -> (completed: Int, success: Int, fail: Int) {
        completed += 1
        if isSuccess {
            success += 1
        } else {
            fail += 1
        }
        return (completed, success, fail)
    }

    func getCounts() -> (completed: Int, success: Int, fail: Int) {
        return (completed, success, fail)
    }
}
