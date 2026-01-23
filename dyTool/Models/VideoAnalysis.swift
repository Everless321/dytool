//
//  VideoAnalysis.swift
//  dyTool
//
//  视频分析数据模型
//

import Foundation

struct VideoAnalysis: Identifiable, Codable {
    let awemeId: String
    var filePath: String
    var tags: [String]
    var category: String
    var summary: String
    var objects: [String]
    var scene: String
    var sexyLevel: Int
    var analyzedAt: Date?
    var error: String?

    var id: String { awemeId }

    var tagsString: String {
        tags.joined(separator: ", ")
    }

    var objectsString: String {
        objects.joined(separator: ", ")
    }

    var sexyLevelDescription: String {
        switch sexyLevel {
        case 1...2: return "正常"
        case 3...4: return "轻微"
        case 5...6: return "中度"
        case 7...8: return "较高"
        case 9...10: return "高度"
        default: return "未知"
        }
    }

    static let empty = VideoAnalysis(
        awemeId: "",
        filePath: "",
        tags: [],
        category: "",
        summary: "",
        objects: [],
        scene: "",
        sexyLevel: 0
    )
}

// MARK: - 分析配置

struct AnalysisConfig {
    var provider: AIProvider = .gemini
    var apiKey: String = ""
    var endpoint: String = ""  // 自定义端点，空则使用默认
    var model: String = ""     // 自定义模型，空则使用默认
    var frameCount: Int = 4
    var concurrency: Int = 1
    var requestDelay: Double = 2.0
    var rpm: Int = 0           // 每分钟请求数限制，0 表示不限制
    var skipAnalyzed: Bool = true

    enum AIProvider: String, CaseIterable {
        case gemini = "gemini"
        case grok = "grok"

        var displayName: String {
            switch self {
            case .gemini: return "Gemini"
            case .grok: return "Grok"
            }
        }

        var defaultModel: String {
            switch self {
            case .gemini: return "gemini-2.0-flash"
            case .grok: return "grok-2-vision-1212"
            }
        }

        var defaultEndpoint: String {
            switch self {
            case .gemini: return "https://generativelanguage.googleapis.com"
            case .grok: return "https://api.x.ai"
            }
        }

        var envKey: String {
            switch self {
            case .gemini: return "GEMINI_API_KEY"
            case .grok: return "GROK_API_KEY"
            }
        }
    }
}

// MARK: - 分析结果

struct AnalysisResponse: Codable {
    let tags: [String]?
    let category: String?
    let summary: String?
    let objects: [String]?
    let scene: String?
    let sexy_level: Int?
}

// MARK: - 标签体系

struct TagSystem {
    static let clothing: [String: [String]] = [
        "丝袜": ["黑丝", "白丝", "肉丝", "彩丝", "网袜", "渔网袜", "条纹袜"],
        "袜子长度": ["短袜", "中筒袜", "过膝袜", "大腿袜", "连裤袜", "堆堆袜"],
        "鞋子": ["裸足", "高跟鞋", "平底鞋", "凉鞋", "靴子", "运动鞋", "拖鞋", "玛丽珍鞋"],
        "下装": ["短裙", "长裙", "百褶裙", "包臀裙", "热裤", "牛仔裤", "阔腿裤", "打底裤", "短裤"],
        "上装": ["衬衫", "T恤", "吊带", "露脐装", "外套", "毛衣", "卫衣", "背心", "抹胸"],
        "整体服装": ["JK制服", "旗袍", "连衣裙", "礼服", "汉服", "洛丽塔", "女仆装", "水手服", "西装"],
    ]

    static let cosplay: [String: [String]] = [
        "来源": ["动漫cos", "游戏cos", "影视cos", "原创cos", "Vtuber"],
        "角色类型": ["女仆", "护士", "学生", "兔女郎", "猫娘", "巫女", "修女", "魔女", "偶像", "萝莉", "御姐"],
        "风格": ["萝莉风", "御姐风", "甜美风", "暗黑风", "清纯风", "性感风", "可爱风"],
    ]

    static let dance: [String: [String]] = [
        "舞种": ["宅舞", "韩舞", "古典舞", "现代舞", "街舞", "爵士舞", "拉丁舞", "民族舞", "芭蕾"],
        "氛围": ["可爱向", "性感向", "帅气向", "优雅向", "活力向"],
    ]

    static let contentTypes = ["舞蹈", "穿搭展示", "Cosplay", "日常", "变装", "写真", "Vlog", "教程"]
}
