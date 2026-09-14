import Cocoa
import SceneKit
import AVFoundation
import Metal

struct VideoJob: Codable {
    var events: [InputEvent]
    var start: Double
    var end: Double
    var speed: Double
    var layout: String
    var deviceID: String?
    var output: String
    var progress: String
    var testLabel: String? = nil
    var includeMouse: Bool? = nil
    var heatMode: String? = nil
    var language: String? = nil
    var sound: String? = nil
}
struct VideoFailure: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
final class KeyboardMovie {
    let scene=SCNScene()
    let renderer: SCNRenderer
    let metal: MTLDevice
    let commandQueue: MTLCommandQueue
    let depthTexture: MTLTexture
    var textureCache: CVMetalTextureCache?
    var dirtyLabels: Set<String>=[]
    var framePresses: Set<String>=[]
    var caps: [String:SCNNode]=[:]
    var labels: [String:SCNNode]=[:]
    var caption: [String:String]=[:]
    var bases: [String:CGFloat]=[:]
    var motions: [String:(CGFloat,CGFloat,Double)]=[:]
    var counts: [String:Int]=[:]
    var held: Set<String>=[]
    var activeCounts: [String:Int]=[:]
    var seenPresses=0
    var fixedPeak: Int?
    var cameraCenter=SCNVector3Zero
    var cameraStart=SCNVector3Zero
    static let outroSeconds=5
    static func totalFrames(_ timeline: PlaybackTimeline) -> Int {timeline.frameCount+outroSeconds*PlaybackTimeline.fps}
    func orbit(progress: Double) {
        guard let camera=renderer.pointOfView else {return}
        let p=min(1,max(0,progress)), angle=(p*p*(3-2*p))*Double.pi/15
        let dx=cameraStart.x-cameraCenter.x, dz=cameraStart.z-cameraCenter.z
        camera.position=SCNVector3(cameraCenter.x+dx*cos(angle)+dz*sin(angle),cameraStart.y,cameraCenter.z-dx*sin(angle)+dz*cos(angle))
        camera.look(at:cameraCenter)
    }
    let width=1920, height=1080
    let progressURL: URL
    init(layout: KeyboardLayout, progress: URL, includeMouse: Bool = true) throws {
        guard let metal=MTLCreateSystemDefaultDevice() else { throw VideoFailure(message:L("无法使用图形设备进行视频渲染。", "No graphics device available for video rendering.")) }
        self.metal=metal
        guard let queue=metal.makeCommandQueue() else {throw VideoFailure(message:L("无法创建图形队列。", "Could not create a graphics command queue."))}
        commandQueue=queue
        let depthDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:width,height:height,mipmapped:false)
        depthDescriptor.usage = .renderTarget;depthDescriptor.storageMode = .private
        guard let depth=metal.makeTexture(descriptor:depthDescriptor) else {throw VideoFailure(message:L("无法创建深度缓冲区。", "Could not create a depth buffer."))}
        depthTexture=depth
        renderer=SCNRenderer(device:metal,options:nil)
        CVMetalTextureCacheCreate(nil,nil,metal,nil,&textureCache)
        renderer.scene=scene; renderer.autoenablesDefaultLighting=false
        progressURL=progress
        scene.background.contents=NSColor(calibratedWhite:0.93,alpha:1)
        let silver=NSColor(calibratedWhite:0.72,alpha:1)
        box("Base",x:layout.width/2,y:0,z:3,w:layout.width+0.5,h:0.4,d:6.5,color:silver,bevel:0.15)
        box("Recess",x:layout.width/2,y:0.23,z:3,w:layout.width+0.06,h:0.1,d:6.03,color:NSColor(calibratedWhite:0.17,alpha:1),bevel:0.10)
        for key in layout.keys {
            let name="key:"+key.id
            let cap=box(name,x:key.x+key.w/2,y:0.52,z:key.y+key.h/2,w:key.w-0.08,h:0.38,d:key.h-0.08,color:NSColor(calibratedWhite:0.85,alpha:1),bevel:0.06)
            caps[name]=cap; bases[name]=cap.position.y; caption[name]=key.displayLabel
            let plane=SCNPlane(width:key.w-0.13,height:key.h-0.13)
            let label=SCNNode(geometry:plane); label.eulerAngles.x = -.pi/2; label.position=SCNVector3(0,0.22,0)
            plane.firstMaterial=SCNMaterial(); plane.firstMaterial!.lightingModel = .constant; plane.firstMaterial!.isDoubleSided=true
            cap.addChildNode(label); labels[name]=label; updateLabel(name)
        }
        let mx=layout.width+3.0
        if includeMouse {
        let body=SCNNode(geometry:SCNSphere(radius:1)); body.scale=SCNVector3(1.45,0.48,2.3); body.position=SCNVector3(mx,0.37,3.2)
        body.geometry!.firstMaterial=material(silver); scene.rootNode.addChildNode(body)
        for (id,label,x,z,w,d) in [("0",L("左键","Left"),mx-0.62,2.4,1.12,1.65),("1",L("右键","Right"),mx+0.62,2.4,1.12,1.65),("2",L("中键","Middle"),mx,1.6,0.35,0.65),("3",L("后退","Back"),mx-1.42,3.6,0.34,0.8),("4",L("前进","Forward"),mx-1.42,4.5,0.34,0.8)] {
            let name="mouse:"+id
            let node=box(name,x:x,y:1.05,z:z,w:w,h:0.25,d:d,color:NSColor(calibratedWhite:0.84,alpha:1),bevel:0.09)
            caps[name]=node; bases[name]=node.position.y; caption[name]=label
            let plane=SCNPlane(width:w*0.88,height:d*0.65); let txt=SCNNode(geometry:plane)
            txt.position.y=0.135; txt.eulerAngles.x = -.pi/2; plane.firstMaterial=SCNMaterial(); plane.firstMaterial!.lightingModel = .constant
            node.addChildNode(txt); labels[name]=txt; updateLabel(name)
        }
        }
        let floor=SCNNode(geometry:SCNFloor()); floor.position.y = -0.25; floor.geometry!.firstMaterial=material(NSColor(calibratedWhite:0.93,alpha:1)); (floor.geometry as? SCNFloor)?.reflectivity=0
        scene.rootNode.addChildNode(floor)
        let ambient=SCNNode(); ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=650;scene.rootNode.addChildNode(ambient)
        let light=SCNNode();light.light=SCNLight();light.light!.type = .directional;light.light!.intensity=900;light.light!.castsShadow=true;light.light!.shadowMode = .deferred;light.light!.shadowRadius=4;light.light!.shadowColor=NSColor.black.withAlphaComponent(0.25);light.eulerAngles=SCNVector3(-0.9,-0.4,0);scene.rootNode.addChildNode(light)
        let cam=SCNNode();cam.camera=SCNCamera();cam.camera!.usesOrthographicProjection=true
        cam.camera!.orthographicScale=(layout.width+(includeMouse ? 6:1))*0.32
        cam.camera!.zNear=0.1;cam.camera!.zFar=100
        cam.position=SCNVector3((layout.width+(includeMouse ? 5:0))/2+0.4,16,15);cam.look(at:SCNVector3((layout.width+(includeMouse ? 5:0))/2,0,2.7))
        cameraCenter=SCNVector3((layout.width+(includeMouse ? 5:0))/2,0,2.7);cameraStart=cam.position
        scene.rootNode.addChildNode(cam);renderer.pointOfView=cam
    }
    func material(_ color:NSColor)->SCNMaterial {
        let m=SCNMaterial();m.diffuse.contents=color;m.lightingModel = .physicallyBased;m.roughness.contents=0.62;m.metalness.contents=0.12;return m
    }
    @discardableResult func box(_ name:String,x:Double,y:Double,z:Double,w:Double,h:Double,d:Double,color:NSColor,bevel:Double)->SCNNode {
        let shape=SCNBox(width:w,height:h,length:d,chamferRadius:bevel);shape.firstMaterial=material(color)
        let n=SCNNode(geometry:shape);n.name=name;n.position=SCNVector3(x,y,z);scene.rootNode.addChildNode(n);return n
    }
    func updateLabel(_ visual:String) {
        guard let node=labels[visual],let plane=node.geometry as? SCNPlane else {return}
        let w=max(64,Int(plane.width*260)), h=max(64,Int(plane.height*260))
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:rep) else {return}
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        NSColor.clear.setFill();NSRect(x:0,y:0,width:w,height:h).fill()
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
        let label=caption[visual] ?? visual
        let labelSize=min(42.0,Double(h)*0.26,Double(w)/Double(max(label.count,1))*1.2)
        (label as NSString).draw(in:NSRect(x:2,y:Double(h)*0.52,width:Double(w)-4,height:Double(h)*0.45),withAttributes:[.font:NSFont.systemFont(ofSize:labelSize),.foregroundColor:NSColor(calibratedWhite:0.12,alpha:1),.paragraphStyle:paragraph])
        (localizedNumber(counts[visual] ?? 0) as NSString).draw(in:NSRect(x:2,y:Double(h)*0.04,width:Double(w)-4,height:Double(h)*0.48),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:min(54,Double(h)*0.32),weight:.medium),.foregroundColor:NSColor(calibratedWhite:0.08,alpha:1),.paragraphStyle:paragraph])
        NSGraphicsContext.restoreGraphicsState()
        let image=NSImage(size:NSSize(width:w,height:h));image.addRepresentation(rep)
        let material=plane.firstMaterial!
        material.diffuse.contents=image;material.diffuse.maxAnisotropy=16
        material.writesToDepthBuffer=false
        node.renderingOrder=10
    }
    func apply(_ playback: PlaybackEvent) {
        let e=playback.source
        let candidate=e.kind+":"+e.key
        guard caps[candidate] != nil else {if e.down {seenPresses+=1};return}
        let visual=candidate
        if e.down {
            guard held.insert(e.control).inserted else {return}
            counts[visual,default:0]+=1; seenPresses+=1; activeCounts[visual,default:0]+=1; dirtyLabels.insert(visual); framePresses.insert(visual)
        } else {
            guard held.remove(e.control) != nil else {return}
            activeCounts[visual,default:0]=max(0,activeCounts[visual,default:0]-1)
        }
    }
    // Linear normalization against the peak reached at this playback instant.
    // Recompute every frame so unchanged keys cool down when another key takes the lead.
    static func heatColor(count: Int, maximum: Int) -> NSColor {
        guard count>0 && maximum>0 else {return NSColor(calibratedWhite:0.88,alpha:1)}
        let t=min(1,max(0,Double(count)/Double(maximum)))
        let stops:[(Double,Double,Double)]=[(0.36,0.63,0.86),(0.97,0.79,0.40),(1.0,0.49,0.23),(0.93,0.24,0.13)]
        let x=t*Double(stops.count-1), i=min(stops.count-2,Int(x)), f=x-Double(i)
        let a=stops[i], b=stops[i+1]
        return NSColor(calibratedRed:a.0+(b.0-a.0)*f,green:a.1+(b.1-a.1)*f,blue:a.2+(b.2-a.2)*f,alpha:1)
    }
    func draw(time: Double, sourceTime: Double, job: VideoJob, buffer: CVPixelBuffer) throws {
        for visual in dirtyLabels {updateLabel(visual)}
        dirtyLabels.removeAll()
        // A quick down/up within one output frame remains visible as a pulse.
        let peak=fixedPeak ?? (counts.values.max() ?? 0)
        for (id,cap) in caps {
            let pressed=activeCounts[id,default:0]>0 || framePresses.contains(id)
            cap.position.y=(bases[id] ?? 0.5)-(pressed ? 0.18:0)
            cap.geometry?.firstMaterial?.diffuse.contents=Self.heatColor(count:counts[id,default:0],maximum:peak)
        }
        framePresses.removeAll()
        SCNTransaction.flush()
        var wrapped: CVMetalTexture?
        guard let cache=textureCache,
              CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,.bgra8Unorm,width,height,0,&wrapped)==kCVReturnSuccess,
              let wrapped, let texture=CVMetalTextureGetTexture(wrapped),let command=commandQueue.makeCommandBuffer() else {throw VideoFailure(message:L("无法创建视频纹理。", "Could not create a video texture."))}
        let pass=MTLRenderPassDescriptor()
        pass.depthAttachment.texture=depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth=1
        pass.colorAttachments[0].texture=texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        renderer.render(atTime:time,viewport:CGRect(x:0,y:0,width:width,height:height),commandBuffer:command,passDescriptor:pass)
        command.commit();command.waitUntilCompleted()
        if let error=command.error {throw error}
        CVPixelBufferLockBaseAddress(buffer,[])
        defer {CVPixelBufferUnlockBaseAddress(buffer,[])}
        guard let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {throw VideoFailure(message:L("无法创建文字绘图环境。", "Could not create a text drawing context."))}
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        defer {NSGraphicsContext.restoreGraphicsState()}
        let df=DateFormatter();df.locale=AppLanguage.locale;df.dateStyle = .medium;df.timeStyle = .medium
        func text(_ body:String,_ x:Double,_ y:Double,_ size:Double,_ bold:Bool=false) {
            let weight:NSFont.Weight=bold ? .semibold:.regular
            let measured=(body as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight)]).width
            let available=(y<100 && x<1000) ? 930.0:Double(width)-x-60
            let fitted=min(size,size*available/max(1,measured))
            (body as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:fitted,weight:weight),.foregroundColor:NSColor(calibratedWhite:0.12,alpha:1)])
        }
        text((job.includeMouse ?? true) ? L("键盘 + 鼠标 · 按动延时摄影", "Keyboard + mouse · Activity timelapse") : L("键盘 · 按动延时摄影", "Keyboard · Activity timelapse"),70,978,36,true)
        text("\(df.string(from:Date(timeIntervalSince1970:job.start)))  →  \(df.string(from:Date(timeIntervalSince1970:job.end)))",70,936,23)
        if let label=job.testLabel {text(label,1450,978,26,true)}
        text(L("热力：蓝 → 黄 → 橙 → 红", "Heat: blue → yellow → orange → red") + "   " + (fixedPeak == nil ? L("动态上限", "Dynamic max") : L("固定上限", "Fixed max")) + " " + localizedNumber(peak),1050,82,20)
        text(L("未使用为灰色 · 按下时键帽下沉", "Unused keys are gray · Pressed keys move down"),1110,46,20)
        text(L("原始时间  \(df.string(from:Date(timeIntervalSince1970:sourceTime)))", "Recorded at  \(df.string(from:Date(timeIntervalSince1970:sourceTime)))"),70,80,23)
        text(L("已播放 \(seenPresses) 次按动", "\(seenPresses) presses played") + "  ·  \(String(format:"%g",job.speed))×  ·  " + L("空档已移除", "Idle gaps removed"),70,42,22)

    }
    static func render(_ job: VideoJob) throws {
        AppLanguage.renderLanguage = AppLanguage.resolve(job.language ?? UserDefaults.standard.string(forKey:"appLanguage"), preferred: AppLanguage.systemLanguages)
        let timeline=PlaybackTimeline(events:job.events,start:job.start,end:job.end,speed:job.speed,deviceID:job.deviceID,includeMouse:job.includeMouse ?? true)
        guard timeline.pressCount>0 else {throw VideoFailure(message:L("所选时间内没有可回放的按动事件。", "No replayable presses in the selected time range."))}
        guard let layout=loadLayouts()[job.layout] else {throw VideoFailure(message:L("键盘布局不存在。", "Keyboard layout not found."))}
        let movie=try KeyboardMovie(layout:layout,progress:URL(fileURLWithPath:job.progress),includeMouse:job.includeMouse ?? true)
        if job.heatMode == "fixed" {
            var totals:[String:Int]=[:]
            for e in timeline.events where e.source.down {
                let candidate=e.source.kind+":"+e.source.key
                if movie.caps[candidate] != nil {totals[candidate,default:0]+=1}
            }
            movie.fixedPeak=totals.values.max() ?? 0
        }
        let final=URL(fileURLWithPath:job.output)
        let temp=movie.progressURL.deletingLastPathComponent().appendingPathComponent("rendering.mp4")
        let writer=try AVAssetWriter(outputURL:temp,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:movie.width,AVVideoHeightKey:movie.height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:8_000_000,AVVideoExpectedSourceFrameRateKey:PlaybackTimeline.fps]])
        input.expectsMediaDataInRealTime=false
        let attrs:[String:Any]=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:movie.width,kCVPixelBufferHeightKey as String:movie.height,kCVPixelBufferMetalCompatibilityKey as String:true,kCVPixelBufferIOSurfacePropertiesKey as String:[:],kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true]
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:attrs)
        guard writer.canAdd(input) else {throw VideoFailure(message:L("无法创建 H.264 编码器。", "Could not create the H.264 encoder."))};writer.add(input)
        let totalFrames=Self.totalFrames(timeline)
        let preset=ClickSound(rawValue:job.sound ?? "keyboard") ?? .keyboard
        let audio=try preset == .silent ? nil:ClickAudioTrack(writer:writer,timeline:timeline,preset:preset,totalFrames:totalFrames)
        defer {if writer.status == .writing {writer.cancelWriting()}}
        guard writer.startWriting() else {throw writer.error ?? VideoFailure(message:L("视频编码无法启动。", "Could not start video encoding."))}
        writer.startSession(atSourceTime:.zero)
        audio?.start(writer:writer)
        var cursor=0;var sourceTime=job.start
        for frame in 0..<totalFrames {
            try autoreleasepool {
                let t=Double(frame)/Double(PlaybackTimeline.fps)
                while cursor<timeline.events.count && timeline.events[cursor].time<=t+0.00001 {
                    movie.apply(timeline.events[cursor]);sourceTime=timeline.events[cursor].source.t;cursor+=1
                }
                if frame>=timeline.frameCount {
                    movie.framePresses.removeAll();movie.activeCounts.removeAll();movie.held.removeAll()
                    movie.orbit(progress:Double(frame-timeline.frameCount)/Double(Self.outroSeconds*PlaybackTimeline.fps-1))
                }
                var optional:CVPixelBuffer?
                let status=CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&optional)
                guard status==kCVReturnSuccess,let buffer=optional else {throw VideoFailure(message:L("无法分配视频缓冲区。", "Could not allocate a video buffer."))}
                try movie.draw(time:t,sourceTime:sourceTime,job:job,buffer:buffer)
                let deadline=Date().addingTimeInterval(30)
                while !input.isReadyForMoreMediaData {
                    if writer.status != .writing || Date()>deadline {throw writer.error ?? VideoFailure(message:L("视频编码超时。", "Video encoding timed out."))}
                    Thread.sleep(forTimeInterval:0.005)
                }
                guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:Int32(PlaybackTimeline.fps))) else {throw writer.error ?? VideoFailure(message:L("写入视频帧失败。", "Could not write a video frame."))}
                if frame%10==0 || frame==totalFrames-1 {
                    let data=try JSONSerialization.data(withJSONObject:["frame":frame+1,"total":totalFrames,"presses":timeline.pressCount])
                    try data.write(to:movie.progressURL,options:.atomic)
                }
            }
        }
        input.markAsFinished()
        if let audio {
            guard audio.done.wait(timeout:.now()+30) == .success,writer.status == .writing else {throw VideoFailure(message:L("无法编码音频。","Could not encode audio."))}
        }
        writer.endSession(atSourceTime:CMTime(value:Int64(totalFrames),timescale:Int32(PlaybackTimeline.fps)))
        let done=DispatchSemaphore(value:0);writer.finishWriting {done.signal()}
        guard done.wait(timeout:.now()+60) == .success, writer.status == .completed else {throw writer.error ?? VideoFailure(message:L("视频编码未完成。", "Video encoding did not complete."))}
        try FileManager.default.moveItem(at:temp,to:final)
        print("VIDEO_OK \(timeline.pressCount) presses \(totalFrames) frames \(final.path)")
    }
}
