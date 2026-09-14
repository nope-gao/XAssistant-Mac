import Cocoa

extension Tracker {
    func resetInput(device: String = "*") {
        eventStore.append(InputEvent(t:Date().timeIntervalSince1970,device:device,kind:"reset",key:"*",down:false))
        if device == "*" { recordedHeld.removeAll(); recentHID.removeAll(); recentFallback.removeAll(); fallbackKeyOwners.removeAll() }
        else { recordedHeld = recordedHeld.filter { !$0.hasPrefix(device+":") } }
    }
    func receiveHID(device: String, usage: String, down: Bool) {
        let t=Date().timeIntervalSince1970
        let match=usage+":"+String(down)
        recentHID[match] = recentHID[match,default:[]].filter {t-$0<0.3}
        recentHID[match,default:[]].append(t)
        if consumeRecent(&recentFallback,key:match,time:t) { return }
        let owner = !down ? fallbackKeyOwners.removeValue(forKey:usage) : nil
        acceptKey(device:owner ?? device,usage:usage,down:down,time:t)
    }
    func consumeRecent(_ values: inout [String:[Double]], key: String, time: Double) -> Bool {
        values[key] = values[key,default:[]].filter { abs($0-time)<0.25 }
        if let index=values[key]?.firstIndex(where:{abs($0-time)<0.12}) {
            values[key]!.remove(at:index);return true
        }
        return false
    }
    func receiveCGKey(usage: String, down: Bool) {
        let t=Date().timeIntervalSince1970
        guard !paused && !sleeping && !locked else {return}
        let epoch=inputEpoch
        DispatchQueue.main.asyncAfter(deadline:.now()+0.09) { [weak self] in
            guard let self, self.inputEpoch == epoch else {return}
            let match=usage+":"+String(down)
            if self.consumeRecent(&self.recentHID,key:match,time:t) {return}
            self.recentFallback[match] = self.recentFallback[match,default:[]].filter {t-$0<0.3}
            self.recentFallback[match,default:[]].append(t)
            let connected=self.keyboards.values.filter(\.connected)
            let id=connected.count==1 ? connected[0].id : "unattributed"
            if self.keyboards[id] == nil {
                self.keyboards[id]=KeyboardProfile(id:id,name:"来源未识别的键盘",transport:"Event tap",builtIn:false,layout:"macbook",detection:"系统事件可记录；多键盘来源无法确认",connected:true)
            }
            if down { self.fallbackKeyOwners[usage] = id }
            let owner = down ? id : (self.fallbackKeyOwners.removeValue(forKey:usage) ?? id)
            self.acceptKey(device:owner,usage:usage,down:down,time:t)
        }
    }
    func acceptKey(device: String, usage: String, down: Bool, time: Double) {
        lastInput=Date()
        guard !paused && !sleeping && !locked else {return}
        let event=InputEvent(t:time,device:device,kind:"key",key:usage,down:down)
        if down {
            guard recordedHeld.insert(event.control).inserted else {return}
            recordKey(deviceID:device,usage:usage)
        } else { guard recordedHeld.remove(event.control) != nil else {return} }
        if down {let date=Date(timeIntervalSince1970:event.t);earliestEvent=min(earliestEvent ?? date,date);latestEvent=max(latestEvent ?? date,date)}
        eventStore.append(event)
        recordedEventCount+=1
    }
    func recordMouse(button: Int64, down: Bool) {
        lastInput=Date()
        let event=InputEvent(t:Date().timeIntervalSince1970,device:"mouse",kind:"mouse",key:String(button),down:down)
        if down { guard recordedHeld.insert(event.control).inserted else {return} }
        else { guard recordedHeld.remove(event.control) != nil else {return} }
        if down {let date=Date(timeIntervalSince1970:event.t);earliestEvent=min(earliestEvent ?? date,date);latestEvent=max(latestEvent ?? date,date)}
        eventStore.append(event);recordedEventCount+=1
        if down {
            let key=dayKey();var day=days[key] ?? Day()
            if button==0 {day.left+=1} else if button==1 {day.right+=1} else {day.other+=1}
            days[key]=day
        }
    }
    func handleInput(_ type:CGEventType,_ event:CGEvent) {
        guard !paused && !sleeping && !locked else {return}
        switch type {
        case .keyDown, .keyUp:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {return}
            if let usage=macKeyUsages[event.getIntegerValueField(.keyboardEventKeycode)] {receiveCGKey(usage:usage,down:type == .keyDown)}
        case .flagsChanged:
            let code=event.getIntegerValueField(.keyboardEventKeycode)
            guard let usage=macKeyUsages[code] else {return}
            if code==57 {
                receiveCGKey(usage:usage,down:true)
                receiveCGKey(usage:usage,down:false)
            } else {
                let masks:[Int64:UInt64]=[59:1,56:2,60:4,55:8,54:16,58:32,61:64,62:8192,63:0x800000]
                if let mask=masks[code] {receiveCGKey(usage:usage,down:event.flags.rawValue & mask != 0)}
            }
        case .leftMouseDown: recordMouse(button:0,down:true)
        case .leftMouseUp: recordMouse(button:0,down:false)
        case .rightMouseDown: recordMouse(button:1,down:true)
        case .rightMouseUp: recordMouse(button:1,down:false)
        case .otherMouseDown, .otherMouseUp: recordMouse(button:event.getIntegerValueField(.mouseEventButtonNumber),down:type == .otherMouseDown)
        default:break
        }
    }
}
