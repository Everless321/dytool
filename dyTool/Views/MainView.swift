//
//  MainView.swift
//  dyTool
//
//  主窗口视图
//

import SwiftUI

enum NavigationItem: String, CaseIterable {
    case users = "用户管理"
    case download = "下载任务"
    case videos = "视频浏览"
    case analysis = "内容分析"

    var icon: String {
        switch self {
        case .users: return "person.2"
        case .download: return "arrow.down.circle"
        case .videos: return "play.rectangle.on.rectangle"
        case .analysis: return "sparkles"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @EnvironmentObject var f2Service: F2Service
    @EnvironmentObject var downloadState: DownloadState
    @State private var selectedItem: NavigationItem = .users

    var body: some View {
        NavigationSplitView {
            // 侧边栏
            List(NavigationItem.allCases, id: \.self, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    Label {
                        Text(item.rawValue)
                    } icon: {
                        if item == .download && f2Service.isDownloading {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .symbolEffect(.pulse)
                        } else {
                            Image(systemName: item.icon)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)

            // 底部状态
            VStack(spacing: 8) {
                Divider()
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("本地模式")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(databaseService.users.count) 用户")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        } detail: {
            // 详情区域
            switch selectedItem {
            case .users:
                UserListView()
            case .download:
                DownloadView()
            case .videos:
                VideoGalleryView()
            case .analysis:
                AnalysisView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    MainView()
        .environmentObject(DatabaseService.shared)
        .environmentObject(F2Service.shared)
        .environmentObject(DownloadState.shared)
}
