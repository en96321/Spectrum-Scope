import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @State private var hasBlackHole = false
    @State private var hasMicPermission = false
    @State private var hasAutomationPermission = false
    @State private var currentStep = 0
    
    var onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Text("歡迎使用 Audio Scope")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Step 1: BlackHole Check
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: hasBlackHole ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(hasBlackHole ? .green : .gray)
                    Text("1. 檢查 BlackHole 驅動")
                        .font(.headline)
                }
                
                if !hasBlackHole {
                    Text("未偵測到 BlackHole。這是實現高音質自動切換的必要組件。")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text("請在終端機執行：")
                        .font(.caption)
                    Text("brew install blackhole-2ch")
                        .font(.system(.caption, design: .monospaced))
                        .padding(5)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(5)
                    
                    Button("重新檢查") {
                        checkBlackHole()
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            
            // Step 2: Permissions
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: hasMicPermission ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(hasMicPermission ? .green : .gray)
                    Text("2. 授予錄音權限")
                        .font(.headline)
                }
                
                if !hasMicPermission {
                    Button("請求權限") {
                        requestMicPermission()
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            
            Spacer()
            
            Button(action: onFinish) {
                Text("開始使用")
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasBlackHole || !hasMicPermission)
        }
        .padding(40)
        .frame(width: 500, height: 600)
        .onAppear {
            checkBlackHole()
            checkMicPermission()
        }
    }
    
    func checkBlackHole() {
        let path2ch = "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
        let path16ch = "/Library/Audio/Plug-Ins/HAL/BlackHole16ch.driver"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path2ch) || fileManager.fileExists(atPath: path16ch) {
            hasBlackHole = true
        } else {
            hasBlackHole = false
        }
    }
    
    func checkMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicPermission = true
        default:
            hasMicPermission = false
        }
    }
    
    func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                hasMicPermission = granted
            }
        }
    }
}
