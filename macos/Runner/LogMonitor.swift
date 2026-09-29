import Foundation

class LogMonitor {
    static let shared = LogMonitor()
    private var process: Process?
    private var outputPipe: Pipe?
    private var tracker = MusicFormatTracker()

    var onSampleRateDetected: ((Int) -> Void)?
    var isDebugMode = true

    func startMonitoring() {
        stopMonitoring()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        // Switch to text mode (default) to match user's manual verification
        process.arguments = ["stream", "--process", "Music"]

        let pipe = Pipe()
        process.standardOutput = pipe
        self.outputPipe = pipe
        self.process = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let string = String(data: data, encoding: .utf8) {
                self?.processLogBatch(string)
            }
        }

        do {
            try process.run()
            print("✅ LogMonitor started listening to Music.app logs (Text Mode)")
        } catch {
            print("❌ Failed to start LogMonitor: \(error)")
        }
    }

    func stopMonitoring() {
        process?.terminate()
        process = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        tracker = MusicFormatTracker()
    }

    private func processLogBatch(_ logBatch: String) {
        let lines = logBatch.split(separator: "\n")
        for line in lines {
            parseTextLog(String(line))
        }
    }

    private func parseTextLog(_ line: String) {
        guard MusicFormatTracker.isRelevant(line) else { return }

        if isDebugMode {
            print("📝 Log Candidate: \(line)")
        }

        if let rate = tracker.consume(line, at: Date()) {
            print("🎯 Detected Music Sample Rate: \(rate) (item \(tracker.currentItemID ?? "?"))")
            onSampleRateDetected?(rate)
        }
    }
}

/// 從 Music.app 的 log 推斷「正在播放」曲目的採樣率。
///
/// Music 為了 gapless 會提前（實測可達 70 秒）預載下一首，並在那時就記錄它的格式。
/// 若一看到格式就切換 DAC，目前這首會在錯的採樣率下播完（系統 SRC + 中途斷音），
/// 所以只在 `ITEM BEGIN`（曲目真正開始播放）時決定切換：
///
///   AUDIO CHANGE <id> + activeFormat  → 記下該曲目的採樣率（最可靠，但不是每首都有）
///   Creating AudioQueue sampleRate:N  → 下一次格式變更的採樣率（沒有綁曲目，作為備援）
///   ITEM BEGIN <id>                   → 套用該曲目的採樣率
struct MusicFormatTracker {

    static let supportedRates: Set<Int> = [44100, 48000, 88200, 96000, 176400, 192000]

    /// ITEM BEGIN 之後多久內建立的 AudioQueue 視為屬於剛開始的曲目（跳歌時 queue 可能晚於 BEGIN）
    static let lateQueueWindow: TimeInterval = 5

    private(set) var currentItemID: String?
    private var currentItemBeganAt: Date?
    private var currentItemRateResolved = false
    private var itemRates: [String: Int] = [:]
    private var audioChangeItemID: String?
    private var pendingQueueRate: Int?

    static func isRelevant(_ line: String) -> Bool {
        line.contains("ITEM BEGIN") || line.contains("AUDIO CHANGE")
            || line.contains("activeFormat:") || line.contains("Creating AudioQueue")
    }

    /// 餵入一行 log；需要切換 DAC 時回傳採樣率
    mutating func consume(_ line: String, at date: Date) -> Int? {
        if let id = Self.firstCapture(Self.itemBeginRegex, in: line) {
            currentItemID = id
            currentItemBeganAt = date
            let rate = itemRates.removeValue(forKey: id) ?? pendingQueueRate
            pendingQueueRate = nil
            currentItemRateResolved = rate != nil
            return rate
        }

        if let id = Self.firstCapture(Self.audioChangeRegex, in: line) {
            audioChangeItemID = id
            return nil
        }

        if line.contains("activeFormat:"), let id = audioChangeItemID {
            audioChangeItemID = nil
            guard let rate = Self.rate(fromActiveFormat: line) else { return nil }
            if id == currentItemID {
                // 正在播的曲目自己的格式（首次播放、跳歌、串流升級畫質）
                currentItemRateResolved = true
                return rate
            }
            itemRates[id] = rate
            return nil
        }

        if line.contains("Creating AudioQueue"),
           let value = Self.firstCapture(Self.queueRateRegex, in: line), let rate = Int(value),
           Self.supportedRates.contains(rate) {
            if !currentItemRateResolved, let began = currentItemBeganAt,
               date.timeIntervalSince(began) <= Self.lateQueueWindow {
                currentItemRateResolved = true
                return rate
            }
            pendingQueueRate = rate
            return nil
        }

        return nil
    }

    // MARK: - Parsing

    // 例: "ITEM BEGIN                 5687 5919"（不會誤中 ITEM ASSET BEGIN / ITEM CONFIG BEGIN）
    private static let itemBeginRegex = try! NSRegularExpression(pattern: #"ITEM BEGIN\s+(\d+\s+\d+)"#)
    private static let audioChangeRegex = try! NSRegularExpression(pattern: #"AUDIO CHANGE\s+(\d+\s+\d+)"#)
    private static let queueRateRegex = try! NSRegularExpression(pattern: #"sampleRate:(\d+)"#)
    // 例: "groupID: audio-alac-stereo-44100-16"
    private static let groupRateRegex = try! NSRegularExpression(pattern: #"groupID:\s*[\w-]*?-(\d{5,6})-\d+"#)
    // 例: "sampleRate: 44khz"
    private static let khzRegex = try! NSRegularExpression(pattern: #"sampleRate:\s*(\d+)khz"#)

    private static let khzToRate: [Int: Int] = [44: 44100, 48: 48000, 88: 88200, 96: 96000, 176: 176400, 192: 192000]

    static func rate(fromActiveFormat line: String) -> Int? {
        if let value = firstCapture(groupRateRegex, in: line), let rate = Int(value), supportedRates.contains(rate) {
            return rate
        }
        if let value = firstCapture(khzRegex, in: line), let khz = Int(value) {
            return khzToRate[khz]
        }
        return nil
    }

    private static func firstCapture(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        // 曲目 ID 以單一空白正規化，避免欄寬對齊的空白數不同
        return text[captured].split(separator: " ").joined(separator: " ")
    }
}
