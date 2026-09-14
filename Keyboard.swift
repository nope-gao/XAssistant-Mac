import Cocoa
import IOKit.hid

struct KeyboardProfile: Codable, Identifiable {
    var id: String
    var name: String
    var transport: String
    var builtIn: Bool
    var layout: String
    var detection: String
    var connected: Bool
}
struct KeyShape: Codable, Identifiable {
    var id: String
    var label: String
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}
struct KeyboardLayout: Codable { var name: String; var width: Double; var keys: [KeyShape] }
func loadLayouts() -> [String: KeyboardLayout] {
    let url = Bundle.main.url(forResource: "layouts", withExtension: "json") ?? URL(fileURLWithPath: "Resources/layouts.json")
    return (try? JSONDecoder().decode([String: KeyboardLayout].self, from: Data(contentsOf: url))) ?? [:]
}
// Physical HID usages only; timestamped press/release recording lives in EventStore.
final class KeyboardMonitor {
    var manager: IOHIDManager?
    var opened = false
    var devices: [String: KeyboardProfile] = [:]
    var handles: [UInt64: String] = [:]
    var held: [UInt64: Set<String>] = [:]
    var onDevices: (([String: KeyboardProfile]) -> Void)?
    var onKey: ((String, String) -> Void)?
    var onTransition: ((String, String, Bool) -> Void)?
    var onDisconnect: ((String) -> Void)?
    static func layout(builtIn: Bool, usages: Set<UInt32>) -> String {
        if builtIn { return "macbook" }
        return usages.contains(0x59) && usages.contains(0x62) && usages.contains(0x58) ? "mac-full" : "macbook"
    }
    func registryID(_ device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }
    func profile(_ device: IOHIDDevice) -> KeyboardProfile {
        func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
        let name = property(kIOHIDProductKey) as? String ?? "External Keyboard"
        let builtIn = (property("Built-In") as? NSNumber)?.boolValue == true || name.lowercased().contains("internal")
        let transport = property(kIOHIDTransportKey) as? String ?? "Unknown"
        let vendor = (property(kIOHIDVendorIDKey) as? NSNumber)?.intValue ?? 0
        let product = (property(kIOHIDProductIDKey) as? NSNumber)?.intValue ?? 0
        let location = (property(kIOHIDLocationIDKey) as? NSNumber)?.intValue ?? 0
        // Do not persist serial numbers. Identical devices without a location are grouped by model.
        let id = builtIn ? "builtin" : "\(vendor)-\(product)-\(location)-\(transport)"
        let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] ?? []
        let usages = Set(elements.filter { IOHIDElementGetUsagePage($0) == 7 }.map { IOHIDElementGetUsage($0) })
        let layout = Self.layout(builtIn: builtIn, usages: usages)
        let detection = builtIn ? "内置键盘 → MacBook；键帽采用 ANSI 模板" : (layout == "mac-full" ? "HID 描述包含数字区 → 全尺寸（可校正）" : "HID 未声明完整数字区 → 紧凑布局（可校正）")
        return KeyboardProfile(id: id, name: name, transport: transport, builtIn: builtIn, layout: layout, detection: detection, connected: true)
    }
    func add(_ device: IOHIDDevice) {
        let p = profile(device); handles[registryID(device)] = p.id; devices[p.id] = p; onDevices?(devices)
    }
    func remove(_ device: IOHIDDevice) {
        let rid = registryID(device)
        if let id = handles.removeValue(forKey: rid), !handles.values.contains(id) { devices[id]?.connected = false; onDisconnect?(id) }
        held.removeValue(forKey: rid); onDevices?(devices)
    }
    // Inventory is read-only and works before input-monitoring permission is granted.
    func inventory() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            let page = IORegistryEntryCreateCFProperty(service, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
            let usage = IORegistryEntryCreateCFProperty(service, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
            if page?.intValue == 1 && usage?.intValue == 6, let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) { add(device) }
            IOObjectRelease(service)
        }
    }
    func start() {
        guard manager == nil else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)); manager = m
        IOHIDManagerSetDeviceMatching(m, [kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 6] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx else { return }; Unmanaged<KeyboardMonitor>.fromOpaque(ctx).takeUnretainedValue().add(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            guard let ctx else { return }; Unmanaged<KeyboardMonitor>.fromOpaque(ctx).takeUnretainedValue().remove(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(m, { ctx, result, _, value in
            guard result == kIOReturnSuccess, let ctx else { return }
            Unmanaged<KeyboardMonitor>.fromOpaque(ctx).takeUnretainedValue().receive(value)
        }, context)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        opened = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        if let found = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> { for device in found { add(device) } }
    }
    func stop() {
        if let m = manager {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil; opened = false; held = [:]; handles = [:]
    }
    func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element); let usage = IOHIDElementGetUsage(element)
        // Keyboard, consumer controls, and Apple's Fn usage only.
        guard (page == 7 && usage >= 4 && usage <= 231) || (page == 12 && [0xE2,0xE9,0xEA,0xCD,0xB5,0xB6,0x6F,0x70].contains(usage)) || (page == 0xFF && usage == 3) else { return }
        guard IOHIDValueGetLength(value) <= 8 else { return }
        let device = IOHIDElementGetDevice(element)
        let rid = registryID(device)
        if handles[rid] == nil { add(device) }
        guard let id = handles[rid] else { return }
        let key = page == 7 ? String(usage) : (page == 12 ? "c:\(usage)" : "fn")
        let down = IOHIDValueGetIntegerValue(value) != 0
        transition(rid: rid, id: id, key: key, down: down)
    }
    func transition(rid: UInt64, id: String, key: String, down: Bool) {
        if down {
            if held[rid, default: []].insert(key).inserted { onKey?(id, key); onTransition?(id,key,true) }
        } else if held[rid, default: []].remove(key) != nil { onTransition?(id,key,false) }
    }
}
