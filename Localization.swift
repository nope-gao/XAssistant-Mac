import SwiftUI

final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()
    // A renderer freezes the export language without changing the user's preference.
    static var renderLanguage: String?
    static func resolve(_ saved: String?, preferred: [String]) -> String {
        if let saved, ["zh-Hans", "en"].contains(saved) { return saved }
        return preferred.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
    @Published var selection: String {
        didSet {
            UserDefaults.standard.set(selection, forKey: "appLanguage")
            NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
        }
    }
    private init() {
        selection = Self.resolve(UserDefaults.standard.string(forKey: "appLanguage"), preferred: Locale.preferredLanguages)
    }
    static var current: String {
        renderLanguage ?? resolve(UserDefaults.standard.string(forKey: "appLanguage"), preferred: Locale.preferredLanguages)
    }
    static var locale: Locale { Locale(identifier: current == "en" ? "en_US" : "zh_CN") }
}
extension Notification.Name {
    static let appLanguageChanged = Notification.Name("XAssistantAppLanguageChanged")
}
func L(_ chinese: String, _ english: String) -> String {
    AppLanguage.current == "en" ? english : chinese
}

// Translate stored descriptive metadata at display time; keep device IDs and records unchanged.
extension KeyboardProfile {
    var displayName: String {
        id == "unattributed" ? L("来源未识别的键盘", "Unidentified keyboard") : name
    }
    var displayDetection: String {
        switch detection {
        case "内置键盘 → MacBook；键帽采用 ANSI 模板":
            return L(detection, "Built-in keyboard → MacBook; ANSI keycaps")
        case "HID 描述包含数字区 → 全尺寸（可校正）":
            return L(detection, "HID includes a number pad → full-size (adjustable)")
        case "HID 未声明完整数字区 → 紧凑布局（可校正）":
            return L(detection, "HID has no complete number pad → compact (adjustable)")
        case "系统事件可记录；多键盘来源无法确认":
            return L(detection, "System events available; source keyboard cannot be confirmed")
        default: return detection
        }
    }
}
