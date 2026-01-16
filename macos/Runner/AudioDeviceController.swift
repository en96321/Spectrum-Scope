import Foundation
import CoreAudio

class AudioDeviceController {
    static let shared = AudioDeviceController()
    
    // 獲取默認輸出設備 ID
    func getDefaultOutputDeviceID() -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        return result == kAudioHardwareNoError ? deviceID : nil
    }
    
    func getAllOutputDevices() -> [(ID: AudioObjectID, Name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        
        let deviceCount = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        
        var devices: [(AudioObjectID, String)] = []
        for id in deviceIDs {
            var outputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var outputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &outputAddress, 0, nil, &outputSize) == noErr else { continue }
            
            if outputSize > 0 {
                if let name = getDeviceName(id: id) {
                    devices.append((id, name))
                }
            }
        }
        return devices
    }
    
    // 根據名稱查找設備 (用於 BlackHole)
    func findDevice(byName name: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        
        let deviceCount = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        
        for id in deviceIDs {
            if let deviceName = getDeviceName(id: id) {
                if deviceName.contains(name) {
                    return id
                }
            }
        }
        
        return nil
    }
    
    // 讀取採樣率
    func getSampleRate(deviceID: AudioObjectID) -> Float64 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRate: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        
        let result = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &sampleRate
        )
        
        return result == kAudioHardwareNoError ? sampleRate : 0
    }
    
    // 設定採樣率
    func setSampleRate(deviceID: AudioObjectID, rate: Float64) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // 檢查是否支持該採樣率
        if !isSampleRateSupported(deviceID: deviceID, rate: rate) {
            print("⚠️ Device \(deviceID) does not support sample rate \(rate)")
            return false
        }
        
        var newRate = rate
        let dataSize = UInt32(MemoryLayout<Float64>.size)
        
        let result = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &newRate
        )
        
        if result == kAudioHardwareNoError {
            print("✅ Successfully set device \(deviceID) sample rate to \(rate)")
            return true
        } else {
            print("❌ Failed to set sample rate: \(result)")
            return false
        }
    }
    
    // 檢查採樣率支持
    private func isSampleRateSupported(deviceID: AudioObjectID, rate: Float64) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == kAudioHardwareNoError else { return false }
        
        let count = Int(dataSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &ranges)
        guard status == kAudioHardwareNoError else { return false }
        
        for range in ranges {
            if rate >= range.mMinimum && rate <= range.mMaximum {
                return true
            }
        }
        
        return false
    }
    private func getDeviceName(id: AudioObjectID) -> String? {
        var deviceName: CFString = "" as CFString
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        // Fix warning: forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'
        var status = noErr
        withUnsafeMutablePointer(to: &deviceName) { ptr in
            status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, ptr)
        }
        
        return status == kAudioHardwareNoError ? (deviceName as String) : nil
    }
}
