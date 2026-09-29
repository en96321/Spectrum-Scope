import Foundation
import CoreMedia
@preconcurrency import AVFoundation

/// 備援來源：從 BlackHole 虛擬裝置錄音（需使用者自行建立含 BlackHole 的多重輸出裝置）。
final class BlackHoleCaptureSource: NSObject, AudioCaptureSource, AVCaptureAudioDataOutputSampleBufferDelegate {

    let name = "BlackHole"
    var onBuffer: ((_ buffers: [AudioBuffer], _ format: AudioStreamBasicDescription) -> Void)?
    var onInvalidated: (() -> Void)?

    private var captureSession: AVCaptureSession?
    private let sampleBufferQueue = DispatchQueue(label: "com.pedro.audio_scope.BlackHoleSampleBufferQueue")

    func start() throws {
        guard let device = findBlackHoleDevice() else {
            throw AudioCaptureError(operation: "Find BlackHole device", status: kAudioHardwareBadDeviceError)
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw AudioCaptureError(operation: "Add BlackHole input", status: kAudioHardwareIllegalOperationError)
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        guard session.canAddOutput(output) else {
            throw AudioCaptureError(operation: "Add audio output", status: kAudioHardwareIllegalOperationError)
        }
        session.addOutput(output)

        session.commitConfiguration()

        // 例如採樣率變更會觸發 runtime error，交給協調者重建
        NotificationCenter.default.addObserver(self, selector: #selector(handleRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func stop() {
        guard let session = captureSession else { return }
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
        session.stopRunning()
        captureSession = nil
    }

    private func findBlackHoleDevice() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices.first { $0.localizedName.contains("BlackHole") }
    }

    @objc private func handleRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
            print("⚠️ AVCaptureSession Runtime Error: \(error.localizedDescription) (Code: \(error.code.rawValue))")
        }
        DispatchQueue.main.async { self.onInvalidated?() }
    }

    @objc private func handleInterruptionEnded(_ notification: Notification) {
        guard let session = notification.object as? AVCaptureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let onBuffer,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else { return }

        var bufferListSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &bufferListSize, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil
        )
        guard bufferListSize > 0 else { return }

        let storage = UnsafeMutableRawPointer.allocate(byteCount: bufferListSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let bufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: bufferList, bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            print("❌ Failed to get AudioBufferList: \(status)")
            return
        }

        // blockBuffer 持有資料直到離開此 scope，onBuffer 為同步呼叫
        withExtendedLifetime(blockBuffer) {
            onBuffer(Array(UnsafeMutableAudioBufferListPointer(bufferList)), asbd)
        }
    }
}
