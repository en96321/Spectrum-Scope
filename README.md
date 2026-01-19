# Spectrum Scope

<img width="256" height="256" alt="Icon" src="https://github.com/user-attachments/assets/bb106a19-74f9-4577-a376-43f914a7697a" />

[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat)](https://github.com/vincentneo/LosslessSwitcher)
[![Language](https://img.shields.io/badge/language-Swift-orange.svg)]()
[![Version](https://img.shields.io/badge/version-1.0.1-blue.svg)]()

[**中文**](#中文) | [**English**](#english)

---

<a id="中文"></a>
# Spectrum Scope (中文)

**Spectrum Scope** 是一款專為 macOS 設計的原生 (Native Swift) 高解析音訊視覺化工具。

它不僅提供精美的即時頻譜分析，更核心的功能是 **Lossless Switcher** —— 能夠智慧偵測 Apple Music 的當前播放採樣率，並自動同步系統音訊設定，確保您享受到 **Bit-Perfect** 的無損聆聽體驗。

## 🚀 版本 1.0.1 新功能
*   **原生重寫**：完全移除 Flutter，改用純 Swift (AppKit) 開發，效能更佳，體積更小。
*   **智慧重連**：自動處理 CoreAudio 中斷（如手動切換格式時），確保 App 不會凍結。
*   **動態狀態列**：Status Bar 寬度隨取樣率文字自動調整，並支援 5 種迷你動畫模式。

## ✨ 主要功能

### 🎵 Lossless Switcher (無損切換)
*   **自動偵測**: 監聽 Apple Music 播放日誌，識別 44.1kHz 至 192kHz 的採樣率變化。
*   **同步切換**: 自動將 **BlackHole** 及您的 **DAC (外部輸出裝置)** 切換至對應採樣率，避免系統強制 SRC (Sample Rate Conversion) 造成的音質減損。

### 📊 專業頻譜分析
*   **即時 FFT**: 基於 vDSP 的高效能頻譜分析。
*   **5 種視覺化模式**:
    1.  **Bars (柱狀圖)**: 經典頻率分佈。
    2.  **Wave (波形圖)**: 時域波形顯示。
    3.  **Circular (圓形)**: 現代感放射狀視覺。
    4.  **Blocks (區塊)**: 復古 LED 風格。
    5.  **Mirror (鏡像)**: 對稱式頻譜。
*   **Status Bar 整合**: 在選單列顯示即時迷你頻譜與當前採樣率 (例如 `96k`)。

### ⚙️ 貼心設定
*   **記憶功能**: 自動記住您上次使用的視覺化模式與更新率設定。
*   **開機啟動**: 支援 Launch at Login。
*   **隱私友善**: 清楚的系統麥克風使用指示 (Privacy Indicator)，完全透明。

## 🛠️ 安裝前準備

本專案依賴虛擬音訊驅動來擷取系統聲音。

### 1. 安裝 BlackHole (必要)
請打開終端機 (Terminal) 安裝 **BlackHole 2ch**：

```bash
brew install blackhole-2ch
```

### 2. (選用) 設定多重輸出裝置
為了在聽音樂的同時進行視覺化，建議在「音訊 MIDI 設定 (Audio MIDI Setup)」中建立一個「多重輸出裝置 (Multi-Output Device)」，同時勾選您的 **DAC/耳機** 和 **BlackHole 2ch**。

## 📦 下載與執行

您可以使用我們內建的腳本一鍵編譯並執行：

1.  **Clone 專案**
2.  **執行腳本**:

    ```bash
    ./run_native.sh
    ```

腳本會自動清理舊檔、編譯 Swift 專案，並啟動 `Spectrum Scope.app`。

---

<a id="english"></a>
# Spectrum Scope (English)

**Spectrum Scope** is a native macOS high-resolution audio visualizer built with Swift.

Beyond beautiful real-time spectrum analysis, its core feature is the **Lossless Switcher**, which intelligently detects the sample rate of the currently playing track in Apple Music and automatically synchronizes the system audio settings, ensuring a **Bit-Perfect** listening experience.

## 🚀 New in v1.0.1
*   **Native Rewrite**: Fully migrated from Flutter to pure Swift (AppKit) for better performance and smaller footprint.
*   **Smart Reconnection**: Robust handling of CoreAudio interruptions (e.g., manual format changes), ensuring the app never freezes.
*   **Dynamic Status Bar**: The status bar item dynamically adjusts its width and supports 5 mini animation modes.

## ✨ Key Features

### 🎵 Lossless Switcher
*   **Auto Detection**: Monitors Apple Music logs to detect sample rate changes from 44.1kHz to 192kHz.
*   **Sync Switching**: Automatically switches **BlackHole** and your **DAC (External Output)** to the matching sample rate, preventing sound degradation caused by system SRC (Sample Rate Conversion).

### 📊 Pro Spectrum Analysis
*   **Real-time FFT**: High-performance spectrum analysis based on vDSP.
*   **5 Visualization Modes**:
    1.  **Bars**: Classic frequency distribution.
    2.  **Wave**: Time-domain waveform.
    3.  **Circular**: Modern radial visualization.
    4.  **Blocks**: Retro LED style.
    5.  **Mirror**: Symmetrical spectrum.
*   **Status Bar Integration**: Displays real-time mini spectrum and current sample rate (e.g., `96k`) directly in the menu bar.

### ⚙️ Settings
*   **Persistence**: Remembers your visualization mode and UI refresh rate preferences.
*   **Launch at Login**: Optional setting to start automatically.
*   **Privacy Friendly**: Clear microphone usage indication via macOS system privacy indicator.

## 🛠️ Prerequisites

This project relies on a virtual audio driver to capture system audio.

### 1. Install BlackHole (Required)
Install **BlackHole 2ch** via terminal:

```bash
brew install blackhole-2ch
```

### 2. (Optional) Multi-Output Device
To listen to music while visualizing it, it is recommended to create a "Multi-Output Device" in **Audio MIDI Setup**, checking both your **DAC/Headphones** and **BlackHole 2ch**.

## 📦 Build & Run

You can use the included script to build and run with one command:

```bash
./run_native.sh
```

This script will clean old artifacts, compile the native Swift project using `xcodebuild`, and launch `Spectrum Scope.app`.

---

## 📸 Screenshots

<img width="312" height="495" alt="Screenshot 1" src="https://github.com/user-attachments/assets/ba2cd8e7-a6fc-4719-8b95-15579c7c2a8a" />
<img width="313" height="493" alt="Screenshot 2" src="https://github.com/user-attachments/assets/1f35500d-74a1-473e-b237-a70b609bbc08" />

## Acknowledgements

Special thanks to [vincentneo](https://github.com/vincentneo) for the [LosslessSwitcher](https://github.com/vincentneo/LosslessSwitcher) project, which provided the core inspiration for our automatic sample rate switching logic.

---
Developed with ❤️ by **Pedro.Yang**.
