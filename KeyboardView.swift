import SwiftUI
import Cocoa

struct KeyboardPanel: View {
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject var tracker: Tracker
    var day: String
    @State var deviceSelection = "auto"
    @State var layoutSelection = "auto"
    let layouts = loadLayouts()
    var deviceID: String { deviceSelection == "auto" ? tracker.automaticKeyboardID : deviceSelection }
    var profile: KeyboardProfile? { tracker.keyboards[deviceID] }
    var layoutID: String { layoutSelection == "auto" ? (profile?.layout ?? "macbook") : layoutSelection }
    var counts: [String: Int] { tracker.days[day]?.deviceKeys?[deviceID] ?? [:] }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker(L("设备", "Device"), selection: $deviceSelection) {
                    Text(L("自动 · 当前使用设备", "Auto · active keyboard")).tag("auto")
                    ForEach(tracker.keyboards.values.sorted { $0.name < $1.name }) { p in Text(p.displayName + (p.connected ? "" : L("（离线）", " (offline)"))).tag(p.id) }
                }.frame(maxWidth: .infinity)
                Picker(L("布局", "Layout"), selection: $layoutSelection) {
                    Text(L("自动识别", "Auto-detect")).tag("auto"); Text(L("MacBook / 紧凑", "MacBook / compact")).tag("macbook"); Text(L("Mac 全尺寸", "Mac full-size")).tag("mac-full")
                }.frame(width: 150)
            }
            HStack {
                Text(profile?.displayName ?? L("等待键盘识别", "Waiting for a keyboard")).font(.subheadline.bold())

                Spacer(); Text(L("\(counts.values.reduce(0,+)) 次", "\(counts.values.reduce(0,+)) presses")).monospacedDigit()
            }
            if let layout = layouts[layoutID] {
                GeometryReader { geo in
                    let unit = min(geo.size.width / layout.width, geo.size.height / 6)
                    let maximum = counts.values.max() ?? 0
                    ZStack(alignment: .topLeading) {
                        ForEach(layout.keys) { k in
                            let count = counts[k.id] ?? 0
                            VStack(spacing: 2) {
                                Text(k.label).font(.system(size: max(7,min(10,unit*0.19))))
                                if k.h > 0.7 { Text(k.id == "touch" ? "—" : "\(count)").font(.system(size: max(8,min(12,unit*0.23)), weight: .semibold)).monospacedDigit() }
                            }
                            .frame(width: k.w*unit-3, height: k.h*unit-3)
                            .foregroundStyle(Color.black.opacity(0.82))
                            .background(color(count, maximum), in: RoundedRectangle(cornerRadius: 4))
                            .offset(x:k.x*unit,y:k.y*unit)
                            .help(L("\(k.label)：\(count) 次", "\(k.label): \(count) presses"))
                        }
                    }
                }.frame(height: layout.width > 20 ? 145 : 220).frame(maxWidth: .infinity)
            }
            Text(L("灰色 = 0 · 蓝 → 黄 → 橙 = 使用频率提高", "Gray = 0 · Blue → yellow → orange = more presses")).font(.caption).foregroundStyle(.secondary)
            Text(L("逐键记录从本次升级开始；包含左右修饰键。模型采用 ANSI 键帽，Touch ID 不计数，部分媒体键单列在导出总数中。", "Per-key counts include left and right modifiers. The model uses ANSI keycaps. Touch ID is not counted; some media keys only appear in export totals.")).font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
    func color(_ count: Int, _ maxCount: Int) -> Color {
        guard count > 0 && maxCount > 0 else { return Color(red: 0.80, green: 0.83, blue: 0.85) }
        let t = log1p(Double(count))/log1p(Double(maxCount))
        if t < 0.5 { return Color(red:0.38+t*0.9,green:0.62+t*0.2,blue:0.82-t*0.6) }
        return Color(red:0.96,green:0.78-(t-0.5)*0.95,blue:0.45-(t-0.5)*0.55)
    }
}

extension Tracker {
    var automaticKeyboardID: String {
        if let id = lastKeyboardID, keyboards[id]?.connected == true { return id }
        if keyboards["builtin"]?.connected == true { return "builtin" }
        return keyboards.values.filter(\.connected).sorted { $0.id < $1.id }.first?.id ?? keyboards.keys.sorted().first ?? ""
    }
    func setupKeyboards() {
        let url = folder.appendingPathComponent("keyboards.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: KeyboardProfile].self, from: data) {
            keyboards = saved.mapValues { var p=$0; p.connected=false; return p }
        }
        keyboardMonitor.onDevices = { [weak self] devices in
            guard let self else { return }
            for (id,p) in devices { self.keyboards[id] = p }
        }
        keyboardMonitor.onTransition = { [weak self] id, usage, down in self?.receiveHID(device:id,usage:usage,down:down) }
        keyboardMonitor.onDisconnect = { [weak self] id in self?.resetInput(device:id) }
        keyboardMonitor.inventory()
        if CGPreflightListenEventAccess() { keyboardMonitor.start() }
    }
    func recordKey(deviceID: String, usage: String) {
        lastInput = Date()
        guard !paused && !sleeping && !locked else { return }
        let key = dayKey(); var day = days[key] ?? Day()
        day.keys += 1
        var perDevice = day.deviceKeys ?? [:]
        perDevice[deviceID, default: [:]][usage, default: 0] += 1
        day.deviceKeys = perDevice
        days[key] = day
        lastKeyboardID = deviceID
    }
}
