# Spectrum Scope

**Spectrum Scope** 是一款專為 macOS 設計的原生高解析音訊視覺化工具 (High-Res Audio Visualizer)。

除了精美的頻譜分析外，最核心的功能是 **Lossless Switcher**，能夠偵測 Apple Music 的採樣率變化，並自動同步系統音訊設定，確保 Bit-Perfect 的聆聽體驗。

![App Icon](macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png)

## 🚀 主要功能

*   **Lossless Switcher**：
    *   自動偵測 Apple Music 播放的音樂採樣率 (44.1kHz ~ 192kHz)。
    *   自動將 **BlackHole** 及**DAC (外部輸出裝置)** 切換至對應採樣率，避免系統強制 SRC (Sample Rate Conversion) 造成的音質減損。
*   **專業頻譜分析**：
    *   即時 FFT 分析，支援 Logarithmic 頻率顯示。
    *   多種視覺化模式 (包含波形圖、頻譜圖)。
*   **貼心設定**：
    *   記憶您的視窗模式與 UI 更新率 (FPS)。
    *   支援開機自動啟動 (Launch at Login)。
*   **隱私友善**：因為需要監聽blackhole，所以會在左上角清楚的出現麥克風使用狀態指示 (Privacy Indicator)。

## 🛠️ 安裝前準備 (Prerequisites)

Spectrum Scope 需要依賴虛擬音訊驅動來擷取系統聲音。

### 1. 安裝 BlackHole (必要)

本專案使用 **BlackHole 2ch** 作為音訊擷取的中介。請打開終端機 (Terminal) 並執行以下指令安裝：

```bash
brew install blackhole-2ch
```

安裝完成後，您可能需要重新啟動電腦或音訊核心 (`sudo launchctl kickstart -k system/com.apple.audio.coreaudiod`)。

### 2. (選用) 設定多重輸出裝置

雖然 Spectrum Scope 會自動切換裝置，但為了在聽音樂的同時進行視覺化，建議您在「音訊 MIDI 設定」中建立一個「多重輸出裝置」，同時包含您的 DAC 和 BlackHole。

## 📦 如何編譯與執行

本專案已經內建自動化編譯腳本，無需打開 Xcode 即可編譯。

1.  **下載專案**
2.  **執行編譯腳本**：

    ```bash
    ./run_native.sh
    ```

    這個腳本會：
    *   清理舊的編譯檔案。
    *   使用 `xcodebuild` 編譯原生 Swift 專案。
    *   將輸出的 App 自動更名為 `Spectrum Scope.app`。
    *   自動啟動 App。

## 🎨 App Icon 設定

專案內建了圖示生成腳本。如果您想更換 App Icon，請準備一張 1024x1024 的圖片，命名為 `icon_original.png` (或修改腳本內路徑)，然後執行：

```bash
./generate_icons.sh
```

這將會自動生成所有 iOS/macOS 所需尺寸的 icon 並放入 `Assets.xcassets`。

## 📂 專案結構

此專案為標準 Xcode 專案結構：
*   `macos/`: 包含所有 Swift 原始碼與 Xcode 專案檔 (`Runner.xcodeproj`)。
    *   `Runner/`: 主要程式碼 (AppDelegate, Views, Services)。
    *   `Configs/`: 編譯設定檔 (xcconfig)。
*   `run_native.sh`: 一鍵編譯與執行腳本。

## Acknowledgements

Special thanks to [vincentneo](https://github.com/vincentneo) for the [LosslessSwitcher](https://github.com/vincentneo/LosslessSwitcher) project, which provided the core inspiration for our automatic sample rate switching logic.

---
Developed with ❤️ by **Pedro.Yang**.
