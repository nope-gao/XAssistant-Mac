import AVFoundation
import AudioToolbox

enum ClickSound:String,CaseIterable,Identifiable {
    case keyboard,mechanical,soft,silent
    var id:String {rawValue}
    var title:String {
        switch self {
        case .keyboard:return L("键盘敲击","Keyboard taps")
        case .mechanical:return L("机械键盘","Mechanical")
        case .soft:return L("柔和敲击","Soft taps")
        case .silent:return L("静音","Silent")
        }
    }
}

// Deterministic synthesis from physical key IDs. No microphone or external audio assets.
final class KeyClickSynth {
    static let sampleRate=48_000
    let events:[(sample:Int,voice:String)]
    let preset:ClickSound
    private var cursor=0
    private var position=0
    private var voices:[(sound:[Float],offset:Int)]=[]
    private var cache:[String:[Float]]=[:]
    private(set) var triggered=0
    init(timeline:PlaybackTimeline,preset:ClickSound) {
        self.preset=preset
        events=timeline.events.filter { $0.source.down }.map {event in
            // Match the first video frame showing this press, including fast/chord groups.
            let frame=Int(ceil(max(0,event.time-0.00001)*Double(PlaybackTimeline.fps)))
            return (frame*Self.sampleRate/PlaybackTimeline.fps,event.source.kind+":"+event.source.key)
        }
    }
    static func waveform(key:String,preset:ClickSound) -> [Float] {
        guard preset != .silent else {return []}
        var seed:UInt64=14695981039346656037
        for byte in key.utf8 {seed=(seed ^ UInt64(byte)) &* 1099511628211}
        let hash=seed
        let seconds=preset == .mechanical ? 0.065:(preset == .soft ? 0.035:0.045)
        let frequency=Double(250+hash%1700)*(preset == .soft ? 0.55:1)
        let resonance=Double(1800+(hash>>12)%4000)
        let count=Int(seconds*Double(sampleRate))
        var filtered=0.0
        return (0..<count).map {index in
            seed=seed &* 6364136223846793005 &+ 1442695040888963407
            let noise=Double((seed>>32)&0xffff)/32767.5-1
            filtered=filtered*0.65+noise*0.35
            let t=Double(index)/Double(sampleRate)
            let attack=min(1,t/0.0008)
            let body=sin(2*Double.pi*frequency*t)*exp(-t/(seconds*0.17))
            let click=(noise-filtered)*exp(-t/(preset == .mechanical ? 0.008:0.0035))
            let ring=sin(2*Double.pi*resonance*t)*exp(-t/0.003)
            let level=preset == .soft ? 0.22:0.40
            let noiseLevel=preset == .soft ? 0.3:(preset == .mechanical ? 1.1:0.8)
            return Float(attack*level*(body*0.45+click*noiseLevel+ring*0.12))
        }
    }
    func samples(count:Int) -> [Float] {
        var output=[Float](repeating:0,count:count)
        guard preset != .silent else {position+=count;return output}
        while cursor<events.count && events[cursor].sample<position+count {
            let event=events[cursor]
            if cache[event.voice] == nil {cache[event.voice]=Self.waveform(key:event.voice,preset:preset)}
            voices.append((cache[event.voice]!,event.sample-position))
            cursor+=1;triggered+=1
        }
        var remaining:[(sound:[Float],offset:Int)]=[]
        for voice in voices {
            let lower=max(0,voice.offset),upper=min(count,voice.offset+voice.sound.count)
            if lower<upper {for index in lower..<upper {output[index]+=voice.sound[index-voice.offset]}}
            if voice.offset+voice.sound.count>count {remaining.append((voice.sound,voice.offset-count))}
        }
        voices=remaining;position+=count
        // Limit overlapping chords without discarding any presses.
        return output.map {Float(tanh(Double($0)))*0.85}
    }
}

final class ClickAudioTrack {
    let input:AVAssetWriterInput
    let synth:KeyClickSynth
    let done=DispatchSemaphore(value:0)
    private let queue=DispatchQueue(label:"XAssistant.audio",qos:.userInitiated)
    private let format:CMAudioFormatDescription
    private var written=0
    private let totalSamples:Int
    init(writer:AVAssetWriter,timeline:PlaybackTimeline,preset:ClickSound,totalFrames:Int) throws {
        synth=KeyClickSynth(timeline:timeline,preset:preset)
        totalSamples=totalFrames*KeyClickSynth.sampleRate/PlaybackTimeline.fps
        input=AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:KeyClickSynth.sampleRate,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:128_000])
        input.expectsMediaDataInRealTime=false
        var description=AudioStreamBasicDescription(mSampleRate:Double(KeyClickSynth.sampleRate),mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,mBytesPerPacket:4,mFramesPerPacket:1,mBytesPerFrame:4,mChannelsPerFrame:1,mBitsPerChannel:32,mReserved:0)
        var result:CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator:kCFAllocatorDefault,asbd:&description,layoutSize:0,layout:nil,magicCookieSize:0,magicCookie:nil,extensions:nil,formatDescriptionOut:&result)==noErr,let result,writer.canAdd(input) else {throw VideoFailure(message:L("无法编码音频。","Could not encode audio."))}
        format=result;writer.add(input)
    }
    func start(writer:AVAssetWriter) {
        input.requestMediaDataWhenReady(on:queue) { [self] in
            while input.isReadyForMoreMediaData {
                if written>=totalSamples {input.markAsFinished();done.signal();return}
                do {
                    let count=min(2048,totalSamples-written)
                    let values=synth.samples(count:count)
                    let sample=try Self.buffer(values,at:written,format:format)
                    guard input.append(sample) else {throw VideoFailure(message:L("无法编码音频。","Could not encode audio."))}
                    written+=count
                } catch {input.markAsFinished();writer.cancelWriting();done.signal();return}
            }
        }
    }
    static func buffer(_ samples:[Float],at offset:Int,format:CMAudioFormatDescription) throws -> CMSampleBuffer {
        let bytes=samples.count*MemoryLayout<Float>.size
        var block:CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:bytes,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:bytes,flags:0,blockBufferOut:&block)==kCMBlockBufferNoErr,let block else {throw VideoFailure(message:L("无法编码音频。","Could not encode audio."))}
        let copied=samples.withUnsafeBytes {CMBlockBufferReplaceDataBytes(with:$0.baseAddress!,blockBuffer:block,offsetIntoDestination:0,dataLength:bytes)}
        var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:Int32(KeyClickSynth.sampleRate)),presentationTimeStamp:CMTime(value:Int64(offset),timescale:Int32(KeyClickSynth.sampleRate)),decodeTimeStamp:.invalid)
        var size=4
        var buffer:CMSampleBuffer?
        guard copied==kCMBlockBufferNoErr,CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:samples.count,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&buffer)==noErr,let buffer else {throw VideoFailure(message:L("无法编码音频。","Could not encode audio."))}
        return buffer
    }
}

// Hardware encoder verification used before publishing a release. No user data is read.
func verifyClickEncoding() throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("XAssistant-media-test-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:folder)}
var events:[InputEvent]=[]
for (i,key) in ["4","22","7","9","44","40","225","4"].enumerated() {
    let t=100+Double(i)*0.4
    events += [InputEvent(t:t,device:"test",kind:"key",key:key,down:true),InputEvent(t:t+0.08,device:"test",kind:"key",key:key,down:false)]
}
for preset in ClickSound.allCases where preset != .silent {
    let timeline=PlaybackTimeline(events:events,start:99,end:104,speed:1)
    let url=folder.appendingPathComponent(preset.rawValue+".mp4")
    try? FileManager.default.removeItem(at:url)
    let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
    let video=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:64])
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:video,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:64])
    writer.add(video)
    let frames=timeline.frameCount+150
    let audio=try ClickAudioTrack(writer:writer,timeline:timeline,preset:preset,totalFrames:frames)
    precondition(writer.startWriting());writer.startSession(atSourceTime:.zero);audio.start(writer:writer)
    for frame in 0..<frames {
        var buffer:CVPixelBuffer?
        precondition(CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)==kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(buffer!,[]);memset(CVPixelBufferGetBaseAddress(buffer!),0,CVPixelBufferGetBytesPerRow(buffer!)*64);CVPixelBufferUnlockBaseAddress(buffer!,[])
        let timeout=Date().addingTimeInterval(15)
        while !video.isReadyForMoreMediaData {precondition(writer.status == .writing && Date()<timeout,"writer stalled: \(String(describing:writer.error))");Thread.sleep(forTimeInterval:0.005)}
        precondition(adaptor.append(buffer!,withPresentationTime:CMTime(value:Int64(frame),timescale:30)))
    }
    video.markAsFinished();precondition(audio.done.wait(timeout:.now()+20) == .success)
    writer.endSession(atSourceTime:CMTime(value:Int64(frames),timescale:30))
    let done=DispatchSemaphore(value:0);writer.finishWriting {done.signal()}
    precondition(done.wait(timeout:.now()+20) == .success && writer.status == .completed,"\(String(describing:writer.error))")
    let asset=AVURLAsset(url:url)
    precondition(asset.tracks(withMediaType:.audio).count == 1 && asset.tracks(withMediaType:.video).count == 1)
    precondition(abs(asset.duration.seconds-Double(frames)/30)<0.04)
    precondition(audio.synth.triggered == timeline.pressCount)
    let reader=try AVAssetReader(asset:asset)
    let output=AVAssetReaderTrackOutput(track:asset.tracks(withMediaType:.audio)[0],outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
    reader.add(output);precondition(reader.startReading())
    var peak:Float=0
    while let sample=output.copyNextSampleBuffer(),let block=CMSampleBufferGetDataBuffer(sample) {
        let length=CMBlockBufferGetDataLength(block)
        var values=[Float](repeating:0,count:length/4)
        let result=values.withUnsafeMutableBytes {CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:$0.baseAddress!)}
        precondition(result==kCMBlockBufferNoErr)
        peak=max(peak,values.map {abs($0)}.max() ?? 0)
    }
    precondition(reader.status == .completed && peak>0.001 && peak<=1)
    print("PASS: \(preset.rawValue), \(audio.synth.triggered) clicks, \(frames) synchronized audio/video frames")
}

}
