import Cocoa
import SwiftUI

struct PreciseDateField: NSViewRepresentable {
    @Binding var date: Date
    var minimum: Date?
    var maximum: Date
    var label: String
    func makeCoordinator() -> Coordinator {Coordinator(self)}
    func makeNSView(context: Context) -> NSDatePicker {
        let field=NSDatePicker()
        field.datePickerStyle = .textFieldAndStepper
        field.datePickerElements = [.yearMonthDay,.hourMinuteSecond]
        field.locale=Locale(identifier:"zh_CN")
        field.font=NSFont.monospacedDigitSystemFont(ofSize:13,weight:.regular)
        field.isBordered=true;field.drawsBackground=true
        field.target=context.coordinator;field.action=#selector(Coordinator.change(_:))
        field.setAccessibilityLabel(label)
        return field
    }
    func updateNSView(_ field:NSDatePicker,context:Context) {
        context.coordinator.parent=self
        field.minDate=minimum;field.maxDate=maximum
        if abs(field.dateValue.timeIntervalSince(date))>0.4 {field.dateValue=date}
    }
    final class Coordinator:NSObject {
        var parent:PreciseDateField
        init(_ parent:PreciseDateField) {self.parent=parent}
        @objc func change(_ field:NSDatePicker) {parent.date=field.dateValue}
    }
}
struct VideoExportPanel: View {
    @ObservedObject var tracker: Tracker
    @State private var customStart=Date()
    @State private var customEnd=Date()
    @State private var fromBeginning=true
    @State private var untilNow=true
    @State private var speed=16.0
    @AppStorage("exportIncludeMouse") private var includeMouse=true
    @AppStorage("exportHeatMode") private var heatMode="dynamic"
    @State private var options=false
    @State private var layoutOverride="auto"
    @State private var selectedDevice="auto"
    func stamp(_ date:Date) -> String {
        let f=DateFormatter();f.dateFormat="yyyy/MM/dd HH:mm:ss";return f.string(from:date)
    }
    var body: some View {
        TimelineView(.periodic(from:.now,by:1)) {clock in
            let now=clock.date
            let first=tracker.earliestEvent
            let start=fromBeginning ? (first ?? now) : customStart
            let end=untilNow ? now : customEnd
            let invalid=start>=end
            let outside=first.map {end<$0 || start>(tracker.latestEvent ?? now)} ?? true
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:6) {
                    Text("导出按动视频").font(.headline)
                    if tracker.boundsLoading {
                        Text("正在查找可用记录…").font(.caption).foregroundStyle(.secondary)
                    } else if let first {
                        Text("最早记录  \(stamp(first))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        if let latest=tracker.latestEvent {Text("最新记录  \(stamp(latest))").font(.caption).monospacedDigit().foregroundStyle(.secondary)}
                    } else {
                        Text("还没有可回放记录。开始操作键鼠后，这里会显示最早时间。").font(.callout).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing:12) {
                    HStack(spacing:12) {
                        Text("从").frame(width:24,alignment:.leading).foregroundStyle(.secondary)
                        PreciseDateField(date:Binding(get:{start},set:{customStart=$0;fromBeginning=false}),minimum:first,maximum:now,label:"开始时间").frame(height:26)
                        Button("最开始") {fromBeginning=true}.frame(width:70).disabled(first==nil).help("选择实际第一条按动记录")
                    }
                    HStack(spacing:12) {
                        Text("到").frame(width:24,alignment:.leading).foregroundStyle(.secondary)
                        PreciseDateField(date:Binding(get:{end},set:{customEnd=$0;untilNow=false}),minimum:first,maximum:now,label:"结束时间").frame(height:26)
                        Button("现在") {untilNow=true}.frame(width:70).help("导出时自动取最新时间")
                    }
                }.disabled(tracker.exporting || first==nil)
                HStack {
                    Text(untilNow ? "结束时间跟随现在" : "已固定结束时间").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("速度",selection:$speed) {
                        ForEach([0.5,1.0,2.0,4.0,8.0,16.0,32.0,64.0,128.0,256.0],id:\.self) {Text(String(format:"%g×",$0)).tag($0)}
                    }.frame(width:135).disabled(tracker.exporting)
                }
                HStack(spacing:18) {
                    Picker("鼠标",selection:$includeMouse) {Text("包含").tag(true);Text("不包含").tag(false)}.frame(width:160)
                    Picker("热力上限",selection:$heatMode) {Text("动态变化").tag("dynamic");Text("固定最高次数").tag("fixed")}
                        .help("动态：随回放变化；固定：采用所选时间和设备范围内的最高累计次数。")
                }.disabled(tracker.exporting)
                DisclosureGroup("设备与布局",isExpanded:$options) {
                    VStack(spacing:10) {
                        Picker("键盘",selection:$selectedDevice) {
                            Text("全部键盘").tag("auto")
                            ForEach(tracker.keyboards.values.sorted {$0.name<$1.name}) {p in Text(p.name).tag(p.id)}
                        }
                        Picker("布局",selection:$layoutOverride) {Text("自动识别").tag("auto");Text("MacBook / 紧凑").tag("macbook");Text("Mac 全尺寸").tag("mac-full")}
                    }.padding(.top,10).disabled(tracker.exporting)
                }.font(.callout)
                if first != nil && invalid {Text("开始时间需要早于结束时间。").font(.caption).foregroundStyle(.orange)}
                else if first != nil && outside {Text("这个范围内没有记录，请调整时间或选择最开始。").font(.caption).foregroundStyle(.orange)}
                HStack {
                    Text(includeMouse ? "键盘 + 鼠标 · 自动去空档" : "仅键盘 · 自动去空档").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if tracker.exporting {Button("取消") {tracker.cancelVideo()}}
                    Button(tracker.exporting ? "正在导出…" : "导出视频到下载") {
                        tracker.exportVideo(start:start,end:untilNow ? Date():end,speed:speed,layoutOverride:layoutOverride,deviceID:selectedDevice=="auto" ? nil:selectedDevice,includeMouse:includeMouse,heatMode:heatMode)
                    }.buttonStyle(.borderedProminent).disabled(tracker.exporting || tracker.boundsLoading || invalid || outside)
                }
                if tracker.exporting {ProgressView(value:tracker.exportProgress)}
                if !tracker.exportStatus.isEmpty {
                    HStack(alignment:.top) {
                        Text(tracker.exportStatus).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                        Spacer()
                        if !tracker.exporting,let url=tracker.lastVideoURL {Button("显示文件") {NSWorkspace.shared.activateFileViewerSelecting([url])}.buttonStyle(.link).font(.caption)}
                    }
                }
            }
        }
    }
}
extension Tracker {
    func cancelVideo() {
        exportCancelled=true
        videoTask?.terminate()
        exportStatus="正在取消…"
    }
    func exportVideo(start: Date,end: Date,speed: Double,layoutOverride: String,deviceID: String?,includeMouse: Bool,heatMode: String) {
        guard !exporting else {return}
        let actualEnd=min(end,Date())
        guard start<actualEnd else {exportStatus="开始时间必须早于结束时间，且不能晚于现在。";return}
        guard speed.isFinite && speed>=0.5 && speed<=256 else {exportStatus="请选择 0.5× 到 256× 的速度。";return}
        lastVideoURL=nil;exporting=true;exportCancelled=false;exportProgress=0;exportStatus="正在读取所选时间内的键盘和鼠标按动…"
        save()
        let profiles=keyboards
        let store=eventStore
        let fallbackLayout=keyboards[automaticKeyboardID]?.layout ?? "macbook"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            do {
                let events=try store.load(start:start,end:actualEnd)
                let timeline=PlaybackTimeline(events:events,start:start.timeIntervalSince1970,end:actualEnd.timeIntervalSince1970,speed:speed,deviceID:deviceID,includeMouse:includeMouse)
                guard timeline.pressCount>0 else {throw VideoFailure(message:"这段时间没有可回放的按动记录。请开启输入监控后实际操作键鼠，再选择对应时间；旧总次数不能生成动画。")}
                var layout=layoutOverride
                if layout=="auto" {
                    let used=Set(events.filter {$0.kind=="key" && (deviceID == nil || $0.device==deviceID)}.map(\.device))
                    layout=used.contains(where:{profiles[$0]?.layout=="mac-full"}) ? "mac-full" : fallbackLayout
                }
                let fm=FileManager.default
                let id=UUID().uuidString
                let cache=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/XAssistantMac/VideoJobs/"+id)
                try fm.createDirectory(at:cache,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let formatter=DateFormatter();formatter.dateFormat="yyyyMMdd-HHmmss"
                let downloads=fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                try fm.createDirectory(at:downloads,withIntermediateDirectories:true)
                let output=downloads.appendingPathComponent("键鼠按动-\(formatter.string(from:start))-\(formatter.string(from:actualEnd))-\(String(format:"%g",speed))x-\(id.prefix(6)).mp4")
                let progress=cache.appendingPathComponent("progress.json")
                let job=VideoJob(events:events,start:start.timeIntervalSince1970,end:actualEnd.timeIntervalSince1970,speed:speed,layout:layout,deviceID:deviceID,output:output.path,progress:progress.path,includeMouse:includeMouse,heatMode:heatMode)
                let jobURL=cache.appendingPathComponent("job.json")
                try JSONEncoder().encode(job).write(to:jobURL,options:.atomic)
                DispatchQueue.main.async {
                    guard let self else {return}
                    if self.exportCancelled {try? fm.removeItem(at:cache);self.exporting=false;self.exportStatus="已取消。";return}
                    do {
                        guard let executable=Bundle.main.executableURL else {throw VideoFailure(message:"找不到视频导出程序。")}
                        let task=Process();task.executableURL=executable;task.arguments=["--render-video",jobURL.path]
                        let log=cache.appendingPathComponent("render.log");fm.createFile(atPath:log.path,contents:nil)
                        let handle=try FileHandle(forWritingTo:log);task.standardOutput=handle;task.standardError=handle
                        self.videoTask=task
                        self.exportStatus="\(timeline.pressCount) 次按动 · 预计视频 \(duration(Double(KeyboardMovie.totalFrames(timeline))/Double(PlaybackTimeline.fps))) · 仅生成 MP4 到下载"
                        let exportStarted=Date()
                        self.videoProgressTimer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
                            if let data=try? Data(contentsOf:progress),let p=try? JSONSerialization.jsonObject(with:data) as? [String:Int],let frame=p["frame"],let total=p["total"],total>0 {
                                self?.exportProgress=Double(frame)/Double(total)
                                let elapsed=Date().timeIntervalSince(exportStarted)
                                let remaining=frame>0 ? elapsed*Double(total-frame)/Double(frame):0
                                self?.exportStatus="成片 \(duration(Double(KeyboardMovie.totalFrames(timeline))/Double(PlaybackTimeline.fps))) · \(Int(Double(frame)*100/Double(total)))% · " + (elapsed<3 ? "正在估算导出耗时…" : "预计还需 \(duration(remaining))")
                            }
                        }
                        task.terminationHandler={ [weak self] process in
                            try? handle.close()
                            DispatchQueue.main.async {
                                guard let self else {return}
                                self.videoProgressTimer?.invalidate();self.videoProgressTimer=nil;self.videoTask=nil;self.exporting=false
                                if self.exportCancelled {
                                    self.exportStatus="已取消视频导出。";try? fm.removeItem(at:cache)
                                } else if process.terminationStatus==0 && fm.fileExists(atPath:output.path) {
                                    self.exportProgress=1;self.lastVideoURL=output;self.exportStatus="视频已保存到下载文件夹。";try? fm.removeItem(at:cache)
                                    NSWorkspace.shared.activateFileViewerSelecting([output])
                                } else {
                                    let message=(try? String(contentsOf:log,encoding:.utf8))?.components(separatedBy:"\n").first(where:{$0.contains("VIDEO_ERROR")}) ?? "渲染进程未成功结束。"
                                    self.exportStatus="导出失败：\(message) 日志：\(log.path)"
                                    try? fm.removeItem(at:jobURL);try? fm.removeItem(at:cache.appendingPathComponent("rendering.mp4"))
                                }
                            }
                        }
                        do {try task.run()} catch {try? handle.close();throw error}
                    } catch {self.videoProgressTimer?.invalidate();self.videoTask=nil;self.exporting=false;self.exportStatus="导出失败：\(error.localizedDescription)";try? fm.removeItem(at:cache)}
                }
            } catch {DispatchQueue.main.async {self?.exporting=false;self?.exportStatus=error.localizedDescription}}
        }
    }
}
