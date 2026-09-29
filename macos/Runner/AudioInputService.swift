import Foundation
import CoreAudio
import Accelerate

protocol AudioInputDelegate: AnyObject {
    func audioInputDidReceiveBuffer(_ buffer: [Float], sampleRate: Float64, channels: Int, bitDepth: Int)
}

/// 音訊擷取來源的共同介面。
/// `onBuffer` 收到的 AudioBuffer 只在 callback 期間有效，不可保留指標。
protocol AudioCaptureSource: AnyObject {
    var name: String { get }
    var onBuffer: ((_ buffers: [AudioBuffer], _ format: AudioStreamBasicDescription) -> Void)? { get set }
    /// 來源失效（格式/裝置變更、runtime error）時通知，由協調者決定是否重建
    var onInvalidated: (() -> Void)? { get set }
    func start() throws
    func stop()
}

struct AudioCaptureError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String { "\(operation) failed (OSStatus \(status))" }

    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioCaptureError(operation: operation, status: status) }
    }
}

/// 協調者：依優先序挑選可用的擷取來源，並把 PCM 混成 mono 交給 delegate。
///   1. Core Audio Process Tap（macOS 14.2+，不需虛擬驅動）
///   2. BlackHole（已安裝時的備援）
final class AudioInputService {

    weak var delegate: AudioInputDelegate?

    private(set) var isRunning = false
    private(set) var activeSourceName: String?

    private var source: AudioCaptureSource?
    private var pendingRestart: DispatchWorkItem?

    /// 各來源每次 callback 的 frame 數不同（Process Tap 約 512），
    /// 累積成固定長度的滑動視窗，讓 FFT (2048 點) 永遠拿到完整資料
    private let analysisWindowSize = 2048
    private var analysisWindow: [Float] = []
    private let sourceFactories: [() -> AudioCaptureSource] = [
        { ProcessTapCaptureSource() },
        { BlackHoleCaptureSource() },
    ]

    func startCapture() {
        stopCapture()
        analysisWindow.removeAll(keepingCapacity: true)

        for makeSource in sourceFactories {
            let candidate = makeSource()
            candidate.onBuffer = { [weak self] buffers, format in
                self?.handle(buffers: buffers, format: format)
            }
            candidate.onInvalidated = { [weak self] in
                print("♻️ \(candidate.name) invalidated - scheduling restart...")
                self?.restartCapture()
            }

            do {
                try candidate.start()
                source = candidate
                activeSourceName = candidate.name
                isRunning = true
                print("✅ Audio capture started via \(candidate.name)")
                return
            } catch {
                print("⚠️ \(candidate.name) unavailable: \(error)")
            }
        }

        print("❌ No audio capture source available")
    }

    func stopCapture() {
        pendingRestart?.cancel()
        pendingRestart = nil
        source?.stop()
        source = nil
        activeSourceName = nil
        isRunning = false
    }

    /// 合併短時間內的多次重啟請求（例如採樣率切換同時觸發格式與裝置變更）
    func restartCapture(after delay: TimeInterval = 0.5) {
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startCapture() }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func handle(buffers: [AudioBuffer], format: AudioStreamBasicDescription) {
        let samples = AudioBufferMixer.mixToMono(buffers, format: format)
        guard !samples.isEmpty else { return }

        analysisWindow.append(contentsOf: samples)
        if analysisWindow.count > analysisWindowSize {
            analysisWindow.removeFirst(analysisWindow.count - analysisWindowSize)
        }

        delegate?.audioInputDidReceiveBuffer(
            analysisWindow,
            sampleRate: format.mSampleRate,
            channels: Int(format.mChannelsPerFrame),
            bitDepth: Int(format.mBitsPerChannel)
        )
    }
}

/// 將 Float32 / Int16 的 interleaved 或 non-interleaved PCM 平均混成 mono。
enum AudioBufferMixer {

    static func mixToMono(_ buffers: [AudioBuffer], format: AudioStreamBasicDescription) -> [Float] {
        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bytesPerSample = Int(format.mBitsPerChannel) / 8

        guard (isFloat && bytesPerSample == 4) || (!isFloat && bytesPerSample == 2),
              let first = buffers.first else { return [] }

        // 每個 buffer 內的聲道數：non-interleaved 為 1，interleaved 為 buffer 自帶的 mNumberChannels
        let channelsPerBuffer = isNonInterleaved ? 1 : max(Int(first.mNumberChannels), 1)
        let frameCount = Int(first.mDataByteSize) / (bytesPerSample * channelsPerBuffer)
        guard frameCount > 0 else { return [] }

        var mono = [Float](repeating: 0, count: frameCount)
        var scratch = [Float](repeating: 0, count: frameCount)
        var mixedChannels = 0

        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let stride = isNonInterleaved ? 1 : max(Int(buffer.mNumberChannels), 1)
            guard Int(buffer.mDataByteSize) >= frameCount * stride * bytesPerSample else { continue }

            for channel in 0..<stride {
                if isFloat {
                    let ptr = data.assumingMemoryBound(to: Float.self) + channel
                    vDSP_vadd(mono, 1, ptr, vDSP_Stride(stride), &mono, 1, vDSP_Length(frameCount))
                } else {
                    let ptr = data.assumingMemoryBound(to: Int16.self) + channel
                    vDSP_vflt16(ptr, vDSP_Stride(stride), &scratch, 1, vDSP_Length(frameCount))
                    var scale = 1.0 / Float(Int16.max)
                    vDSP_vsmul(scratch, 1, &scale, &scratch, 1, vDSP_Length(frameCount))
                    vDSP_vadd(mono, 1, scratch, 1, &mono, 1, vDSP_Length(frameCount))
                }
                mixedChannels += 1
            }
        }

        guard mixedChannels > 0 else { return [] }
        var divisor = Float(mixedChannels)
        vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(frameCount))
        return mono
    }
}
