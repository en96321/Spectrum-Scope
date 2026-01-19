import Foundation
import CoreAudio
import ServiceManagement

class SettingsManager {
    static let shared = SettingsManager()
    
    private init() {}
    
    var visualizationMode: Int {
        get { UserDefaults.standard.integer(forKey: "visualizationMode") }
        set { UserDefaults.standard.set(newValue, forKey: "visualizationMode") }
    }
    
    var uiRefreshRate: Int {
        get { 
            let rate = UserDefaults.standard.integer(forKey: "uiRefreshRate")
            return rate == 0 ? 60 : rate
        }
        set { UserDefaults.standard.set(newValue, forKey: "uiRefreshRate") }
    }
    
    var isLosslessSwitcherEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "isLosslessSwitcherEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "isLosslessSwitcherEnabled") }
    }

    var isLaunchAtLoginEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "isLaunchAtLoginEnabled") }
        set { 
            UserDefaults.standard.set(newValue, forKey: "isLaunchAtLoginEnabled")
            // Logic to actually enable/disable launch at login should be handled here or by the caller
            if #available(macOS 13.0, *) {
                let service = SMAppService.mainApp
                do {
                    if newValue {
                        try service.register()
                    } else {
                        try service.unregister()
                    }
                } catch {
                    print("Failed to toggle launch at login: \(error)")
                }
            }
        }
    }
    
    var targetOutputDeviceID: AudioObjectID {
        get {
            let id = UserDefaults.standard.integer(forKey: "targetOutputDeviceID")
            return AudioObjectID(id)
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: "targetOutputDeviceID")
        }
    }
    
    var showSampleRateInStatusBar: Bool {
        get {
            return UserDefaults.standard.object(forKey: "showSampleRateInStatusBar") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showSampleRateInStatusBar")
        }
    }
}
