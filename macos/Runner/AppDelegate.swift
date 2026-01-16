import Cocoa
import SwiftUI
import CoreAudio

import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate, AudioInputDelegate {
    
    // UI Components
    var statusItem: NSStatusItem!
    var menuBarSpectrumView: MenuBarSpectrumView!
    var popover: NSPopover!
    var popoverView: FullPopoverView!
    var eventMonitor: Any?
    var onboardingWindow: NSWindow?
    
    // Logic Components
    let audioInput = AudioInputService()
    let spectrumAnalyzer = SpectrumAnalyzer()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("🚀 Audio Scope (Swift) Launched")
        
        // 1. 初始化 UI
        setupStatusItem()
        setupPopover()
        
        // 2. 設定委派
        audioInput.delegate = self
        
        // 3. 啟動 Lossless Switcher (Log Monitor)
        // 當偵測到 Apple Music 採樣率變化時，自動切換系統設備
        LogMonitor.shared.onSampleRateDetected = { [weak self] rate in
            self?.handleSampleRateChange(rate)
        }
        // 嘗試啟動監聽 (需要非沙盒環境)
        LogMonitor.shared.startMonitoring()
        
        // 4. 檢查是否需要新手引導
        checkOnboarding()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        audioInput.stopCapture()
        LogMonitor.shared.stopMonitoring()
    }
    
    // MARK: - Onboarding Logic
    
    private func checkOnboarding() {
        // 檢查 BlackHole 驅動是否存在
        if AudioDeviceController.shared.findDevice(byName: "BlackHole") != nil {
            // ✅ BlackHole 存在，正常啟動
            UserDefaults.standard.set(true, forKey: "OnboardingCompleted")
            startAudioCapture()
        } else {
            // ❌ BlackHole 缺失，跳出警告
            showMissingBlackHoleAlert()
        }
    }
    
    private func showMissingBlackHoleAlert() {
        let alert = NSAlert()
        alert.messageText = "未偵測到 BlackHole 驅動"
        alert.informativeText = "Audio Scope 需要 BlackHole 虛擬音訊驅動才能正常運作。\n\n請打開終端機並執行以下指令安裝：\nbrew install blackhole-2ch\n\n安裝完成後請重新啟動本程式。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "結束 App")
        
        // 顯示 Alert (Modal)
        alert.runModal()
        
        // 用戶點擊結束後，關閉程式
        NSApp.terminate(nil)
    }

    private func showOnboarding() {
        // 創建 SwiftUI 視圖
        let onboardingView = OnboardingView { [weak self] in
            // 完成回調
            UserDefaults.standard.set(true, forKey: "OnboardingCompleted")
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.startAudioCapture()
        }
        
        // 創建視窗
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Audio Scope 設定"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.isReleasedWhenClosed = false
        
        self.onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func startAudioCapture() {
        Task {
            await audioInput.startCapture()
        }
    }
    
    // MARK: - Lossless Switcher Logic
    
    private func handleSampleRateChange(_ rate: Int) {
        // 0. 檢查功能是否開啟
        guard SettingsManager.shared.isLosslessSwitcherEnabled else {
            print("🛑 Lossless Switcher is DISABLED in settings.")
            return
        }
    
        print("🔄 Lossless Switcher: Switching to \(rate) Hz")
        
        // 1. 查找 BlackHole 設備 (必選，因為我們要錄音)
        if let blackHoleID = AudioDeviceController.shared.findDevice(byName: "BlackHole") {
            _ = AudioDeviceController.shared.setSampleRate(deviceID: blackHoleID, rate: Float64(rate))
        }
        
        // 2. 設定目標輸出設備 (用戶設定 或 預設)
        let targetID = SettingsManager.shared.targetOutputDeviceID
        if targetID != 0 {
            // 用戶指定了設備
            print("🎛️ Setting Custom Target Device \(targetID) to \(rate) Hz")
            _ = AudioDeviceController.shared.setSampleRate(deviceID: AudioObjectID(targetID), rate: Float64(rate))
        } else {
            // 跟隨系統預設輸出
            if let defaultID = AudioDeviceController.shared.getDefaultOutputDeviceID() {
                print("🔈 Setting System Default Device \(defaultID) to \(rate) Hz")
                _ = AudioDeviceController.shared.setSampleRate(deviceID: defaultID, rate: Float64(rate))
            }
        }
        
        // 3. 重啟音訊捕獲以應用新的採樣率
        print("♻️ Restarting Capture to apply \(rate) Hz...")
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await audioInput.startCapture()
        }
    }
    
    // Rate Limiting
    private var lastUpdateTime: TimeInterval = 0
    private var updateInterval: TimeInterval {
        return 1.0 / Double(SettingsManager.shared.uiRefreshRate)
    }
    
    // MARK: - AudioInputDelegate
    
    func audioInputDidReceiveBuffer(_ buffer: [Float], sampleRate: Float64, channels: Int, bitDepth: Int) {
        // Throttling: Limit update rate to save CPU and reduce jitter
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastUpdateTime >= updateInterval else { return }
        lastUpdateTime = currentTime
        
        // 1. FFT 處理
        let spectrum = spectrumAnalyzer.process(audioData: buffer, sampleRate: sampleRate)
        
        // 2. 計算音量
        let volumeDb = spectrumAnalyzer.calculateVolumeDb(buffer)
        let peakDb = spectrumAnalyzer.calculatePeakDb(buffer)
        
        // 3. 更新 UI (主執行緒)
        DispatchQueue.main.async { [weak self] in
            // 更新 Menu Bar
            self?.menuBarSpectrumView?.updateSpectrum(spectrum)
            
            // 更新 Popover
            if let popoverView = self?.popoverView {
                popoverView.updateSpectrum(spectrum)
                popoverView.updateMetrics(volumeDb: volumeDb, peakDb: peakDb)
                popoverView.updateAudioInfo(sampleRate: sampleRate, bitDepth: bitDepth, channels: channels)
            }
        }
    }
    
    // MARK: - UI Setup (Copied & Adapted)
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 36)
        statusItem.behavior = .removalAllowed
        
        if let button = statusItem.button {
            menuBarSpectrumView = MenuBarSpectrumView(frame: NSRect(x: 0, y: 4, width: 30, height: 14))
            if let view = menuBarSpectrumView {
                button.addSubview(view)
            }
            
            button.action = #selector(togglePopover)
            button.target = self
        }
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        
        let viewController = NSViewController()
        let popoverSize = NSSize(width: 320, height: 460)
        popoverView = FullPopoverView(frame: NSRect(origin: .zero, size: popoverSize))
        
        popoverView.onQuit = {
            NSApp.terminate(nil)
        }
        
        popoverView.onModeChanged = { [weak self] mode in
            self?.menuBarSpectrumView?.mode = mode 
            // 在這裡可以保留 MenuBar 簡潔模式，或者同步
        }
        
        viewController.view = popoverView
        popover.contentViewController = viewController
        popover.contentSize = popoverSize
    }
    
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover(sender: nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            showPopover(button: button)
        }
    }
    
    private func showPopover(button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, strongSelf.popover.isShown {
                strongSelf.closePopover(sender: event)
            }
        }
    }
    
    private func closePopover(sender: Any?) {
        popover.performClose(sender)
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
