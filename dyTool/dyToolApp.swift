//
//  dyToolApp.swift
//  dyTool
//
//  Created by Everless on 2026/1/21.
//

import SwiftUI

@main
struct dyToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var databaseService = DatabaseService.shared
    @StateObject private var f2Service = F2Service.shared
    @StateObject private var downloadState = DownloadState.shared

    var body: some Scene {
        // 主窗口
        WindowGroup {
            MainView()
                .environmentObject(databaseService)
                .environmentObject(f2Service)
                .environmentObject(downloadState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // 菜单栏
        MenuBarExtra {
            MenuBarView()
                .environmentObject(databaseService)
                .environmentObject(f2Service)
                .environmentObject(downloadState)
        } label: {
            Image(systemName: f2Service.isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .menuBarExtraStyle(.window)

        // 设置窗口
        Settings {
            SettingsView()
                .environmentObject(databaseService)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 尝试从 Python 后端数据库导入数据（如果存在）
        let pythonDBPath = "/Users/everless/project/douyintool/douyintool.db"
        if FileManager.default.fileExists(atPath: pythonDBPath) {
            DatabaseService.shared.importFromPythonDB(at: pythonDBPath)
            print("已从 Python 数据库导入数据")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 停止正在进行的下载
        F2Service.shared.stopDownload()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // 关闭窗口后继续在菜单栏运行
    }
}
