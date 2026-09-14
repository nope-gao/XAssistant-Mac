import Foundation

struct InputEvent: Codable, Equatable {
    var t: Double
    var device: String
    var kind: String // key, mouse, reset
    var key: String
    var down: Bool
    var control: String { device + ":" + kind + ":" + key }
}
final class EventStore {
    let folder: URL
    private let queue = DispatchQueue(label: "XAssistant.events")
    private var handles: [String: FileHandle] = [:]
    var onError: ((String) -> Void)?
    init(folder: URL) { self.folder=folder }
    func append(_ event: InputEvent) {
        queue.async {
            do {
                try FileManager.default.createDirectory(at:self.folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let date=dayKey(Date(timeIntervalSince1970:event.t))
                let file=self.folder.appendingPathComponent(date+".jsonl")
                if self.handles[date] == nil {
                    for h in self.handles.values { try h.close() }; self.handles.removeAll()
                    if !FileManager.default.fileExists(atPath:file.path) { FileManager.default.createFile(atPath:file.path,contents:nil,attributes:[.posixPermissions:0o600]) }
                    let h=try FileHandle(forWritingTo:file); try h.seekToEnd(); self.handles[date]=h
                }
                var data=try JSONEncoder().encode(event); data.append(10)
                try self.handles[date]!.write(contentsOf:data)
            } catch { self.onError?(L("按动记录保存失败：\(error.localizedDescription)", "Could not save activity: \(error.localizedDescription)")) }
        }
    }
    func availableRange() throws -> (Date?,Date?) {
        flush()
        guard FileManager.default.fileExists(atPath:folder.path) else {return (nil,nil)}
        let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter {$0.pathExtension=="jsonl"}.sorted {$0.lastPathComponent<$1.lastPathComponent}
        func timestamps(_ file:URL) throws -> [Double] {
            try Data(contentsOf:file).split(separator:10).compactMap {line in
                guard let e=try? JSONDecoder().decode(InputEvent.self,from:Data(line)),e.down,(e.kind=="key" || e.kind=="mouse") else {return nil}
                return e.t
            }
        }
        var first:Double?,last:Double?
        for file in files {if let t=try timestamps(file).min() {first=t;break}}
        for file in files.reversed() {if let t=try timestamps(file).max() {last=t;break}}
        return (first.map {Date(timeIntervalSince1970:$0)},last.map {Date(timeIntervalSince1970:$0)})
    }
    func flush() { queue.sync { for h in handles.values { try? h.synchronize() } } }
    func load(start: Date, end: Date) throws -> [InputEvent] {
        flush()
        let fm=FileManager.default
        guard fm.fileExists(atPath:folder.path) else { return [] }
        let first=dayKey(start), last=dayKey(end)
        let files=try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter { $0.pathExtension == "jsonl" && $0.deletingPathExtension().lastPathComponent >= first && $0.deletingPathExtension().lastPathComponent <= last }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [InputEvent]=[]
        for file in files {
            let data=try Data(contentsOf:file)
            let lines=data.split(separator:10,omittingEmptySubsequences:true)
            for (index,line) in lines.enumerated() {
                do {
                    let e=try JSONDecoder().decode(InputEvent.self,from:Data(line))
                    if e.t >= start.timeIntervalSince1970 && e.t <= end.timeIntervalSince1970 { result.append(e) }
                } catch {
                    // An interrupted last append can leave a partial final line; never hide corruption in the middle.
                    if index == lines.count-1 && data.last != 10 { continue }
                    throw NSError(domain:"EventStore",code:1,userInfo:[NSLocalizedDescriptionKey:L("事件文件损坏：\(file.lastPathComponent)，第 \(index+1) 行", "Corrupt event file: \(file.lastPathComponent), line \(index+1)")])
                }
            }
        }
        return result.enumerated().sorted { $0.element.t == $1.element.t ? $0.offset < $1.offset : $0.element.t < $1.element.t }.map(\.element)
    }
}
struct PlaybackEvent { var time: Double; var source: InputEvent }
struct PlaybackTimeline {
    let events: [PlaybackEvent]
    let duration: Double
    let pressCount: Int
    static let fps=30
    init(events input: [InputEvent], start: Double, end: Double, speed: Double, deviceID: String? = nil, includeMouse: Bool = true) {
        var normalized: [InputEvent]=[]
        var held: [String:InputEvent]=[:]
        for event in input.enumerated().sorted(by: { $0.element.t == $1.element.t ? $0.offset < $1.offset : $0.element.t < $1.element.t }).map(\.element) {
            guard event.t >= start && event.t <= end else { continue }
            if event.kind == "reset" {
                let controls=held.keys.filter { event.device == "*" || held[$0]?.device == event.device }.sorted()
                for c in controls { var up=held.removeValue(forKey:c)!; up.t=event.t; up.down=false; normalized.append(up) }
                continue
            }
            guard (includeMouse && event.kind == "mouse") || (event.kind == "key" && (deviceID == nil || event.device == deviceID)) else { continue }
            if event.down {
                if held[event.control] == nil { held[event.control]=event; normalized.append(event) }
            } else if held.removeValue(forKey:event.control) != nil { normalized.append(event) }
        }
        // Finish keys still held at Y. Do not invent any press before X or recover old aggregate counts.
        for control in held.keys.sorted() { var up=held[control]!; up.down=false; up.t=end; normalized.append(up) }
        let ordered=normalized.enumerated().sorted { $0.element.t == $1.element.t ? $0.offset < $1.offset : $0.element.t < $1.element.t }.map(\.element)
        var compact: [PlaybackEvent]=[]; var outputTime=0.0; var previous: InputEvent?
        for e in ordered {
            if let prev=previous {
                let delta=max(0,e.t-prev.t)
                // Simultaneous chord edges stay simultaneous, except opposite edges of the same key.
                if delta > 0.012 || e.control == prev.control {
                    outputTime += max(2.0/Double(Self.fps),min(delta,0.24))/max(0.25,speed)
                }
            }
            compact.append(PlaybackEvent(time:outputTime,source:e)); previous=e
        }
        events=compact
        pressCount=compact.filter { $0.source.down }.count
        duration=compact.isEmpty ? 0 : outputTime+3.0/Double(Self.fps)
    }
    var frameCount: Int { Int(ceil(duration*Double(Self.fps))) }
}

// Physical macOS virtual key -> USB HID key usage. No character translation is performed.
let macKeyUsages: [Int64:String] = [
0:"4",1:"22",2:"7",3:"9",4:"11",5:"10",6:"29",7:"27",8:"6",9:"25",11:"5",12:"20",13:"26",14:"8",15:"21",16:"28",17:"23",18:"30",19:"31",20:"32",21:"33",22:"35",23:"34",24:"46",25:"38",26:"36",27:"45",28:"37",29:"39",30:"48",31:"18",32:"24",33:"47",34:"12",35:"19",36:"40",37:"15",38:"13",39:"52",40:"14",41:"51",42:"49",43:"54",44:"56",45:"17",46:"16",47:"55",48:"43",49:"44",50:"53",51:"42",53:"41",54:"231",55:"227",56:"225",57:"57",58:"226",59:"224",60:"229",61:"230",62:"228",63:"fn",64:"108",65:"99",67:"85",69:"87",71:"83",75:"84",76:"88",78:"86",79:"109",80:"110",81:"103",82:"98",83:"89",84:"90",85:"91",86:"92",87:"93",88:"94",89:"95",91:"96",92:"97",96:"62",97:"63",98:"64",99:"60",100:"65",101:"66",103:"68",105:"104",106:"107",107:"105",109:"67",111:"69",113:"106",114:"73",115:"74",116:"75",117:"76",118:"61",119:"77",120:"59",121:"78",122:"58",123:"80",124:"79",125:"81",126:"82"]
