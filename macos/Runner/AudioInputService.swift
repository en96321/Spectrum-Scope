import Foundation
import ScreenCaptureKit
import CoreMedia
@preconcurrency import AVFoundation

protocol AudioInputDelegate: AnyObject {
    func audioInputDidReceiveBuffer(_ buffer: [Float], sampleRate: Float64, channels: Int, bitDepth: Int)
}

class AudioInputService: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    weak var delegate: AudioInputDelegate?
    
    private var captureSession: AVCaptureSession?
    private var isUsingBlackHole = false
    private var stream: SCStream?
    private let videoSampleBufferQueue = DispatchQueue(label: "com.pedro.audio_scope.VideoSampleBufferQueue")
    
    private(set) var isRunning = false
    private(set) var currentSampleRate: Float64 = 48000
    private var lastFormatSampleRate: Float64 = 0
    private var hasLoggedFormat = false
    
    override init() {
        super.init()
    }
    
    func startCapture() async {
        stopCapture()
        
        if let blackHoleDevice = findBlackHoleDevice() {
            print("✅ Found BlackHole: \(blackHoleDevice.localizedName)")
            startCoreAudioCapture(device: blackHoleDevice)
            return
        }
        
        print("⚠️ BlackHole not found, falling back to ScreenCaptureKit")
        await startScreenCapture()
    }
    
    func stopCapture() {
        if isUsingBlackHole {
            if let session = captureSession {
                NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
                NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: session)
                NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
                session.stopRunning()
            }
            captureSession = nil
        } else {
            if let stream = stream {
                stream.stopCapture { error in 
                    if let error = error { print("❌ Error stopping capture: \(error)") }
                }
            }
            stream = nil
        }
        isRunning = false
        print("🛑 Capture stopped")
    }
    
    private func findBlackHoleDevice() -> AVCaptureDevice? {
        // macOS 14+ replacement
        let discoverySession: AVCaptureDevice.DiscoverySession
        if #available(macOS 14.0, *) {
            discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            )
        } else {
            discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInMicrophone, .externalUnknown],
                mediaType: .audio,
                position: .unspecified
            )
        }
        
        for device in discoverySession.devices {
            if device.localizedName.contains("BlackHole") { return device }
        }
        return nil
    }
    
    private func startCoreAudioCapture(device: AVCaptureDevice) {
        let session = AVCaptureSession()
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            else { print("❌ Cannot add BlackHole input"); return }
            
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: videoSampleBufferQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
            else { print("❌ Cannot add audio output"); return }
            
            session.commitConfiguration()
            
            // Add Observers for Runtime Errors (e.g. Sample Rate Change)
            NotificationCenter.default.addObserver(self, selector: #selector(handleCaptureSessionError), name: .AVCaptureSessionRuntimeError, object: session)
            NotificationCenter.default.addObserver(self, selector: #selector(handleCaptureSessionInterruption), name: .AVCaptureSessionWasInterrupted, object: session)
            NotificationCenter.default.addObserver(self, selector: #selector(handleCaptureSessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
            
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                self.isRunning = true
                self.isUsingBlackHole = true
                print("✅ CoreAudio Capture Started (BlackHole)")
            }
            self.captureSession = session
        } catch {
            print("❌ Failed to create capture input: \(error)")
        }
    }
    
    @objc private func handleCaptureSessionError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print("⚠️ AVCaptureSession Runtime Error: \(error.localizedDescription) (Code: \(error.code.rawValue))")
        
        // Auto-restart mechanism for any runtime error (e.g. device format change)
        print("♻️ Runtime Error - scheduling restart...")
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1s
            
            guard let session = notification.object as? AVCaptureSession else { return }
            if !session.isRunning {
                print("♻️ Attempting to restart AVCaptureSession...")
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        }
    }
    
    @objc private func handleCaptureSessionInterruption(_ notification: Notification) {
        print("⚠️ AVCaptureSession Interrupted")
    }
    
    @objc private func handleCaptureSessionInterruptionEnded(_ notification: Notification) {
        print("✅ AVCaptureSession Interruption Ended - Resuming...")
        guard let session = notification.object as? AVCaptureSession else { return }
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processSampleBuffer(sampleBuffer)
    }
    
    private func startScreenCapture() async {
        do {
            // macOS 14+ replacement
            // Note: For older macOS support we might need #available check but let's assume macOS 12+ for SCKit
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 2; config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.capturesAudio = true; config.excludesCurrentProcessAudio = true; config.channelCount = 2
            config.sampleRate = 48000
            
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: videoSampleBufferQueue)
            try await stream?.startCapture()
            isRunning = true; isUsingBlackHole = false
            print("✅ ScreenCaptureKit Audio Capture Started")
        } catch { print("❌ SCKit Error: \(error)") }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        processSampleBuffer(sampleBuffer)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ SCKit Stream stopped: \(error)")
        isRunning = false
    }
    
    // MARK: - Robust Sample Buffer Processing

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // 1. Get ASBD
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)!.pointee
        self.currentSampleRate = asbd.mSampleRate
        
        // Debug Log on Format Change
        if asbd.mSampleRate != lastFormatSampleRate {
            lastFormatSampleRate = asbd.mSampleRate
            let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            print("🎵 Format: \(asbd.mSampleRate)Hz, \(asbd.mChannelsPerFrame)ch, Float:\(isFloat), NonInterleaved:\(isNonInterleaved)")
        }

        // 2. Use AudioBufferList to handle Interleaved/Non-Interleaved automatically
        var blockBuffer: CMBlockBuffer?
        
        let listSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size * (Int(asbd.mChannelsPerFrame) - 1)
        let bufferListStorage = UnsafeMutableRawBufferPointer.allocate(byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListStorage.deallocate() }
        
        let audioBufferListPtr = bufferListStorage.bindMemory(to: AudioBufferList.self)
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPtr.baseAddress!,
            bufferListSize: listSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else {
            print("❌ Failed to get AudioBufferList: \(status)")
            return
        }
        
        // 3. Extract and Mix Samples
        let bufferCount = Int(audioBufferListPtr.baseAddress!.pointee.mNumberBuffers)
        let channels = Int(asbd.mChannelsPerFrame)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        var floatSamples: [Float] = []
        
        // Use withUnsafePointer to avoid dangling pointer warnings
        withUnsafePointer(to: &audioBufferListPtr.baseAddress!.pointee.mBuffers) { buffersPtr in
            let buffers = UnsafeBufferPointer(start: buffersPtr, count: bufferCount)
            
            guard let firstBuffer = buffers.first, let _ = firstBuffer.mData else { return }
            let frameCount = Int(firstBuffer.mDataByteSize) / (isFloat ? 4 : 2)
            
            if frameCount == 0 { return }
            
            // Initialize with zeroes
            floatSamples = [Float](repeating: 0, count: frameCount)
            
            for i in 0..<buffers.count {
                let buffer = buffers[i]
                guard let data = buffer.mData else { continue }
                
                if isFloat {
                    // Float32
                    let ptr = data.bindMemory(to: Float.self, capacity: frameCount)
                    for j in 0..<frameCount {
                        floatSamples[j] += ptr[j]
                    }
                } else {
                    // Int16
                    let ptr = data.bindMemory(to: Int16.self, capacity: frameCount)
                    for j in 0..<frameCount {
                        floatSamples[j] += Float(ptr[j]) / Float(Int16.max)
                    }
                }
            }
            
            // Average the mix
            if buffers.count > 0 {
                let div = Float(buffers.count)
                for j in 0..<frameCount {
                    floatSamples[j] /= div
                }
            }
        } // End withUnsafePointer
        
        if floatSamples.isEmpty { return }

        // 4. Debug Check (Silence Detection)
        if Int.random(in: 0...50) == 0 {
            var maxVal: Float = 0
            for s in floatSamples { if abs(s) > maxVal { maxVal = abs(s) } }
            // Debug print if needed
        }
        
        delegate?.audioInputDidReceiveBuffer(floatSamples, sampleRate: asbd.mSampleRate, channels: channels, bitDepth: 32)
    }
}
