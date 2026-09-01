import Foundation

/// The languages DockGlance's UI can be shown in. Default: English.
enum Language: String, CaseIterable, Identifiable, Codable {
    case english
    case chinese

    var id: String { rawValue }

    /// The name shown in the Language picker (each language names itself).
    var displayName: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }

    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .chinese: Locale(identifier: "zh_CN")
        }
    }
}

/// The app's UI strings. The key is always the English text; `localized`
/// returns the Chinese rendering when the language is set to Chinese.
/// Values are never formatted with `String(format:)` — callers interpolate
/// them instead (a format/CVarArg mismatch is how bogus numbers appeared).
enum L10n {
    static func localized(_ key: String, _ language: Language) -> String {
        guard language == .chinese, let chinese = chineseStrings[key] else {
            return key
        }
        return chinese
    }

    private static let chineseStrings: [String: String] = [
        // Cards
        "CPU": "CPU",
        "Memory": "内存",
        "Temperature": "温度",
        "Disk": "磁盘",
        "Download speed": "下载速度",
        "Upload speed": "上传速度",
        "Battery": "电池",
        "Connection (Wi-Fi/Ethernet)": "网络（Wi-Fi/以太网）",
        "Public IP": "公网 IP",
        "Time": "时间",
        "Date": "日期",
        "Weather": "天气",

        // Settings window
        "Language": "语言",
        "Temperature unit": "温度单位",
        "Card height": "卡片高度",
        "Bottom gap": "底部间距",
        "Background color": "背景颜色",
        "Background opacity": "背景透明度",
        "Text color": "文字颜色",
        "Cards": "卡片",
        "Side": "位置",
        "Left": "左",
        "Right": "右",
        "Show/hide": "显示/隐藏",

        // Context menu
        "About DockGlance": "关于 DockGlance",
        "Settings…": "设置…",
        "Start at Login": "开机启动",
        "Profiles": "配置",
        "Save Current as Profile…": "将当前设置保存为配置…",
        "Delete Active Profile…": "删除当前配置…",
        "Quit DockGlance": "退出 DockGlance",
        "Save": "保存",
        "Cancel": "取消",
        "Delete": "删除",
        "Save current settings as profile": "将当前设置保存为配置",
        "Overwrites an existing profile with the same name.": "将覆盖同名配置。",
        "Profile name": "配置名称",
        "Delete profile": "删除配置",
        "Your current settings stay unchanged.": "当前设置保持不变。",

        // Pop-up content
        "Charge": "电量",
        "Status": "状态",
        "Time to full": "充满电还需",
        "Charging": "充电中",
        "On battery": "使用电池",
        "Health": "健康度",
        "Cycles": "循环次数",
        "Good": "良好",
        "Fair": "一般",
        "Poor": "较差",
        "Used": "已用",
        "Free": "可用",
        "Total": "总计",
        "Humidity": "湿度",
        "Wind": "风速",
        "km/h": "公里/小时",
        "Feels like": "体感温度",
        "Tomorrow": "明天",
        "Fanless": "无风扇",
        "Fan": "风扇",
        "RPM": "转/分",
        "Connection": "连接",
        "h": "小时",
        "min": "分钟",
        "IP address": "IP 地址",
        "Country": "国家",
        "Region": "地区",
        "City": "城市",
        "Postal code": "邮政编码",
        "ISP": "运营商",
        "Organization": "机构",
        "ASN": "ASN",
        "Timezone": "时区",

        // Weather conditions (WMO titles from WeatherMonitor)
        "Clear sky": "晴",
        "Partly cloudy": "多云",
        "Overcast": "阴天",
        "Foggy": "雾",
        "Drizzle": "毛毛雨",
        "Rain": "雨",
        "Snow": "雪",
        "Showers": "阵雨",
        "Snow showers": "阵雪",
        "Thunderstorm": "雷雨",

        // About window
        "Version": "版本",
        "Author": "作者",
        "DockGlance Settings": "DockGlance 设置",
    ]
}