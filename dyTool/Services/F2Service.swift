//
//  F2Service.swift
//  dyTool
//
//  f2 下载服务 - 直接调用 f2-cli 二进制
//

import Foundation
import Combine

class F2Service: ObservableObject {
    static let shared = F2Service()

    @Published var isDownloading = false
    @Published var currentProgress: DownloadProgress?
    @Published var logs: [String] = []

    private var currentProcess: Process?
    private var activeProcesses: [Process] = []
    private var cancelFlag = false
    private let processLock = NSLock()

    private init() {}

    // MARK: - 获取 f2-cli 路径

    private var f2CliPath: URL? {
        // 优先从 Bundle 获取（沙盒环境和打包后都可用）
        if let bundlePath = Bundle.main.url(forResource: "f2-cli", withExtension: nil) {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // 开发时备用路径（非沙盒环境）
        #if DEBUG
        let devPath = URL(fileURLWithPath: "/Users/everless/project/douyintool/dyTool/dyTool/Resources/f2-cli")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath
        }
        #endif

        return nil
    }

    // MARK: - 下载用户作品

    func downloadUser(
        url: String,
        mode: String = "post",
        cookie: String,
        path: String = "Download",
        maxCounts: Int = 0,
        cover: Bool = true,
        interval: String? = nil,
        onProgress: @escaping (String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let f2Path = f2CliPath else {
            completion(.failure(F2Error.binaryNotFound))
            return
        }

        guard !isDownloading else {
            completion(.failure(F2Error.alreadyDownloading))
            return
        }

        isDownloading = true
        cancelFlag = false
        logs.removeAll()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = f2Path

            // 构建参数
            var arguments = [
                "dy",
                "-M", mode,
                "-u", url,
                "-k", cookie,
                "-p", path,
                "-v", cover ? "true" : "false"
            ]

            if maxCounts > 0 {
                arguments.append(contentsOf: ["-o", String(maxCounts)])
            }

            if let interval = interval, !interval.isEmpty {
                arguments.append(contentsOf: ["-i", interval])
            }

            process.arguments = arguments

            // 设置工作目录
            let workDir = URL(fileURLWithPath: path).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: workDir.path) {
                process.currentDirectoryURL = workDir
            }

            // 捕获输出
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            self.currentProcess = process

            do {
                try process.run()

                // 读取输出
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self?.logs.append(line)
                            onProgress(line)
                        }
                    }
                }

                process.waitUntilExit()
                handle.readabilityHandler = nil

                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.currentProcess = nil

                    if self.cancelFlag {
                        completion(.failure(F2Error.cancelled))
                    } else if process.terminationStatus == 0 {
                        completion(.success(()))
                    } else {
                        completion(.failure(F2Error.downloadFailed(Int(process.terminationStatus))))
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.currentProcess = nil
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - 批量下载

    func downloadUsers(
        users: [DouyinUser],
        cookie: String,
        defaultPath: String = "Download",
        parallel: Bool = true,
        maxWorkers: Int = 3,
        onUserStart: @escaping (Int, Int, DouyinUser) -> Void,
        onUserComplete: @escaping (Int, Int, DouyinUser, Bool, String?) -> Void,
        onProgress: @escaping (String) -> Void,
        completion: @escaping (Int, Int) -> Void
    ) {
        guard !isDownloading else {
            onProgress("[错误] 已有下载任务在执行")
            return
        }

        isDownloading = true
        cancelFlag = false

        let total = users.count

        if parallel && maxWorkers > 1 {
            onProgress("[信息] 开始并发下载 \(total) 个用户 (最大并发: \(maxWorkers))")
        } else {
            onProgress("[信息] 开始串行下载 \(total) 个用户")
        }
        onProgress("[信息] 保存路径: \(defaultPath)")

        if parallel && maxWorkers > 1 {
            downloadUsersParallel(
                users: users,
                cookie: cookie,
                defaultPath: defaultPath,
                maxWorkers: maxWorkers,
                onUserStart: onUserStart,
                onUserComplete: onUserComplete,
                onProgress: onProgress,
                completion: completion
            )
        } else {
            downloadUsersSerial(
                users: users,
                cookie: cookie,
                defaultPath: defaultPath,
                onUserStart: onUserStart,
                onUserComplete: onUserComplete,
                onProgress: onProgress,
                completion: completion
            )
        }
    }

    // MARK: - 串行下载

    private func downloadUsersSerial(
        users: [DouyinUser],
        cookie: String,
        defaultPath: String,
        onUserStart: @escaping (Int, Int, DouyinUser) -> Void,
        onUserComplete: @escaping (Int, Int, DouyinUser, Bool, String?) -> Void,
        onProgress: @escaping (String) -> Void,
        completion: @escaping (Int, Int) -> Void
    ) {
        var successCount = 0
        var failCount = 0
        let total = users.count

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for (index, user) in users.enumerated() {
                guard let self = self, !self.cancelFlag else { break }

                DispatchQueue.main.async {
                    onUserStart(index + 1, total, user)
                }

                let semaphore = DispatchSemaphore(value: 0)
                var success = false
                var errorMessage: String? = nil

                self.downloadSingleUser(
                    url: user.url,
                    mode: user.mode,
                    cookie: cookie,
                    path: defaultPath,
                    maxCounts: user.maxCounts,
                    interval: user.interval,
                    onProgress: onProgress
                ) { result in
                    switch result {
                    case .success:
                        success = true
                        successCount += 1
                    case .failure(let error):
                        success = false
                        failCount += 1
                        errorMessage = error.localizedDescription
                    }
                    semaphore.signal()
                }

                semaphore.wait()

                DispatchQueue.main.async {
                    onUserComplete(index + 1, total, user, success, errorMessage)
                }
            }

            DispatchQueue.main.async {
                self?.isDownloading = false
                completion(successCount, failCount)
            }
        }
    }

    // MARK: - 并发下载

    private func downloadUsersParallel(
        users: [DouyinUser],
        cookie: String,
        defaultPath: String,
        maxWorkers: Int,
        onUserStart: @escaping (Int, Int, DouyinUser) -> Void,
        onUserComplete: @escaping (Int, Int, DouyinUser, Bool, String?) -> Void,
        onProgress: @escaping (String) -> Void,
        completion: @escaping (Int, Int) -> Void
    ) {
        let total = users.count
        var successCount = 0
        var failCount = 0
        let countLock = NSLock()

        let semaphore = DispatchSemaphore(value: maxWorkers)
        let group = DispatchGroup()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for (index, user) in users.enumerated() {
                guard let self = self, !self.cancelFlag else { break }

                group.enter()
                semaphore.wait()

                guard !self.cancelFlag else {
                    semaphore.signal()
                    group.leave()
                    break
                }

                DispatchQueue.main.async {
                    onUserStart(index + 1, total, user)
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    self.downloadSingleUser(
                        url: user.url,
                        mode: user.mode,
                        cookie: cookie,
                        path: defaultPath,
                        maxCounts: user.maxCounts,
                        interval: user.interval,
                        onProgress: onProgress
                    ) { result in
                        countLock.lock()
                        var success = false
                        var errorMessage: String? = nil

                        switch result {
                        case .success:
                            success = true
                            successCount += 1
                        case .failure(let error):
                            success = false
                            failCount += 1
                            errorMessage = error.localizedDescription
                        }
                        countLock.unlock()

                        DispatchQueue.main.async {
                            onUserComplete(index + 1, total, user, success, errorMessage)
                        }

                        semaphore.signal()
                        group.leave()
                    }
                }
            }

            group.wait()

            DispatchQueue.main.async {
                self?.isDownloading = false
                self?.activeProcesses.removeAll()
                completion(successCount, failCount)
            }
        }
    }

    private func downloadSingleUser(
        url: String,
        mode: String,
        cookie: String,
        path: String,
        maxCounts: Int,
        interval: String?,
        onProgress: @escaping (String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let f2Path = f2CliPath else {
            onProgress("[错误] 找不到 f2-cli 二进制文件")
            completion(.failure(F2Error.binaryNotFound))
            return
        }

        // 确保下载目录存在
        let downloadDir = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: downloadDir.path) {
            do {
                try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)
                onProgress("[信息] 创建下载目录: \(path)")
            } catch {
                onProgress("[错误] 创建下载目录失败: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
        }

        let process = Process()
        process.executableURL = f2Path

        var arguments = [
            "dy",
            "-M", mode,
            "-u", url,
            "-k", cookie,
            "-p", path,
            "-v", "true"
        ]

        if maxCounts > 0 {
            arguments.append(contentsOf: ["-o", String(maxCounts)])
        }

        if let interval = interval, !interval.isEmpty {
            arguments.append(contentsOf: ["-i", interval])
        }

        process.arguments = arguments
        process.currentDirectoryURL = downloadDir

        onProgress("[命令] f2-cli dy -M \(mode) -u \(url.prefix(50))... -p \(path)")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // 追踪活动进程
        processLock.lock()
        activeProcesses.append(process)
        processLock.unlock()

        do {
            try process.run()

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        onProgress(line)
                    }
                }
            }

            process.waitUntilExit()
            handle.readabilityHandler = nil

            // 移除已完成的进程
            processLock.lock()
            activeProcesses.removeAll { $0 === process }
            processLock.unlock()

            let exitCode = process.terminationStatus
            if exitCode == 0 {
                completion(.success(()))
            } else {
                onProgress("[错误] f2-cli 退出码: \(exitCode)")
                completion(.failure(F2Error.downloadFailed(Int(exitCode))))
            }

        } catch {
            processLock.lock()
            activeProcesses.removeAll { $0 === process }
            processLock.unlock()

            onProgress("[错误] 启动 f2-cli 失败: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }

    // MARK: - 停止下载

    func stopDownload() {
        cancelFlag = true
        currentProcess?.terminate()

        // 终止所有活动进程
        processLock.lock()
        for process in activeProcesses {
            process.terminate()
        }
        activeProcesses.removeAll()
        processLock.unlock()
    }
}

// MARK: - 错误类型

enum F2Error: LocalizedError {
    case binaryNotFound
    case alreadyDownloading
    case cancelled
    case downloadFailed(Int)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "找不到 f2-cli 二进制文件"
        case .alreadyDownloading:
            return "已有下载任务在执行"
        case .cancelled:
            return "下载已取消"
        case .downloadFailed(let code):
            return "下载失败 (错误码: \(code))"
        }
    }
}

// MARK: - 下载进度

struct DownloadProgress {
    var currentUser: Int
    var totalUsers: Int
    var currentUserName: String
    var successCount: Int
    var failCount: Int
}
