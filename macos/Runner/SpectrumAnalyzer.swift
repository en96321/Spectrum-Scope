import Foundation
import Accelerate

class SpectrumAnalyzer {
    private var fftSetup: FFTSetup?
    private let fftSize: Int = 2048
    private var log2n: vDSP_Length
    private var window: [Float]
    
    init() {
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        self.window = [Float](repeating: 0, count: fftSize)
        
        // Setup FFT
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        
        // Hanning Window
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    func process(audioData: [Float], sampleRate: Double, bandCount: Int = 32) -> [Float] {
        guard let fftSetup = fftSetup, !audioData.isEmpty else { return [Float](repeating: -80, count: bandCount) }
        
        // 1. 準備數據：取最後 2048 個點
        var inputData = [Float](repeating: 0, count: fftSize)
        let dataCount = audioData.count
        if dataCount >= fftSize {
            inputData.replaceSubrange(0..<fftSize, with: audioData[(dataCount-fftSize)..<dataCount])
        } else {
            inputData.replaceSubrange(0..<dataCount, with: audioData)
        }
        
        // 2. 加窗
        vDSP_vmul(inputData, 1, window, 1, &inputData, 1, vDSP_Length(fftSize))
        
        // 3. 轉換為 Complex Split 並執行 FFT
        var real = [Float](repeating: 0, count: fftSize/2)
        var imag = [Float](repeating: 0, count: fftSize/2)
        
        // 重新綁定記憶體以適配 DSPComplex
        inputData.withUnsafeBufferPointer { p in
            p.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize/2) { typeConvertedTransferBuffer in
                
                real.withUnsafeMutableBufferPointer { realBP in
                    imag.withUnsafeMutableBufferPointer { imagBP in
                        guard let realPtr = realBP.baseAddress, let imagPtr = imagBP.baseAddress else { return }
                        
                        var splitComplex = DSPSplitComplex(realp: realPtr, imagp: imagPtr)
                        vDSP_ctoz(typeConvertedTransferBuffer, 2, &splitComplex, 1, vDSP_Length(fftSize/2))
                        
                        // 4. 執行 FFT
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                        
                        // 5. 計算 magnitude (square)
                        vDSP_zvmags(&splitComplex, 1, realPtr, 1, vDSP_Length(fftSize/2))
                    }
                }
            }
        }
        
        // 6. 轉換為 dB 並映射到 bands (Log Scale)
        var spectrum: [Float] = []
        let nyquistIdx = fftSize / 2
        let nyquistFreq = Float(sampleRate / 2.0)
        let minFreq: Float = 20.0
        let maxFreq: Float = nyquistFreq // Dynamic range up to Nyquist
        
        let freqPerBin = nyquistFreq / Float(nyquistIdx)
        
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logRange = logMax - logMin
        let logStep = logRange / Float(bandCount)
        
        for i in 0..<bandCount {
            let logStart = logMin + Float(i) * logStep
            let logEnd = logMin + Float(i + 1) * logStep
            let startFreq = pow(10, logStart)
            let endFreq = pow(10, logEnd)
            
            if startFreq > nyquistFreq {
                spectrum.append(-80)
                continue
            }
            
            let startBin = Int(startFreq / freqPerBin)
            let endBin = min(Int(endFreq / freqPerBin), nyquistIdx)
            
            var maxMagnitude: Float = 0.0000001
            
            if startBin < endBin {
                for bin in startBin..<endBin {
                     if bin < real.count && real[bin] > maxMagnitude {
                         maxMagnitude = real[bin]
                     }
                }
            } else if startBin < nyquistIdx && startBin < real.count {
                maxMagnitude = real[startBin]
            }
            
            // 權重與 Gain Adjustment (-50dB, 0.6 tilt)
            let weightDb: Float = Float(i) * 0.6
            let db = 10 * log10(maxMagnitude) + weightDb - 50
            spectrum.append(max(-80, min(0, db)))
        }
        
        return spectrum
    }
    
    func calculateVolumeDb(_ audioData: [Float]) -> Float {
        guard !audioData.isEmpty else { return -60 }
        
        var sumSquares: Float = 0
        for sample in audioData {
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(audioData.count))
        let db = 20 * log10(rms + 1e-10)
        return max(-60, min(0, db))
    }
    
    func calculatePeakDb(_ audioData: [Float]) -> Float {
        guard !audioData.isEmpty else { return -60 }
        
        var peak: Float = 0
        for sample in audioData {
            let abs = Swift.abs(sample)
            if abs > peak { peak = abs }
        }
        let db = 20 * log10(peak + 1e-10)
        return max(-60, min(0, db))
    }
}
