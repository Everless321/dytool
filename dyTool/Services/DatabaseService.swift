//
//  DatabaseService.swift
//  dyTool
//
//  本地 SQLite 数据库服务
//

import Foundation
import SQLite3
import Combine

// SQLite TRANSIENT destructor - tells SQLite to copy the string
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class DatabaseService: ObservableObject {
    static let shared = DatabaseService()

    // 应用数据目录
    static var appSupportDirectory: URL {
        let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return path.appendingPathComponent("dyTool", isDirectory: true)
    }

    // 默认下载目录
    static var defaultDownloadDirectory: URL {
        return appSupportDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    private var db: OpaquePointer?
    private let dbPath: String

    @Published var users: [DouyinUser] = []
    @Published var settings: AppSettings = .default

    private init() {
        let appFolder = DatabaseService.appSupportDirectory
        let downloadFolder = DatabaseService.defaultDownloadDirectory

        // 创建应用目录和下载目录
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)

        dbPath = appFolder.appendingPathComponent("douyintool.db").path
        openDatabase()
        createTables()
        loadData()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - 数据库操作

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("无法打开数据库: \(dbPath)")
        }
    }

    private func createTables() {
        let createUsersTable = """
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                url TEXT NOT NULL UNIQUE,
                mode TEXT DEFAULT 'post',
                max_counts INTEGER DEFAULT 0,
                interval TEXT,
                nickname TEXT,
                path TEXT,
                aweme_count INTEGER,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """

        let createSettingsTable = """
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
        """

        executeSQL(createUsersTable)
        executeSQL(createSettingsTable)

        // 迁移：添加 aweme_count 列（如果不存在）
        addColumnIfNotExists(table: "users", column: "aweme_count", type: "INTEGER")

        // 初始化默认设置
        initDefaultSettings()
    }

    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func addColumnIfNotExists(table: String, column: String, type: String) {
        var statement: OpaquePointer?
        let pragma = "PRAGMA table_info(\(table))"

        if sqlite3_prepare_v2(db, pragma, -1, &statement, nil) == SQLITE_OK {
            var columnExists = false
            while sqlite3_step(statement) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(statement, 1) {
                    let name = String(cString: namePtr)
                    if name == column {
                        columnExists = true
                        break
                    }
                }
            }
            sqlite3_finalize(statement)

            if !columnExists {
                executeSQL("ALTER TABLE \(table) ADD COLUMN \(column) \(type)")
            }
        } else {
            sqlite3_finalize(statement)
        }
    }

    private func initDefaultSettings() {
        let defaultPath = DatabaseService.defaultDownloadDirectory.path
        let defaults: [(String, String)] = [
            ("parallel", "true"),
            ("max_workers", "3"),
            ("on_error", "skip"),
            ("mode", "post"),
            ("max_counts", "10"),
            ("path", defaultPath),
            ("cover", "true"),
            ("embed_cover", "true"),
            ("cookie", "")
        ]

        for (key, value) in defaults {
            let sql = "INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, value, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    private func loadData() {
        users = getAllUsers()
        settings = getSettings()
    }

    // MARK: - 用户管理

    func getAllUsers() -> [DouyinUser] {
        var result: [DouyinUser] = []
        // 过滤掉空记录
        let sql = "SELECT id, url, mode, max_counts, interval, nickname, aweme_count FROM users WHERE length(id) > 0 AND length(url) > 0 ORDER BY created_at DESC"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let url = String(cString: sqlite3_column_text(statement, 1))
                // mode 可能为空，默认为 "post"
                let modePtr = sqlite3_column_text(statement, 2)
                let mode = modePtr != nil ? String(cString: modePtr!) : "post"
                let finalMode = mode.isEmpty ? "post" : mode
                let maxCounts = Int(sqlite3_column_int(statement, 3))
                let interval = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                let nickname = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let awemeCount: Int? = sqlite3_column_type(statement, 6) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 6)) : nil

                let user = DouyinUser(
                    id: id,
                    url: url,
                    mode: finalMode,
                    maxCounts: maxCounts,
                    interval: interval,
                    nickname: nickname,
                    awemeCount: awemeCount
                )
                result.append(user)
            }
        }
        sqlite3_finalize(statement)
        return result
    }

    func addUser(url: String, mode: String = "post", maxCounts: Int = 0, nickname: String? = nil, awemeCount: Int? = nil) -> DouyinUser? {
        // 验证 URL 不为空
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else {
            print("[DB] 添加用户失败: URL 为空")
            return nil
        }

        let id = "user_\(UUID().uuidString.prefix(8))"
        let sql = "INSERT INTO users (id, url, mode, max_counts, nickname, aweme_count) VALUES (?, ?, ?, ?, ?, ?)"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, trimmedUrl, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, mode, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 4, Int32(maxCounts))
            if let nickname = nickname, !nickname.isEmpty {
                sqlite3_bind_text(statement, 5, nickname, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            if let awemeCount = awemeCount {
                sqlite3_bind_int(statement, 6, Int32(awemeCount))
            } else {
                sqlite3_bind_null(statement, 6)
            }

            if sqlite3_step(statement) == SQLITE_DONE {
                sqlite3_finalize(statement)
                let user = DouyinUser(id: id, url: trimmedUrl, mode: mode, maxCounts: maxCounts, nickname: nickname, awemeCount: awemeCount)
                DispatchQueue.main.async {
                    self.users.insert(user, at: 0)
                }
                print("[DB] 添加用户成功: \(id)")
                return user
            } else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                print("[DB] 添加用户失败: \(errMsg)")
            }
        }
        sqlite3_finalize(statement)
        return nil
    }

    func updateUser(_ user: DouyinUser) -> Bool {
        let sql = "UPDATE users SET mode = ?, max_counts = ?, interval = ?, nickname = ?, aweme_count = ? WHERE id = ?"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, user.mode, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(user.maxCounts))
            if let interval = user.interval {
                sqlite3_bind_text(statement, 3, interval, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            if let nickname = user.nickname {
                sqlite3_bind_text(statement, 4, nickname, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            if let awemeCount = user.awemeCount {
                sqlite3_bind_int(statement, 5, Int32(awemeCount))
            } else {
                sqlite3_bind_null(statement, 5)
            }
            sqlite3_bind_text(statement, 6, user.id, -1, SQLITE_TRANSIENT)

            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)

            if result {
                DispatchQueue.main.async {
                    if let index = self.users.firstIndex(where: { $0.id == user.id }) {
                        self.users[index] = user
                    }
                }
            }
            return result
        }
        sqlite3_finalize(statement)
        return false
    }

    func deleteUser(id: String) -> Bool {
        let sql = "DELETE FROM users WHERE id = ?"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)

            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)

            if result {
                // 验证删除是否成功
                let changes = sqlite3_changes(db)
                print("[DB] 删除用户 \(id): 影响 \(changes) 行")

                DispatchQueue.main.async {
                    self.users.removeAll { $0.id == id }
                }
            } else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                print("[DB] 删除用户失败: \(errMsg)")
            }
            return result
        } else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("[DB] 准备删除语句失败: \(errMsg)")
        }
        sqlite3_finalize(statement)
        return false
    }

    // MARK: - 设置管理

    func getSettings() -> AppSettings {
        var result = AppSettings.default
        let sql = "SELECT key, value FROM settings"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let key = String(cString: sqlite3_column_text(statement, 0))
                let value = String(cString: sqlite3_column_text(statement, 1))

                switch key {
                case "parallel": result.parallel = value == "true"
                case "max_workers": result.maxWorkers = Int(value) ?? 3
                case "on_error": result.onError = value
                case "mode": result.mode = value
                case "max_counts": result.maxCounts = Int(value) ?? 10
                case "path":
                    // 确保路径是绝对路径
                    if value.hasPrefix("/") {
                        result.path = value
                    } else {
                        // 相对路径转换为默认下载目录
                        result.path = DatabaseService.defaultDownloadDirectory.path
                        print("[DB] 修正相对路径为: \(result.path)")
                    }
                case "cover": result.cover = value == "true"
                case "embed_cover": result.embedCover = value == "true"
                default: break
                }
            }
        }
        sqlite3_finalize(statement)
        return result
    }

    func updateSettings(_ settings: AppSettings) {
        let updates: [(String, String)] = [
            ("parallel", settings.parallel ? "true" : "false"),
            ("max_workers", String(settings.maxWorkers)),
            ("on_error", settings.onError),
            ("mode", settings.mode),
            ("max_counts", String(settings.maxCounts)),
            ("path", settings.path),
            ("cover", settings.cover ? "true" : "false"),
            ("embed_cover", settings.embedCover ? "true" : "false"),
        ]

        for (key, value) in updates {
            let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, value, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }

        DispatchQueue.main.async {
            self.settings = settings
        }
    }

    // MARK: - Cookie 管理

    func getCookie() -> String {
        let sql = "SELECT value FROM settings WHERE key = 'cookie'"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let value = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                return value
            }
        }
        sqlite3_finalize(statement)
        return ""
    }

    func setCookie(_ cookie: String) {
        let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES ('cookie', ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, cookie, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    // MARK: - 数据导入

    func importFromPythonDB(at path: String) {
        // 从 Python 后端的 SQLite 数据库导入数据
        var sourceDB: OpaquePointer?
        guard sqlite3_open(path, &sourceDB) == SQLITE_OK else { return }
        defer { sqlite3_close(sourceDB) }

        // 导入用户
        let userSQL = "SELECT id, url, mode, max_counts, interval, nickname FROM users"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(sourceDB, userSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let url = String(cString: sqlite3_column_text(statement, 1))
                let mode = String(cString: sqlite3_column_text(statement, 2))
                let maxCounts = Int(sqlite3_column_int(statement, 3))
                let interval = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                let nickname = sqlite3_column_text(statement, 5).map { String(cString: $0) }

                // 插入到本地数据库
                let insertSQL = "INSERT OR IGNORE INTO users (id, url, mode, max_counts, interval, nickname) VALUES (?, ?, ?, ?, ?, ?)"
                var insertStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(insertStmt, 1, id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(insertStmt, 2, url, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(insertStmt, 3, mode, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(insertStmt, 4, Int32(maxCounts))
                    if let interval = interval {
                        sqlite3_bind_text(insertStmt, 5, interval, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(insertStmt, 5)
                    }
                    if let nickname = nickname {
                        sqlite3_bind_text(insertStmt, 6, nickname, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(insertStmt, 6)
                    }
                    sqlite3_step(insertStmt)
                }
                sqlite3_finalize(insertStmt)
            }
        }
        sqlite3_finalize(statement)

        // 导入设置
        let settingsSQL = "SELECT key, value FROM settings"
        if sqlite3_prepare_v2(sourceDB, settingsSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let key = String(cString: sqlite3_column_text(statement, 0))
                let value = String(cString: sqlite3_column_text(statement, 1))

                let insertSQL = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
                var insertStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(insertStmt, 1, key, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(insertStmt, 2, value, -1, SQLITE_TRANSIENT)
                    sqlite3_step(insertStmt)
                }
                sqlite3_finalize(insertStmt)
            }
        }
        sqlite3_finalize(statement)

        // 重新加载数据
        loadData()
    }

    // MARK: - 视频分析管理

    func createAnalysisTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS video_analysis (
                aweme_id TEXT PRIMARY KEY,
                file_path TEXT,
                tags TEXT,
                category TEXT,
                summary TEXT,
                objects TEXT,
                scene TEXT,
                sexy_level INTEGER DEFAULT 0,
                analyzed_at TEXT,
                error TEXT
            )
        """
        executeSQL(sql)
    }

    func saveAnalysis(_ analysis: VideoAnalysis) {
        createAnalysisTable()

        let sql = """
            INSERT INTO video_analysis (aweme_id, file_path, tags, category, summary, objects, scene, sexy_level, analyzed_at, error)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(aweme_id) DO UPDATE SET
                file_path = excluded.file_path,
                tags = excluded.tags,
                category = excluded.category,
                summary = excluded.summary,
                objects = excluded.objects,
                scene = excluded.scene,
                sexy_level = excluded.sexy_level,
                analyzed_at = excluded.analyzed_at,
                error = excluded.error
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let tagsJson = try? JSONEncoder().encode(analysis.tags)
            let objectsJson = try? JSONEncoder().encode(analysis.objects)

            sqlite3_bind_text(statement, 1, analysis.awemeId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, analysis.filePath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, tagsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "[]", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, analysis.category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, analysis.summary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 6, objectsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "[]", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 7, analysis.scene, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 8, Int32(analysis.sexyLevel))

            let dateFormatter = ISO8601DateFormatter()
            let dateStr = analysis.analyzedAt.map { dateFormatter.string(from: $0) } ?? dateFormatter.string(from: Date())
            sqlite3_bind_text(statement, 9, dateStr, -1, SQLITE_TRANSIENT)

            if let error = analysis.error {
                sqlite3_bind_text(statement, 10, error, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 10)
            }

            if sqlite3_step(statement) != SQLITE_DONE {
                print("[DB] 保存分析结果失败: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        sqlite3_finalize(statement)
    }

    func getAnalysis(awemeId: String) -> VideoAnalysis? {
        createAnalysisTable()

        let sql = "SELECT aweme_id, file_path, tags, category, summary, objects, scene, sexy_level, analyzed_at, error FROM video_analysis WHERE aweme_id = ?"

        var statement: OpaquePointer?
        var result: VideoAnalysis?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, awemeId, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_ROW {
                result = parseAnalysisRow(statement)
            }
        }
        sqlite3_finalize(statement)
        return result
    }

    func getAllAnalysis() -> [VideoAnalysis] {
        createAnalysisTable()

        var results: [VideoAnalysis] = []
        let sql = "SELECT aweme_id, file_path, tags, category, summary, objects, scene, sexy_level, analyzed_at, error FROM video_analysis WHERE error IS NULL ORDER BY analyzed_at DESC"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let analysis = parseAnalysisRow(statement) {
                    results.append(analysis)
                }
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func getAnalyzedAwemeIds() -> Set<String> {
        createAnalysisTable()

        var ids = Set<String>()
        let sql = "SELECT aweme_id FROM video_analysis WHERE error IS NULL"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                ids.insert(id)
            }
        }
        sqlite3_finalize(statement)
        return ids
    }

    private func parseAnalysisRow(_ statement: OpaquePointer?) -> VideoAnalysis? {
        guard let statement = statement else { return nil }

        let awemeId = String(cString: sqlite3_column_text(statement, 0))
        let filePath = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        let tagsStr = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "[]"
        let category = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
        let summary = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
        let objectsStr = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "[]"
        let scene = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
        let sexyLevel = Int(sqlite3_column_int(statement, 7))
        let analyzedAtStr = sqlite3_column_text(statement, 8).map { String(cString: $0) }
        let error = sqlite3_column_text(statement, 9).map { String(cString: $0) }

        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsStr.utf8))) ?? []
        let objects = (try? JSONDecoder().decode([String].self, from: Data(objectsStr.utf8))) ?? []

        let dateFormatter = ISO8601DateFormatter()
        let analyzedAt = analyzedAtStr.flatMap { dateFormatter.date(from: $0) }

        return VideoAnalysis(
            awemeId: awemeId,
            filePath: filePath,
            tags: tags,
            category: category,
            summary: summary,
            objects: objects,
            scene: scene,
            sexyLevel: sexyLevel,
            analyzedAt: analyzedAt,
            error: error
        )
    }

    // MARK: - 分析配置存储

    func getAnalysisApiKey(provider: String) -> String {
        let key = "analysis_\(provider)_api_key"
        let sql = "SELECT value FROM settings WHERE key = ?"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                let value = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                return value
            }
        }
        sqlite3_finalize(statement)
        return ""
    }

    func setAnalysisApiKey(provider: String, key apiKey: String) {
        let key = "analysis_\(provider)_api_key"
        let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, apiKey, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    func getAnalysisSetting(key settingKey: String) -> String? {
        let key = "analysis_\(settingKey)"
        let sql = "SELECT value FROM settings WHERE key = ?"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                let value = String(cString: sqlite3_column_text(statement, 0))
                sqlite3_finalize(statement)
                return value
            }
        }
        sqlite3_finalize(statement)
        return nil
    }

    func setAnalysisSetting(key settingKey: String, value: String) {
        let key = "analysis_\(settingKey)"
        let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, value, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    // MARK: - 下载统计

    /// 获取用户已下载的视频数量
    func getDownloadedCount(for user: DouyinUser) -> Int {
        let downloadPath = settings.path
        let nickname = user.nickname ?? user.displayName

        // 构建用户文件夹路径: {downloadPath}/douyin/{mode}/{nickname}/
        let userFolder = URL(fileURLWithPath: downloadPath)
            .appendingPathComponent("douyin")
            .appendingPathComponent(user.mode)
            .appendingPathComponent(nickname)

        return countVideos(in: userFolder)
    }

    /// 获取所有用户的下载数量
    func getAllDownloadedCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for user in users {
            counts[user.id] = getDownloadedCount(for: user)
        }
        return counts
    }

    private func countVideos(in folder: URL) -> Int {
        guard FileManager.default.fileExists(atPath: folder.path) else { return 0 }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            // 按作品前缀去重统计（一个作品可能有多个文件）
            var workPrefixes = Set<String>()
            let validExtensions = ["mp4", "webp", "jpg", "png"]

            for file in contents {
                let ext = file.pathExtension.lowercased()
                guard validExtensions.contains(ext) else { continue }

                let filename = file.deletingPathExtension().lastPathComponent

                // 提取作品前缀：移除 _video, _cover, _image_N, _live_N 后缀
                var prefix = filename
                if prefix.hasSuffix("_video") {
                    prefix = String(prefix.dropLast(6))
                } else if prefix.hasSuffix("_cover") {
                    prefix = String(prefix.dropLast(6))
                } else if let range = prefix.range(of: "_image_\\d+$", options: .regularExpression) {
                    prefix = String(prefix[..<range.lowerBound])
                } else if let range = prefix.range(of: "_live_\\d+$", options: .regularExpression) {
                    prefix = String(prefix[..<range.lowerBound])
                }

                workPrefixes.insert(prefix)
            }

            return workPrefixes.count
        } catch {
            return 0
        }
    }
}
