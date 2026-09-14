import Cocoa
import SwiftUI
import ServiceManagement

struct AppUsage: Codable { var name: String; var seconds: Double = 0 }
struct Day: Codable {
    var keys = 0
    var left = 0
    var right = 0
    var other = 0
    var awake: Double = 0
    var active: Double = 0
    var apps: [String: AppUsage] = [:]
    var deviceKeys: [String: [String: Int]]? = nil
}
func dayKey(_ date: Date = Date()) -> String {
    let f = DateFormatter(); f.locale=Locale(identifier:"en_US_POSIX"); f.calendar=Calendar(identifier:.gregorian); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
}
func duration(_ seconds: Double) -> String {
    let n = Int(seconds); return L("\(n / 3600) 小时 \(n % 3600 / 60) 分 \(n % 60) 秒", "\(n / 3600)h \(n % 3600 / 60)m \(n % 60)s")
}
final class Tracker: ObservableObject {
    @Published var days: [String: Day] = [:]
    @Published var paused = UserDefaults.standard.bool(forKey: "paused")
    @Published var inputOK = false
    @Published var error: LocalizedMessage = ""
    @Published var login = SMAppService.mainApp.status == .enabled
    let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/XAssistantMac")
    var file: URL { folder.appendingPathComponent("statistics.json") }
    @Published var keyboards: [String: KeyboardProfile] = [:]
    @Published var exporting = false
    @Published var exportStatus: LocalizedMessage = ""
    @Published var lastVideoURL: URL?
    @Published var earliestEvent: Date?
    @Published var latestEvent: Date?
    @Published var boundsLoading = true
    @Published var recordedEventCount = 0
    @Published var exportProgress = 0.0
    @Published var recordingSince: Date = {
        let saved=UserDefaults.standard.double(forKey:"eventRecordingSince")
        if saved>0 {return Date(timeIntervalSince1970:saved)}
        let now=Date();UserDefaults.standard.set(now.timeIntervalSince1970,forKey:"eventRecordingSince");return now
    }()
    lazy var eventStore = EventStore(folder: folder.appendingPathComponent("Events"))
    var recordedHeld: Set<String> = []
    var recentHID: [String:[Double]] = [:]
    var recentFallback: [String:[Double]] = [:]
    var fallbackKeyOwners: [String:String] = [:]
    var inputEpoch = 0
    var videoTask: Process?
    var videoProgressTimer: Timer?
    var exportCancelled = false
    var keyboardMonitor = KeyboardMonitor()
    var lastKeyboardID: String?
    var lastInput = Date.distantPast
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var timer: Timer?
    var last = Date()
    var sleeping = false
    var locked = false
    var ticks = 0
    var previousApp: NSRunningApplication?
    var observers: [NSObjectProtocol] = []
    init() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                do { days = try JSONDecoder().decode([String: Day].self, from: Data(contentsOf: file)) }
                catch {
                    let backup = folder.appendingPathComponent("statistics-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                    try FileManager.default.copyItem(at: file, to: backup)
                    self.error = M("旧数据无法读取，已备份：\(backup.lastPathComponent)", "Could not read old data. Backup: \(backup.lastPathComponent)")
                }
            }
        } catch { self.error = M("数据目录错误：\(error.localizedDescription)", "Data folder error: \(error.localizedDescription)") }
        previousApp = NSWorkspace.shared.frontmostApplication
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.tick(); self?.inputEpoch += 1; self?.resetInput(); self?.sleeping = true; self?.save() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.sleeping = false; self?.last = Date() })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.tick(); self?.previousApp = NSWorkspace.shared.frontmostApplication })
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.tick(); self?.inputEpoch += 1; self?.resetInput(); self?.locked = value; self?.last = Date(); self?.save() })
        }
        eventStore.onError = { [weak self] message in DispatchQueue.main.async { self?.error=message } }
        resetInput()
        let store=eventStore
        DispatchQueue.global(qos:.utility).async { [weak self] in
            do {
                let bounds=try store.availableRange()
                DispatchQueue.main.async {
                    guard let self else {return}
                    if let first=bounds.0 {self.earliestEvent=min(first,self.earliestEvent ?? first)}
                    if let last=bounds.1 {self.latestEvent=max(last,self.latestEvent ?? last)}
                    self.boundsLoading=false
                }
            } catch {DispatchQueue.main.async {self?.boundsLoading=false;self?.error=M("无法读取记录时间：\(error.localizedDescription)", "Could not read recording dates: \(error.localizedDescription)")}}
        }
        setupKeyboards()
        connectInput()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func tick() {
        let now = Date(); let start = last; let elapsed = now.timeIntervalSince(start); last = now
        if !paused && !sleeping && !locked && elapsed > 0 && elapsed < 5 {
            let systemIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
            let idle = min(systemIdle, now.timeIntervalSince(lastInput))
            var cursor = start
            while cursor < now {
                let boundary = Calendar.current.startOfDay(for: cursor).addingTimeInterval(1)
                let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: boundary))!
                let end = min(next, now); let seconds = end.timeIntervalSince(cursor)
                let key = dayKey(cursor); var d = days[key] ?? Day(); d.awake += seconds
                if idle < 60 {
                    d.active += seconds
                    if let app = previousApp {
                        let id = app.bundleIdentifier ?? app.localizedName ?? "unknown"
                        var usage = d.apps[id] ?? AppUsage(name: app.localizedName ?? id)
                        usage.seconds += seconds; d.apps[id] = usage
                    }
                }
                days[key] = d; cursor = end
            }
        }
        ticks += 1
        if ticks % 10 == 0 { save(); connectInput(); login = SMAppService.mainApp.status == .enabled }
    }
    func connectInput() {
        guard CGPreflightListenEventAccess() else {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            if inputOK { inputEpoch+=1; resetInput() }; inputOK = false; keyboardMonitor.stop(); return
        }
        if !keyboardMonitor.opened { keyboardMonitor.stop(); keyboardMonitor.start() }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); inputOK = CGEvent.tapIsEnabled(tap: tap); return }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let tracker = Unmanaged<Tracker>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = tracker.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else { tracker.handleInput(type, event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true); inputOK = true
        } else { inputOK = false }
    }
    func requestInput() {
        _ = CGRequestListenEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        connectInput()
    }
    func togglePause() { tick(); inputEpoch+=1; resetInput(); paused.toggle(); UserDefaults.standard.set(paused, forKey: "paused"); save() }
    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            login = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = M("登录启动设置失败：\(error.localizedDescription)", "Could not change launch at login: \(error.localizedDescription)") }
    }
    func save() {
        eventStore.flush()
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(days).write(to: file, options: .atomic); try encoder.encode(keyboards).write(to: folder.appendingPathComponent("keyboards.json"), options: .atomic) }
        catch { self.error = M("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)") }
    }

}
struct Dashboard: View {
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject var tracker: Tracker
    @State private var details=false
    @State private var selected=dayKey()
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text("XAssistant").font(.title3.weight(.semibold))
                Spacer()
                Circle().fill(tracker.paused ? Color.orange : (tracker.inputOK ? .green : .orange)).frame(width:6,height:6)
                Text(tracker.paused ? L("已暂停", "Paused") : (tracker.inputOK ? L("正在记录", "Recording") : L("等待权限", "Permission needed"))).font(.callout).foregroundStyle(.secondary)
                Button(tracker.paused ? L("继续", "Resume") : L("暂停", "Pause")) {tracker.togglePause()}.controlSize(.small)
            }.padding(.horizontal,22).padding(.vertical,16)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if !tracker.inputOK {
                        HStack(alignment:.center) {
                            VStack(alignment:.leading,spacing:3) {
                                Text(L("开启输入监控后才能记录", "Enable Input Monitoring to record")).font(.callout.weight(.medium))
                                Text(L("允许 XAssistant Mac 记录键鼠按动。", "Allow XAssistant Mac to record key presses and mouse clicks.")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("打开设置", "Open Settings")) {tracker.requestInput()}
                        }.padding(12).background(Color.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
                    }
                    VideoExportPanel(tracker:tracker)
                    Divider()
                    DisclosureGroup(L("统计与键盘热力图", "Statistics & keyboard heatmap"),isExpanded:$details) {
                        VStack(alignment:.leading,spacing:12) {
                            Picker(L("日期", "Date"),selection:$selected) {ForEach(Array(Set(tracker.days.keys).union([dayKey()])).sorted().reversed(),id:\.self) {Text(localizedDay($0)).tag($0)}}.frame(width:220)
                            let d=tracker.days[selected] ?? Day()
                            HStack {Text(L("键盘 \(d.keys)", "Keys \(d.keys)"));Text(L("鼠标 \(d.left+d.right+d.other)", "Clicks \(d.left+d.right+d.other)"));Spacer();Text(L("活跃 \(duration(d.active))", "Active \(duration(d.active))")).foregroundStyle(.secondary)}.font(.callout)
                            KeyboardPanel(tracker:tracker,day:selected)
                            ForEach(d.apps.keys.sorted {(d.apps[$0]?.seconds ?? 0)>(d.apps[$1]?.seconds ?? 0)},id:\.self) {key in
                                if let usage=d.apps[key] {HStack {Text(usage.name);Spacer();Text(duration(usage.seconds)).foregroundStyle(.secondary)}.font(.caption)}
                            }
                        }.padding(.top,12)
                    }.font(.callout)
                    if !tracker.error.isEmpty {Text(tracker.error.text).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
                }.padding(22)
            }
            Divider()
            HStack {
                Toggle(L("登录时启动", "Launch at login"),isOn:Binding(get:{tracker.login},set:{_ in tracker.toggleLogin()})).toggleStyle(.checkbox)
                Spacer()
                Picker(L("语言", "Language"), selection: $language.selection) {
                    Text(L("跟随系统", "Follow system")).tag("system")
                    ForEach(AppLanguage.supported,id: \.self) {code in Text(AppLanguage.names[code] ?? code).tag(code)}
                }.labelsHidden().frame(width:140).disabled(tracker.exporting)
                Button(L("数据文件夹", "Data folder")) {tracker.save();NSWorkspace.shared.open(tracker.folder)}.buttonStyle(.link)
            }.font(.caption).padding(.horizontal,22).padding(.vertical,12)
        }.frame(minWidth:600,minHeight:560)
        .environment(\.locale, AppLanguage.locale)
    }
}
final class Delegate: NSObject, NSApplicationDelegate {
    var tracker: Tracker!
    var status: NSStatusItem!
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        tracker = Tracker()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: L("XAssistant 活动统计", "XAssistant activity statistics"))
        rebuildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu), name: .appLanguageChanged, object: nil)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "XAssistant Mac"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Dashboard(tracker: tracker)); window.center()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") { show(); UserDefaults.standard.set(true, forKey: "hasLaunched") }
    }
    @objc func rebuildMenu() {
        status.button?.setAccessibilityLabel(L("XAssistant 活动统计", "XAssistant activity statistics"))
        let menu = NSMenu()
        for (title, action) in [(L("查看统计", "Show dashboard"), #selector(show)), (L("暂停 / 继续记录", "Pause / resume recording"), #selector(pause)), (L("输入监控权限…", "Input Monitoring…"), #selector(permission)), (L("退出 XAssistant", "Quit XAssistant"), #selector(quit))] { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        status.menu = menu
    }
    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func pause() { tracker.togglePause(); status.button?.image = NSImage(systemSymbolName: tracker.paused ? "pause.circle" : "chart.bar.xaxis", accessibilityDescription: "XAssistant") }
    @objc func permission() { tracker.requestInput() }
    @objc func quit() { tracker.tick(); tracker.resetInput(); tracker.save(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { tracker?.save() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
}
if CommandLine.arguments.contains("--media-self-test") {
    try verifyClickEncoding()
} else if CommandLine.arguments.contains("--write-localizations") {
    let resources=Bundle.main.resourceURL!
    let key="Record key and mouse press/release times locally for animated playback. Key sequences may reveal typed content."
    for language in AppLanguage.supported {
        let folder=resources.appendingPathComponent(language+".lproj")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var text=StringCatalog.strings[language]?[key] ?? StringCatalog.strings["zh-Hans"]![key]!
        if language=="zh-Hant" {text=text.applyingTransform(StringTransform("Hans-Hant"),reverse:false) ?? text}
        let value=text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")
        try ("\"NSInputMonitoringUsageDescription\" = \""+value+"\";\n").write(to:folder.appendingPathComponent("InfoPlist.strings"),atomically:true,encoding:.utf8)
    }
} else if let index=CommandLine.arguments.firstIndex(of:"--render-video"), CommandLine.arguments.count>index+1 {
    do {
        let job=try JSONDecoder().decode(VideoJob.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[index+1])))
        try KeyboardMovie.render(job)
    } catch { fputs("VIDEO_ERROR: \(error.localizedDescription)\n",stderr);exit(1) }
} else if CommandLine.arguments.contains("--self-test") {
    var d = Day(); d.keys = 3; d.apps["test"] = AppUsage(name: "Test", seconds: 61)
    let data = try JSONEncoder().encode(["2026-09-12": d])
    let decoded = try JSONDecoder().decode([String: Day].self, from: data)
    precondition(decoded["2026-09-12"]?.keys == 3)
    precondition(decoded["2026-09-12"]?.apps["test"]?.seconds == 61)
    precondition(AppLanguage.resolve(nil, preferred:["en-GB"]) == "en")
    precondition(AppLanguage.resolve(nil, preferred:["zh-Hant"]) == "zh-Hant")
    precondition(AppLanguage.resolve("en", preferred:["zh-Hans"]) == "en")
    precondition(AppLanguage.resolve("invalid", preferred:["fr"]) == "fr")
    AppLanguage.renderLanguage = "zh-Hans"
    precondition(duration(3661) == "1 小时 1 分 1 秒")
    precondition(L("现在", "Now") == "现在")
    AppLanguage.renderLanguage = "en"
    precondition(duration(3661) == "1h 1m 1s")
    precondition(L("现在", "Now") == "Now")
    precondition(AppLanguage.resolve(nil,preferred:["it-IT","fr-CA","en"]) == "fr")
    precondition(AppLanguage.resolve("system",preferred:["zh-TW"]) == "zh-Hant")
    precondition(AppLanguage.resolve(nil,preferred:["zh-Hans-TW"]) == "zh-Hans")
    precondition(AppLanguage.resolve("ja",preferred:["de-DE"]) == "ja")
    precondition(AppLanguage.resolve(nil,preferred:["pt-BR"]) == "en")
    let message=M("正在记录", "Recording")
    AppLanguage.renderLanguage="fr"
    precondition(message.text == "Enregistrement")
    precondition(L("已播放 3 次按动", "\(3) presses played") == "3 appuis reproduits")
    AppLanguage.renderLanguage="ja"
    precondition(message.text == "記録中")
    AppLanguage.renderLanguage="zh-Hant"
    precondition(L("记录键盘", "unused") == "記錄鍵盤")
    precondition(StringCatalog.format("{0} / {1}",arguments:["literal {1}","done"]) == "literal {1} / done")
    let catalog=StringCatalog.strings
    let expected=Set(catalog["en"]!.keys)
    let placeholders=try! NSRegularExpression(pattern:"\\{[0-9]+\\}")
    func tokens(_ value:String) -> [String] {
        placeholders.matches(in:value,range:NSRange(value.startIndex...,in:value)).map {String(value[Range($0.range,in:value)!])}.sorted()
    }
    for language in AppLanguage.supported where language != "zh-Hant" {
        precondition(Set(catalog[language]!.keys)==expected)
        for (key,translation) in catalog[language]! {precondition(tokens(key)==tokens(translation), "Invalid placeholders: \(language) \(key)")}
    }
    AppLanguage.renderLanguage = nil
    let legacy = Data("{\"2026-09-12\":{\"keys\":12,\"left\":2,\"right\":0,\"other\":0,\"awake\":12,\"active\":5,\"apps\":{}}}".utf8)
    let migrated = try JSONDecoder().decode([String: Day].self, from: legacy)
    precondition(migrated["2026-09-12"]?.keys == 12 && migrated["2026-09-12"]?.deviceKeys == nil)
    d.deviceKeys = ["builtin": ["4":3,"225":2]]
    let detailed = try JSONDecoder().decode(Day.self,from:JSONEncoder().encode(d))
    precondition(detailed.deviceKeys?["builtin"]?["225"] == 2)
    precondition(KeyboardMonitor.layout(builtIn:true,usages:[0x59,0x62,0x58]) == "macbook")
    precondition(KeyboardMonitor.layout(builtIn:false,usages:[0x59,0x62,0x58]) == "mac-full")
    precondition(KeyboardMonitor.layout(builtIn:false,usages:[4,5]) == "macbook")
    precondition(loadLayouts().count == 2)
    let monitor = KeyboardMonitor()
    var captured: [String] = []
    monitor.onKey = { device, key in captured.append(device + ":" + key) }
    monitor.transition(rid:1,id:"builtin",key:"4",down:true)
    monitor.transition(rid:1,id:"builtin",key:"4",down:true)
    monitor.transition(rid:1,id:"builtin",key:"225",down:true)
    monitor.transition(rid:1,id:"builtin",key:"4",down:false)
    monitor.transition(rid:1,id:"builtin",key:"4",down:true)
    monitor.transition(rid:2,id:"external",key:"4",down:true)
    precondition(captured == ["builtin:4","builtin:225","builtin:4","external:4"])
    func ev(_ t:Double,_ key:String,_ down:Bool,_ kind:String="key",_ device:String="builtin") -> InputEvent {InputEvent(t:t,device:device,kind:kind,key:key,down:down)}
    let actions=[ev(99,"9",true),ev(100,"9",false),ev(101,"225",true),ev(101.005,"4",true),ev(101.1,"4",true),ev(102,"4",false),ev(150,"0",true,"mouse","mouse"),ev(150.1,"0",false,"mouse","mouse"),ev(190,"225",false),ev(201,"5",true)]
    let red=KeyboardMovie.heatColor(count:10,maximum:10)
    precondition(red == KeyboardMovie.heatColor(count:20,maximum:20))
    precondition(red != KeyboardMovie.heatColor(count:10,maximum:20))
    precondition(KeyboardMovie.heatColor(count:0,maximum:0) == KeyboardMovie.heatColor(count:0,maximum:20))
    let slow=PlaybackTimeline(events:actions,start:100,end:200,speed:0.5)
    let fast=PlaybackTimeline(events:actions,start:100,end:200,speed:4)
    let turbo=PlaybackTimeline(events:actions,start:100,end:200,speed:64)
    precondition(abs((fast.duration-0.1)/(turbo.duration-0.1)-16)<0.001)
    precondition(turbo.pressCount==fast.pressCount && turbo.events.count==fast.events.count)
    precondition(KeyboardMovie.totalFrames(fast)-fast.frameCount==150)
    precondition(slow.pressCount==3 && fast.pressCount==3)
    precondition(slow.duration<3 && fast.duration<slow.duration)
    precondition(fast.events[0].time==fast.events[1].time)
    precondition(fast.events.filter {$0.source.down}.map(\.source.key)==["225","4","0"])
    let fastest=PlaybackTimeline(events:actions,start:100,end:200,speed:256)
    precondition(fastest.pressCount==fast.pressCount && fastest.events.count==fast.events.count)
    precondition(abs((turbo.duration-0.1)/(fastest.duration-0.1)-4)<0.001)
    for preset in ClickSound.allCases where preset != .silent {
        let voices=Set(macKeyUsages.values).map {KeyClickSynth.waveform(key:"key:"+$0,preset:preset)}
        precondition(Set(voices.map {Data(bytes:$0,count:$0.count*MemoryLayout<Float>.size)}).count == voices.count)
        precondition(KeyClickSynth.waveform(key:"key:4",preset:preset) != KeyClickSynth.waveform(key:"key:5",preset:preset))
        let synth=KeyClickSynth(timeline:fastest,preset:preset)
        let pcm=synth.samples(count:KeyboardMovie.totalFrames(fastest)*KeyClickSynth.sampleRate/PlaybackTimeline.fps)
        precondition(synth.triggered == fastest.pressCount)
        precondition(pcm.contains {$0 != 0} && pcm.allSatisfy {$0.isFinite && abs($0)<1})
        precondition(pcm.suffix(KeyClickSynth.sampleRate*4).allSatisfy {$0==0})
    }
    precondition(KeyClickSynth.waveform(key:"key:4",preset:.keyboard) != KeyClickSynth.waveform(key:"key:4",preset:.mechanical))
    let mute=KeyClickSynth(timeline:fastest,preset:.silent)
    precondition(mute.samples(count:4800).allSatisfy {$0==0})
    print("PASS: system language matching, 7 languages, catalog coverage, live message translation, per-key timbres, sound presets and press counts")
    let keyboardOnly=PlaybackTimeline(events:actions,start:100,end:200,speed:4,includeMouse:false)
    precondition(keyboardOnly.pressCount==2 && keyboardOnly.events.allSatisfy {$0.source.kind=="key"})
    let truncated=PlaybackTimeline(events:[ev(100,"4",true)],start:99,end:110,speed:1)
    precondition(truncated.events.count==2 && truncated.events.last?.source.down==false)
    let reset=InputEvent(t:101,device:"*",kind:"reset",key:"*",down:false)
    let paused=PlaybackTimeline(events:[ev(100,"4",true),reset,ev(110,"4",false)],start:99,end:120,speed:1)
    precondition(paused.events.count==2 && paused.events.last?.source.t==101)
    let filtered=PlaybackTimeline(events:actions,start:100,end:200,speed:1,deviceID:"external")
    precondition(filtered.pressCount==1 && filtered.events.allSatisfy {$0.source.kind=="mouse"})
    let testFolder=FileManager.default.temporaryDirectory.appendingPathComponent("XAssistant-test-"+UUID().uuidString)
    let store=EventStore(folder:testFolder)
    let emptyBounds=try store.availableRange()
    precondition(emptyBounds.0==nil && emptyBounds.1==nil)
    store.append(InputEvent(t:1,device:"*",kind:"reset",key:"*",down:false))
    let resetBounds=try store.availableRange()
    precondition(resetBounds.0==nil && resetBounds.1==nil)
    actions.forEach {store.append($0)};store.flush()
    let available=try store.availableRange()
    precondition(available.0?.timeIntervalSince1970==99 && available.1?.timeIntervalSince1970==201)
    let loaded=try store.load(start:Date(timeIntervalSince1970:100),end:Date(timeIntervalSince1970:200))
    precondition(loaded==Array(actions.dropFirst().dropLast()))
    try FileManager.default.removeItem(at:testFolder)
    print("PASS: timeline boundaries, gap removal, speed, chords, mouse, reset, event persistence")
    print("PASS: legacy migration, per-device counts, layout detection, JSON and duration")
} else {
    let app = NSApplication.shared
    let delegate = Delegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
}
