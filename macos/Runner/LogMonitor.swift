import Foundation

class LogMonitor {
    static let shared = LogMonitor()
    private var process: Process?
    private var outputPipe: Pipe?
    
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
    }
    
    private func processLogBatch(_ logBatch: String) {
        let lines = logBatch.split(separator: "\n")
        for line in lines {
            parseTextLog(String(line))
        }
    }
    
    private func parseTextLog(_ line: String) {
        // Keyword filter to reduce noise
        guard line.contains("sampleRate") else { return }
        
        if isDebugMode {
            print("📝 Log Candidate: \(line)")
        }
        
        // Match pattern: sampleRate:96000
        // User provided log: "... use AudioQueue for format:'qlac' ... sampleRate:96000"
        if let rate = extractSampleRate(from: line) {
            // Anti-bounce / Validation
            if [44100, 48000, 88200, 96000, 176400, 192000].contains(rate) {
                print("🎯 Detected Music Sample Rate: \(rate)")
                onSampleRateDetected?(rate)
            }
        }
    }
    
    private func extractSampleRate(from text: String) -> Int? {
        // Regex to look for "sampleRate:(\d+)" or "sampleRate = (\d+)"
        // The user log specifically shows "sampleRate:96000"
        let pattern = #"sampleRate[:\s=]+(\d+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if let lastMatch = results.last, lastMatch.numberOfRanges >= 2 {
            let numberString = nsString.substring(with: lastMatch.range(at: 1))
            return Int(numberString)
        }
        
        return nil
    }
}
