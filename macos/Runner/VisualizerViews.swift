import Cocoa
import ServiceManagement

// MARK: - VisualizationMode

enum VisualizationMode: Int, CaseIterable {
    case bars = 0
    case wave = 1
    case circular = 2
    case blocks = 3
    case mirror = 4
    
    var icon: String {
        switch self {
        case .bars: return "chart.bar.fill"
        case .wave: return "waveform.path"
        case .circular: return "circle.circle"
        case .blocks: return "square.grid.3x3.fill"
        case .mirror: return "arrow.up.arrow.down"
        }
    }
    
    var label: String {
        switch self {
        case .bars: return "柱狀圖"
        case .wave: return "波形圖"
        case .circular: return "圓形"
        case .blocks: return "區塊"
        case .mirror: return "鏡像"
        }
    }
}

// MARK: - CGFloat Extension

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - MiniSpectrumView

/// 迷你頻譜視圖 - 用於 Menu Bar Popover
class MiniSpectrumView: NSView {
    
    private var spectrum: [Float] = []
    private let barCount = 32
    var mode: VisualizationMode = .bars {
        didSet { needsDisplay = true }
    }
    
    private let gradientColors: [NSColor] = [
        NSColor(red: 0, green: 0.898, blue: 1, alpha: 1),      // 青色
        NSColor(red: 0, green: 0.749, blue: 0.647, alpha: 1),  // 綠松色
        NSColor(red: 1, green: 0.839, blue: 0, alpha: 1),      // 黃色
        NSColor(red: 1, green: 0.427, blue: 0, alpha: 1),      // 橙色
        NSColor(red: 1, green: 0.090, blue: 0.267, alpha: 1),  // 紅色
    ]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1).cgColor
        layer?.cornerRadius = 8
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1).cgColor
        layer?.cornerRadius = 8
    }
    
    func updateSpectrum(_ newSpectrum: [Float]) {
        spectrum = newSpectrum
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 背景
        context.setFillColor(NSColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1).cgColor)
        context.fill(bounds)
        
        // 為標籤預留空間（如果不是 Circular 模式）
        let labelHeight: CGFloat = mode == .circular ? 0 : 16
        
        // 保存狀態以進行裁切/變換
        context.saveGState()
        
        // 將原點移動到標籤上方
        context.translateBy(x: 0, y: labelHeight)
        
        // 創建一個新的區域用於繪製頻譜
        let spectrumContextBounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - labelHeight)
        
        // 根據模式繪製頻譜
        switch mode {
        case .bars:
            drawBars(context, bounds: spectrumContextBounds)
        case .wave:
            drawWave(context, bounds: spectrumContextBounds)
        case .circular:
            drawCircular(context, bounds: spectrumContextBounds)
        case .blocks:
            drawBlocks(context, bounds: spectrumContextBounds)
        case .mirror:
            drawMirror(context, bounds: spectrumContextBounds)
        }
        
        context.restoreGState()
        
        // 繪製標籤
        if mode != .circular {
            drawLabels(context)
        }
    }
    
    var maxFrequency: Float = 24000.0 { // Default to 48k/2
        didSet { needsDisplay = true }
    }
    
    // ... (init/draw methods remain same until drawLabels)

    private func drawLabels(_ context: CGContext) {
        let minFreq: Float = 20.0
        let maxFreqString = String(format: "%.0fk", maxFrequency / 1000.0)
        
        // 定義要顯示的頻率點 (固定 + 動態最大值)
        let targetFreqs: [(Float, String)] = [
            (20.0, "20"),
            (100.0, "100"),
            (1000.0, "1k"),
            (10000.0, "10k"),
            (maxFrequency, maxFreqString)
        ]
        
        let width = bounds.width
        let logMin = log10(minFreq)
        let logMax = log10(maxFrequency)
        let logRange = logMax - logMin
        
        for (freq, text) in targetFreqs {
            // 只有當頻率在範圍內才顯示
            if freq > maxFrequency + 1 { continue } // +1 for float error
            
            let logVal = log10(freq)
            let relativeX = CGFloat((logVal - logMin) / logRange)
            
            // 避免標籤重疊 (簡單判斷: 如果不是 min/max，太靠邊就不畫)
            if (freq != minFreq && freq != maxFrequency) {
                if relativeX < 0.05 || relativeX > 0.95 { continue }
            }
            
            let x = width * relativeX
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.white.withAlphaComponent(0.5)
            ]
            let string = NSAttributedString(string: text, attributes: attrs)
            let size = string.size()
            
            var drawX = x - size.width / 2
            
            // 邊界修正
            if relativeX <= 0.0 { drawX = 0 }
            if relativeX >= 1.0 { drawX = width - size.width }
            
            string.draw(at: CGPoint(x: drawX, y: 2))
        }
    }
    
    private func drawBars(_ context: CGContext, bounds: CGRect) {
        guard !spectrum.isEmpty else { return }
        
        let sampledSpectrum = resampleSpectrum(spectrum, targetCount: barCount)
        let barWidth = bounds.width / CGFloat(barCount)
        let spacing = barWidth * 0.2
        let actualBarWidth = barWidth - spacing
        
        for (index, value) in sampledSpectrum.enumerated() {
            let normalizedHeight = CGFloat((value + 80) / 80).clamped(to: 0...1)
            let barHeight = bounds.height * normalizedHeight
            
            let x = CGFloat(index) * barWidth + spacing / 2
            let y: CGFloat = 0
            
            let color = getColorForHeight(normalizedHeight)
            context.setShadow(offset: .zero, blur: 3, color: color.withAlphaComponent(0.5).cgColor)
            context.setFillColor(color.cgColor)
            let rect = CGRect(x: x, y: y, width: actualBarWidth, height: barHeight)
            context.fill(rect)
        }
    }
    
    private func drawWave(_ context: CGContext, bounds: CGRect) {
        guard !spectrum.isEmpty else { return }
        let sampledSpectrum = resampleSpectrum(spectrum, targetCount: Int(bounds.width / 2))
        
        context.setLineWidth(2)
        let path = CGMutablePath()
        
        let width = bounds.width
        let height = bounds.height
        let count = sampledSpectrum.count
        
        path.move(to: CGPoint(x: 0, y: 0))
        
        for (i, value) in sampledSpectrum.enumerated() {
            let x = width * CGFloat(i) / CGFloat(count - 1)
            let normalizedHeight = CGFloat((value + 80) / 80).clamped(to: 0...1)
            let y = height * normalizedHeight
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        
        context.addPath(path)
        context.setStrokeColor(gradientColors[2].cgColor)
        context.setShadow(offset: .zero, blur: 4, color: gradientColors[2].withAlphaComponent(0.6).cgColor)
        context.strokePath()
    }
    
    private func drawCircular(_ context: CGContext, bounds: CGRect) {
        guard !spectrum.isEmpty else { return }
        let pointCount = 64
        let sampledSpectrum = resampleSpectrum(spectrum, targetCount: pointCount)
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let maxRadius = min(bounds.width, bounds.height) / 2
        let minRadius = maxRadius * 0.3
        let angleStep = (2 * CGFloat.pi) / CGFloat(pointCount)
        
        for (i, value) in sampledSpectrum.enumerated() {
            let normalizedHeight = CGFloat((value + 80) / 80).clamped(to: 0...1)
            let barLength = (maxRadius - minRadius) * normalizedHeight
            let angle = CGFloat(i) * angleStep - CGFloat.pi / 2
            
            let startX = center.x + cos(angle) * minRadius
            let startY = center.y + sin(angle) * minRadius
            let endX = center.x + cos(angle) * (minRadius + barLength)
            let endY = center.y + sin(angle) * (minRadius + barLength)
            
            let color = getColorForHeight(normalizedHeight)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(3)
            context.setLineCap(.round)
            context.setShadow(offset: .zero, blur: 2, color: color.withAlphaComponent(0.5).cgColor)
            
            context.move(to: CGPoint(x: startX, y: startY))
            context.addLine(to: CGPoint(x: endX, y: endY))
            context.strokePath()
        }
    }
    
    private func drawBlocks(_ context: CGContext, bounds: CGRect) {
        guard !spectrum.isEmpty else { return }
        let columns = 16
        let rows = 10
        let sampledSpectrum = resampleSpectrum(spectrum, targetCount: columns)
        let blockW = bounds.width / CGFloat(columns)
        let blockH = bounds.height / CGFloat(rows)
        let spacing: CGFloat = 2
        
        for (col, value) in sampledSpectrum.enumerated() {
            let normalizedHeight = CGFloat((value + 80) / 80).clamped(to: 0...1)
            let activeRows = Int(normalizedHeight * CGFloat(rows))
            for row in 0..<activeRows {
                let x = CGFloat(col) * blockW + spacing / 2
                let y = CGFloat(row) * blockH + spacing / 2
                let heightRatio = CGFloat(row) / CGFloat(rows)
                let color = getColorForHeight(heightRatio)
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: x, y: y, width: blockW - spacing, height: blockH - spacing))
            }
        }
    }
    
    private func drawMirror(_ context: CGContext, bounds: CGRect) {
        guard !spectrum.isEmpty else { return }
        let sampledSpectrum = resampleSpectrum(spectrum, targetCount: barCount)
        let barWidth = bounds.width / CGFloat(barCount)
        let spacing = barWidth * 0.2
        let actualBarWidth = barWidth - spacing
        let midY = bounds.midY
        
        for (index, value) in sampledSpectrum.enumerated() {
            let normalizedHeight = CGFloat((value + 80) / 80).clamped(to: 0...1)
            let barHeight = (bounds.height / 2) * normalizedHeight
            let x = CGFloat(index) * barWidth + spacing / 2
            let color = getColorForHeight(normalizedHeight)
            context.setFillColor(color.cgColor)
            context.setShadow(offset: .zero, blur: 3, color: color.withAlphaComponent(0.5).cgColor)
            context.fill(CGRect(x: x, y: midY, width: actualBarWidth, height: barHeight))
            context.fill(CGRect(x: x, y: midY - barHeight, width: actualBarWidth, height: barHeight))
        }
    }
    
    private func resampleSpectrum(_ original: [Float], targetCount: Int) -> [Float] {
        guard !original.isEmpty else { return [] }
        guard original.count > targetCount else { return original }
        
        var result: [Float] = []
        let step = Float(original.count) / Float(targetCount)
        
        for i in 0..<targetCount {
            let start = Int(Float(i) * step)
            let end = min(Int(Float(i + 1) * step), original.count)
            guard start < end else {
                result.append(result.last ?? -80)
                continue
            }
            var maxVal: Float = -100
            for j in start..<end {
                if original[j] > maxVal { maxVal = original[j] }
            }
            result.append(maxVal)
        }
        return result
    }
    
    private func getColorForHeight(_ height: CGFloat) -> NSColor {
        let colorIndex = Int(height * CGFloat(gradientColors.count - 1))
        let clampedIndex = max(0, min(colorIndex, gradientColors.count - 1))
        let nextIndex = min(clampedIndex + 1, gradientColors.count - 1)
        let t = height * CGFloat(gradientColors.count - 1) - CGFloat(clampedIndex)
        return interpolateColor(from: gradientColors[clampedIndex], to: gradientColors[nextIndex], t: t)
    }
    
    private func interpolateColor(from: NSColor, to: NSColor, t: CGFloat) -> NSColor {
        let clampedT = max(0, min(t, 1))
        return NSColor(
            red: from.redComponent + (to.redComponent - from.redComponent) * clampedT,
            green: from.greenComponent + (to.greenComponent - from.greenComponent) * clampedT,
            blue: from.blueComponent + (to.blueComponent - from.blueComponent) * clampedT,
            alpha: 1
        )
    }
}

// MARK: - MenuBarSpectrumView

class MenuBarSpectrumView: NSView {
    
    private var spectrum: [Float] = []
    private let barCount = 5
    var mode: VisualizationMode = .bars {
        didSet { needsDisplay = true }
    }
    
    private let gradientColors: [NSColor] = [
        NSColor(red: 0, green: 0.898, blue: 1, alpha: 1),
        NSColor(red: 0, green: 0.749, blue: 0.647, alpha: 1),
        NSColor(red: 1, green: 0.839, blue: 0, alpha: 1),
        NSColor(red: 1, green: 0.427, blue: 0, alpha: 1),
        NSColor(red: 1, green: 0.090, blue: 0.267, alpha: 1),
    ]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    func updateSpectrum(_ newSpectrum: [Float]) {
        spectrum = newSpectrum
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        switch mode {
        case .bars, .blocks: drawBars(context)
        case .wave, .circular, .mirror: drawWave(context)
        }
    }
    
    private func drawBars(_ context: CGContext) {
        let barWidth = bounds.width / CGFloat(barCount)
        let spacing: CGFloat = 1
        let actualBarWidth = barWidth - spacing
        let sampledSpectrum: [Float] = spectrum.isEmpty ? [-60, -50, -40, -50, -60] : resampleSpectrum(spectrum, targetCount: barCount)
        
        for (index, value) in sampledSpectrum.enumerated() {
            let normalizedHeight = CGFloat((value + 80) / 80).clamped(to: 0...1)
            let barHeight = max(2, bounds.height * normalizedHeight)
            let x = CGFloat(index) * barWidth + spacing / 2
            let y = (bounds.height - barHeight) / 2
            
            let color = getColorForHeight(normalizedHeight)
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: x, y: y, width: actualBarWidth, height: barHeight))
        }
    }
    
    private func drawWave(_ context: CGContext) {
        let sampledSpectrum: [Float] = spectrum.isEmpty ? [-60, -60, -60] : resampleSpectrum(spectrum, targetCount: Int(bounds.width / 2))
        
        context.setLineWidth(1.5)
        let path = CGMutablePath()
        let width = bounds.width
        let height = bounds.height
        let count = sampledSpectrum.count
        let midY = height / 2
        path.move(to: CGPoint(x: 0, y: midY))
        
        for (i, value) in sampledSpectrum.enumerated() {
            let x = width * CGFloat(i) / CGFloat(count - 1)
            let normalizedHeight = CGFloat((value + 80) / 80).clamped(to: 0...1)
            let amplitude = (height / 2) * normalizedHeight
            let y = midY - amplitude
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        
        context.addPath(path)
        context.setStrokeColor(gradientColors[2].cgColor)
        context.strokePath()
    }
    
    // Duplicate helper methods to keep class independent if needed, or rely on shared logic?
    // Copying helpers for safety.
    private func getColorForHeight(_ height: CGFloat) -> NSColor {
        let colorIndex = Int(height * CGFloat(gradientColors.count - 1))
        let clampedIndex = max(0, min(colorIndex, gradientColors.count - 1))
        let nextIndex = min(clampedIndex + 1, gradientColors.count - 1)
        let t = height * CGFloat(gradientColors.count - 1) - CGFloat(clampedIndex)
        return interpolateColor(from: gradientColors[clampedIndex], to: gradientColors[nextIndex], t: t)
    }
    
    private func interpolateColor(from: NSColor, to: NSColor, t: CGFloat) -> NSColor {
        let clampedT = max(0, min(t, 1))
        return NSColor(
            red: from.redComponent + (to.redComponent - from.redComponent) * clampedT,
            green: from.greenComponent + (to.greenComponent - from.greenComponent) * clampedT,
            blue: from.blueComponent + (to.blueComponent - from.blueComponent) * clampedT,
            alpha: 1
        )
    }
    
    private func resampleSpectrum(_ original: [Float], targetCount: Int) -> [Float] {
        guard !original.isEmpty else { return [] }
        guard original.count > targetCount else { return original }
        var result: [Float] = []
        let step = Float(original.count) / Float(targetCount)
        for i in 0..<targetCount {
            let start = Int(Float(i) * step)
            let end = min(Int(Float(i + 1) * step), original.count)
            guard start < end else { result.append(result.last ?? -80); continue }
            var maxVal: Float = -100
            for j in start..<end { if original[j] > maxVal { maxVal = original[j] } }
            result.append(maxVal)
        }
        return result
    }
}

// MARK: - FullPopoverView

class FullPopoverView: NSView {
    
    private var spectrumView: MiniSpectrumView!
    private var modeSegmentedControl: NSSegmentedControl!
    private var volumeLabel: NSTextField!
    private var peakLabel: NSTextField!
    private var sampleRateLabel: NSTextField!
    private var bitDepthLabel: NSTextField!
    
    var onQuit: (() -> Void)?
    var onModeChanged: ((VisualizationMode) -> Void)?
    

    
    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.03, green: 0.03, blue: 0.08, alpha: 1).cgColor
        
        // 標題列
        let titleLabel = NSTextField(labelWithString: "Spectrum Scope")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 16, y: bounds.height - 32, width: 200, height: 20)
        addSubview(titleLabel)
        
        // 模式切換器
        let modes = VisualizationMode.allCases
        modeSegmentedControl = NSSegmentedControl(
            images: modes.map { NSImage(systemSymbolName: $0.icon, accessibilityDescription: $0.label) ?? NSImage() },
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged)
        )
        modeSegmentedControl.selectedSegment = 0
        modeSegmentedControl.frame = NSRect(x: 16, y: bounds.height - 70, width: bounds.width - 32, height: 24)
        modeSegmentedControl.segmentStyle = .texturedRounded
        addSubview(modeSegmentedControl)
        
        // 頻譜視圖
        spectrumView = MiniSpectrumView(frame: NSRect(x: 16, y: bounds.height - 220, width: bounds.width - 32, height: 140))
        addSubview(spectrumView)
        
        // 音量區塊
        let volumeTitleLabel = NSTextField(labelWithString: "音量")
        volumeTitleLabel.font = NSFont.systemFont(ofSize: 12)
        volumeTitleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        volumeTitleLabel.frame = NSRect(x: 16, y: bounds.height - 250, width: 50, height: 16)
        addSubview(volumeTitleLabel)
        
        volumeLabel = NSTextField(labelWithString: "-60.0 dB")
        volumeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        volumeLabel.textColor = .white
        volumeLabel.alignment = .right
        volumeLabel.frame = NSRect(x: bounds.width - 100, y: bounds.height - 250, width: 84, height: 16)
        addSubview(volumeLabel)
        
        // 音量進度條背景
        let volumeProgressBg = NSView(frame: NSRect(x: 16, y: bounds.height - 272, width: bounds.width - 32, height: 8))
        volumeProgressBg.wantsLayer = true
        volumeProgressBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        volumeProgressBg.layer?.cornerRadius = 4
        addSubview(volumeProgressBg)
        
        // 峰值區塊
        let peakTitleLabel = NSTextField(labelWithString: "峰值")
        peakTitleLabel.font = NSFont.systemFont(ofSize: 12)
        peakTitleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        peakTitleLabel.frame = NSRect(x: 16, y: bounds.height - 300, width: 50, height: 16)
        addSubview(peakTitleLabel)
        
        peakLabel = NSTextField(labelWithString: "-60.0 dB")
        peakLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        peakLabel.textColor = .white
        peakLabel.alignment = .right
        peakLabel.frame = NSRect(x: bounds.width - 100, y: bounds.height - 300, width: 84, height: 16)
        addSubview(peakLabel)
        
        // 峰值進度條背景
        let peakProgressBg = NSView(frame: NSRect(x: 16, y: bounds.height - 322, width: bounds.width - 32, height: 8))
        peakProgressBg.wantsLayer = true
        peakProgressBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        peakProgressBg.layer?.cornerRadius = 4
        addSubview(peakProgressBg)
        
        // 分隔線
        let separator1 = NSView(frame: NSRect(x: 16, y: bounds.height - 340, width: bounds.width - 32, height: 1))
        separator1.wantsLayer = true
        separator1.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        addSubview(separator1)
        
        // 音訊資訊區塊
        let infoTitleLabel = NSTextField(labelWithString: "音訊資訊")
        infoTitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        infoTitleLabel.textColor = .white
        infoTitleLabel.frame = NSRect(x: 16, y: bounds.height - 370, width: 100, height: 20)
        addSubview(infoTitleLabel)
        
        // 取樣率
        let sampleRateTitleLabel = NSTextField(labelWithString: "取樣率")
        sampleRateTitleLabel.font = NSFont.systemFont(ofSize: 11)
        sampleRateTitleLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        sampleRateTitleLabel.frame = NSRect(x: 16, y: bounds.height - 395, width: 60, height: 14)
        addSubview(sampleRateTitleLabel)
        
        sampleRateLabel = NSTextField(labelWithString: "48.0 kHz")
        sampleRateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        sampleRateLabel.textColor = .white
        sampleRateLabel.frame = NSRect(x: 16, y: bounds.height - 415, width: 100, height: 18)
        addSubview(sampleRateLabel)
        
        // 位元深度
        let bitDepthTitleLabel = NSTextField(labelWithString: "位元深度")
        bitDepthTitleLabel.font = NSFont.systemFont(ofSize: 11)
        bitDepthTitleLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        bitDepthTitleLabel.frame = NSRect(x: bounds.width / 2, y: bounds.height - 395, width: 60, height: 14)
        addSubview(bitDepthTitleLabel)
        
        bitDepthLabel = NSTextField(labelWithString: "32 bit")
        bitDepthLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        bitDepthLabel.textColor = .white
        bitDepthLabel.frame = NSRect(x: bounds.width / 2, y: bounds.height - 415, width: 100, height: 18)
        addSubview(bitDepthLabel)
        
        // 設定按鈕 (齒輪圖示)
        let settingsButton = NSButton(frame: NSRect(x: bounds.width - 40, y: bounds.height - 32, width: 24, height: 24))
        settingsButton.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "設定")
        settingsButton.bezelStyle = .texturedRounded
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .white
        settingsButton.target = self
        settingsButton.action = #selector(settingsClicked)
        addSubview(settingsButton)
    }
    
    @objc func settingsClicked(_ sender: NSButton) {
        let menu = NSMenu()
        
        // 1. 開機自動啟動
        let isLaunchAtLogin = SettingsManager.shared.isLaunchAtLoginEnabled
        let launchItem = NSMenuItem(title: "開機自動啟動", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = isLaunchAtLogin ? .on : .off
        launchItem.target = self
        menu.addItem(launchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. 更新頻率 (FPS)
        let fpsItem = NSMenuItem(title: "UI 更新頻率", action: nil, keyEquivalent: "")
        let fpsMenu = NSMenu()
        let currentFPS = SettingsManager.shared.uiRefreshRate
        let fpsOptions = [24, 30, 60, 120]
        
        for fps in fpsOptions {
            let item = NSMenuItem(title: "\(fps) FPS", action: #selector(selectFPS), keyEquivalent: "")
            item.tag = fps
            item.state = (currentFPS == fps) ? NSControl.StateValue.on : NSControl.StateValue.off
            item.target = self
            fpsMenu.addItem(item)
        }
        fpsItem.submenu = fpsMenu
        menu.addItem(fpsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Lossless Switcher 開關
        let isLosslessEnabled = SettingsManager.shared.isLosslessSwitcherEnabled
        let losslessItem = NSMenuItem(title: "啟用 Lossless Switcher", action: #selector(toggleLosslessSwitcher), keyEquivalent: "")
        losslessItem.state = isLosslessEnabled ? .on : .off
        losslessItem.target = self
        menu.addItem(losslessItem)
        
        // 4. 目標輸出裝置選擇 (Submenu)
        let deviceItem = NSMenuItem(title: "同步設定輸出裝置", action: nil, keyEquivalent: "")
        let deviceMenu = NSMenu()
        
        let devices = AudioDeviceController.shared.getAllOutputDevices()
        let currentTargetID = SettingsManager.shared.targetOutputDeviceID
        
        // 選項: 自動 (跟隨系統預設)
        let autoItem = NSMenuItem(title: "系統預設 (System Default)", action: #selector(selectTargetDevice), keyEquivalent: "")
        autoItem.tag = 0
        autoItem.state = (currentTargetID == 0) ? NSControl.StateValue.on : NSControl.StateValue.off
        autoItem.target = self
        deviceMenu.addItem(autoItem)
        
        deviceMenu.addItem(NSMenuItem.separator())
        
        for (id, name) in devices {
            if name.contains("BlackHole") { continue } // 不需要同步給 BlackHole 自己
            
            let item = NSMenuItem(title: name, action: #selector(selectTargetDevice), keyEquivalent: "")
            item.tag = Int(id)
            item.state = (currentTargetID == id) ? NSControl.StateValue.on : NSControl.StateValue.off
            item.target = self
            deviceMenu.addItem(item)
        }
        
        deviceItem.submenu = deviceMenu
        menu.addItem(deviceItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 關於
         let aboutItem = NSMenuItem(title: "關於 Spectrum Scope", action: #selector(aboutClicked), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 結束 (移至此處)
        let quitItem = NSMenuItem(title: "結束 Spectrum Scope", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // 顯示選單 (Anchor to button)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
    
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        SettingsManager.shared.isLaunchAtLoginEnabled = newState
        sender.state = newState ? .on : .off
    }
    
    @objc func selectFPS(_ sender: NSMenuItem) {
        SettingsManager.shared.uiRefreshRate = sender.tag
    }
    
    @objc func toggleLosslessSwitcher(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        SettingsManager.shared.isLosslessSwitcherEnabled = newState
        sender.state = newState ? .on : .off
    }
    
    @objc func selectTargetDevice(_ sender: NSMenuItem) {
        SettingsManager.shared.targetOutputDeviceID = UInt32(sender.tag)
    }
    
    @objc func modeChanged(_ sender: NSSegmentedControl) {
        let mode = VisualizationMode(rawValue: sender.selectedSegment) ?? .bars
        SettingsManager.shared.visualizationMode = mode.rawValue
        spectrumView.mode = mode
        onModeChanged?(mode)
    }
    
    @objc func quitClicked() {
        onQuit?()
    }
    
    @objc func aboutClicked() {
        let alert = NSAlert()
        alert.messageText = "Spectrum Scope"
        alert.informativeText = "Version 1.0.0\n\nA High-Res Audio Visualizer for macOS.\n\nDeveloped with ❤️ by Pedro.Yang\n\nSpecial thanks to vincentneo for LosslessSwitcher inspiration."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        // Set icon if available, otherwise default app icon executes
        alert.icon = NSImage(named: "AppIcon") 
        alert.runModal()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        
        // Restore saved mode
        let savedMode = SettingsManager.shared.visualizationMode
        if let mode = VisualizationMode(rawValue: savedMode) {
            spectrumView.mode = mode
            modeSegmentedControl?.selectedSegment = savedMode
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    func updateSpectrum(_ spectrum: [Float]) {
        spectrumView?.updateSpectrum(spectrum)
    }
    
    func updateMetrics(volumeDb: Float, peakDb: Float) {
        volumeLabel?.stringValue = String(format: "%.1f dB", volumeDb)
        peakLabel?.stringValue = String(format: "%.1f dB", peakDb)
    }
    
    func updateAudioInfo(sampleRate: Double, bitDepth: Int, channels: Int) {
        sampleRateLabel?.stringValue = String(format: "%.1f kHz", sampleRate / 1000.0)
        bitDepthLabel?.stringValue = "\(bitDepth) bit / \(channels) ch"
        
        // 更新頻譜最大頻率 (Nyquist)
        spectrumView?.maxFrequency = Float(sampleRate / 2.0)
    }
}

// MARK: - SettingsManager

class SettingsManager {
    static let shared = SettingsManager()
    
    private let launchAtLoginKey = "launchAtLogin"
    private let losslessSwitcherKey = "losslessSwitcherEnabled" // default true
    private let targetDeviceKey = "targetOutputDeviceID" // 0 = system default
    private let uiRefreshRateKey = "uiRefreshRate" // default 60
    private let visualizationModeKey = "visualizationMode" // default 0 (bars)
    
    var isLaunchAtLoginEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return UserDefaults.standard.bool(forKey: launchAtLoginKey)
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
                } catch {
                    print("❌ Failed to toggle Launch at Login: \(error)")
                }
            } else {
                UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
            }
        }
    }
    
    var visualizationMode: Int {
        get { return UserDefaults.standard.integer(forKey: visualizationModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: visualizationModeKey) }
    }
    
    var isLosslessSwitcherEnabled: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: losslessSwitcherKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: losslessSwitcherKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: losslessSwitcherKey)
        }
    }
    
    var targetOutputDeviceID: UInt32 {
        get {
            return UInt32(UserDefaults.standard.integer(forKey: targetDeviceKey))
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: targetDeviceKey)
            print("💾 Target Device Saved: \(newValue)")
        }
    }
    
    var uiRefreshRate: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: uiRefreshRateKey)
            return val == 0 ? 60 : val // default to 60 if not set
        }
        set {
            UserDefaults.standard.set(newValue, forKey: uiRefreshRateKey)
        }
    }
}

