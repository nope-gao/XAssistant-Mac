import SwiftUI

final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()
    static let supported = ["zh-Hans", "zh-Hant", "en", "ja", "es", "fr", "de"]
    static let names = ["zh-Hans":"简体中文", "zh-Hant":"繁體中文", "en":"English", "ja":"日本語", "es":"Español", "fr":"Français", "de":"Deutsch"]
    // Only set in the separate renderer process; a job keeps its original language.
    static var renderLanguage: String?
    static var systemLanguages: [String] {
        UserDefaults.standard.stringArray(forKey:"AppleLanguages") ?? Locale.preferredLanguages
    }
    static func match(_ identifier: String) -> String? {
        let parts=identifier.replacingOccurrences(of:"_",with:"-").lowercased().split(separator:"-").map(String.init)
        guard let base=parts.first else {return nil}
        if base=="zh" {
            if parts.contains("hant") {return "zh-Hant"}
            if parts.contains("hans") {return "zh-Hans"}
            return parts.contains(where:{["tw","hk","mo"].contains($0)}) ? "zh-Hant":"zh-Hans"
        }
        return supported.contains(base) ? base:nil
    }
    static func resolve(_ saved: String?, preferred: [String]) -> String {
        if let saved, saved != "system", let language=match(saved) {return language}
        return preferred.compactMap(match).first ?? "en"
    }
    @Published var selection: String {
        didSet {
            UserDefaults.standard.set(selection,forKey:"appLanguage")
            NotificationCenter.default.post(name:.appLanguageChanged,object:nil)
        }
    }
    private var localeObserver: NSObjectProtocol?
    private init() {
        let saved=UserDefaults.standard.string(forKey:"appLanguage")
        selection=saved.flatMap {Self.supported.contains($0) ? $0:nil} ?? "system"
        localeObserver=NotificationCenter.default.addObserver(forName:NSLocale.currentLocaleDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self, self.selection=="system" else {return}
            self.objectWillChange.send()
            NotificationCenter.default.post(name:.appLanguageChanged,object:nil)
        }
    }
    static var current: String {renderLanguage ?? resolve(UserDefaults.standard.string(forKey:"appLanguage"),preferred:systemLanguages)}
    static var locale: Locale {Locale(identifier:current)}
}
extension Notification.Name {static let appLanguageChanged=Notification.Name("XAssistantAppLanguageChanged")}

// Capture interpolation before formatting so every language uses the same stable key.
struct LocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let template: String
    let arguments: [String]
    init(stringLiteral value:String) {template=value;arguments=[]}
    init(stringInterpolation value:StringInterpolation) {template=value.template;arguments=value.arguments}
    struct StringInterpolation: StringInterpolationProtocol {
        var template=""
        var arguments:[String]=[]
        init(literalCapacity:Int,interpolationCount:Int) {template.reserveCapacity(literalCapacity)}
        mutating func appendLiteral(_ literal:String) {template+=literal}
        mutating func appendInterpolation<T>(_ value:T) {
            template+="{\(arguments.count)}"
            if let number=value as? Int {arguments.append(localizedNumber(number))}
            else {arguments.append(String(describing:value))}
        }
    }
}
func localizedNumber(_ value:Int) -> String {
    let formatter=NumberFormatter();formatter.locale=AppLanguage.locale;formatter.numberStyle = .decimal
    return formatter.string(from:NSNumber(value:value)) ?? String(value)
}
enum StringCatalog {
    static let strings: [String:[String:String]] = {
        let url=Bundle.main.url(forResource:"localizations",withExtension:"json") ?? URL(fileURLWithPath:"Resources/localizations.json")
        return (try? JSONDecoder().decode([String:[String:String]].self,from:Data(contentsOf:url))) ?? [:]
    }()
    static func format(_ template:String, arguments:[String]) -> String {
        // A single pass prevents placeholder-like text inside an argument from being replaced.
        let expression=try! NSRegularExpression(pattern:"\\{([0-9]+)\\}")
        var result=template
        for match in expression.matches(in:template,range:NSRange(template.startIndex...,in:template)).reversed() {
            guard let numberRange=Range(match.range(at:1),in:template),let index=Int(template[numberRange]),arguments.indices.contains(index),let range=Range(match.range,in:result) else {continue}
            result.replaceSubrange(range,with:arguments[index])
        }
        return result
    }
    static func text(chinese:String, english:LocalizedText) -> String {
        let language=AppLanguage.current
        if language=="zh-Hans" {return chinese}
        if language=="zh-Hant" {return chinese.applyingTransform(StringTransform("Hans-Hant"),reverse:false) ?? chinese}
        let template=strings[language]?[english.template] ?? english.template
        return format(template,arguments:english.arguments)
    }
}
func L(_ chinese:String, _ english:LocalizedText) -> String {StringCatalog.text(chinese:chinese,english:english)}

// Status text is evaluated when displayed, so switching languages also updates existing messages.
struct LocalizedMessage: ExpressibleByStringLiteral {
    let render: () -> String
    init(_ render:@escaping ()->String) {self.render=render}
    init(stringLiteral value:String) {render={value}}
    var text:String {render()}
    var isEmpty:Bool {text.isEmpty}
    static func +(lhs:Self,rhs:Self) -> Self {Self {lhs.text+rhs.text}}
}
func M(_ chinese:@autoclosure @escaping ()->String, _ english:@autoclosure @escaping ()->LocalizedText) -> LocalizedMessage {
    LocalizedMessage {L(chinese(),english())}
}
func localizedStamp(_ date:Date) -> String {
    let formatter=DateFormatter();formatter.locale=AppLanguage.locale
    formatter.dateStyle = .medium;formatter.timeStyle = .medium
    return formatter.string(from:date)
}
func localizedDay(_ key:String) -> String {
    let parser=DateFormatter();parser.locale=Locale(identifier:"en_US_POSIX");parser.dateFormat="yyyy-MM-dd"
    guard let date=parser.date(from:key) else {return key}
    let formatter=DateFormatter();formatter.locale=AppLanguage.locale;formatter.dateStyle = .medium
    return formatter.string(from:date)
}
extension KeyboardProfile {
    var displayName:String {
        if id=="unattributed" {return L("来源未识别的键盘","Unidentified keyboard")}
        return name=="External Keyboard" ? L("外接键盘","External keyboard"):name
    }
}

extension KeyShape {
    var displayLabel:String {
        switch label {
        case "caps lock":return L("大写锁定","Caps Lock")
        case "clear":return L("清除","Clear")
        case "command":return L("⌘","⌘")
        case "control":return L("控制","Control")
        case "del →":return L("向前删除","Delete forward")
        case "delete":return L("删除","Delete")
        case "end":return L("末尾","End")
        case "enter":return L("输入","Enter")
        case "esc":return L("退出","Esc")
        case "fn / help":return L("fn / 帮助","fn / Help")
        case "home":return L("开头","Home")
        case "option":return L("⌥","⌥")
        case "page down":return L("下一页","Page Down")
        case "page up":return L("上一页","Page Up")
        case "return":return L("回车","Return")
        case "shift":return L("⇧","⇧")
        case "space":return L("空格","Space")
        case "tab":return L("制表","Tab")
        default:return label
        }
    }
}
