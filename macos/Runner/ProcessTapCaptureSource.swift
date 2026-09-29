import Foundation
import CoreAudio

/// 使用 Core Audio Process Tap（macOS 14.2+）擷取全系統音訊，不需要虛擬音訊驅動。
///
///   所有 App 的輸出 ──▶ Global Tap ──▶ Private Aggregate Device ──▶ IOProc ──▶ onBuffer
///                                        (時脈跟隨預設輸出裝置)
///
/// ⚠️ Global tap 回報的 kAudioTapPropertyFormat 固定是 48k，不會跟著裝置變。
/// 實際送進 IOProc 的資料會被 drift compensation 重新取樣到 aggregate 的時脈
/// （= 預設輸出裝置的 nominal rate），所以採樣率必須以 aggregate 為準。
final class ProcessTapCaptureSource: AudioCaptureSource {

    let name = "Process Tap"
    var onBuffer: ((_ buffers: [AudioBuffer], _ format: AudioStreamBasicDescription) -> Void)?
    var onInvalidated: (() -> Void)?

    private let ioQueue = DispatchQueue(label: "com.pedro.audio_scope.ProcessTapIO", qos: .userInteractive)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var listeners: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    deinit {
        stop()
    }

    func start() throws {
        do {
            let tapUID = try createTap()
            var format = try readTapFormat()
            try createAggregateDevice(tapUID: tapUID)
            let tapRate = format.mSampleRate
            format.mSampleRate = try readAggregateSampleRate()
            print("🎵 Tap format: \(format.mSampleRate)Hz (tap reports \(tapRate)Hz), \(format.mChannelsPerFrame)ch, \(format.mBitsPerChannel)bit")
            try startIO(format: format)
            installListeners()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        removeListeners()

        if aggregateID != kAudioObjectUnknown {
            if let procID = ioProcID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Setup

    private func createTap() throws -> String {
        // 本 App 不發聲，不需要排除任何 process
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Spectrum Scope Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        try AudioCaptureError.check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")
        return description.uuid.uuidString
    }

    private func readTapFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try AudioCaptureError.check(
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format),
            "Read kAudioTapPropertyFormat"
        )
        return format
    }

    private func readAggregateSampleRate() throws -> Float64 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        try AudioCaptureError.check(
            AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, &rate),
            "Read aggregate nominal sample rate"
        )
        return rate
    }

    private func createAggregateDevice(tapUID: String) throws {
        guard let outputID = AudioDeviceController.shared.getDefaultOutputDeviceID(),
              let outputUID = AudioDeviceController.shared.getDeviceUID(id: outputID) else {
            throw AudioCaptureError(operation: "Resolve default output device", status: kAudioHardwareBadDeviceError)
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Spectrum Scope Tap Device",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUID,
                ],
            ],
        ]

        try AudioCaptureError.check(
            AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID),
            "AudioHardwareCreateAggregateDevice"
        )
    }

    private func startIO(format: AudioStreamBasicDescription) throws {
        // Aggregate 的 input 會先列出 sub-device 自己的輸入（例如帶麥克風的音訊介面），
        // tap 的 buffer 排在最後，所以只取尾端屬於 tap 的那幾個。
        let isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let tapBufferCount = isNonInterleaved ? Int(format.mChannelsPerFrame) : 1

        try AudioCaptureError.check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { [weak self] _, inInputData, _, _, _ in
                guard let self, let onBuffer = self.onBuffer else { return }
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
                guard buffers.count >= tapBufferCount else { return }
                onBuffer(Array(buffers.suffix(tapBufferCount)), format)
            },
            "AudioDeviceCreateIOProcIDWithBlock"
        )
        // 首次呼叫時系統會跳出「系統音訊錄製」權限詢問（NSAudioCaptureUsageDescription）
        try AudioCaptureError.check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")
    }

    // MARK: - Change Listeners

    /// 輸出裝置採樣率（反映在 aggregate 上）或預設輸出裝置變更時，aggregate 需要重建
    private func installListeners() {
        addListener(object: aggregateID, selector: kAudioDevicePropertyNominalSampleRate)
        addListener(object: tapID, selector: kAudioTapPropertyFormat)
        addListener(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private func addListener(object: AudioObjectID, selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onInvalidated?()
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func removeListeners() {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.object, &address, DispatchQueue.main, listener.block)
        }
        listeners.removeAll()
    }
}
