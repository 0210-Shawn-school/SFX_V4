import Foundation
import AVFoundation

// MARK: - UI Level (Basic / Pro)
enum UILevel: String, CaseIterable, Hashable {
    case basic
    case pro
}


enum WahMode: String, CaseIterable, Hashable {
    case lfo
    case manual
}
// MARK: - Audio Manager
final class AudioManager: ObservableObject {
    
    static let shared = AudioManager()
    
    // Engine
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    
    // FX Nodes
    private let distortionUnit = AVAudioUnitDistortion()
    private let delayUnit = AVAudioUnitDelay()
    private let wahUnit = AVAudioUnitEQ(numberOfBands: 1) //wah ==> band-pass EQ
    
    private var audioFile: AVAudioFile?
    
    // Security-scoped URL (macOS sandbox / iOS fileImporter)
    private var securityScopedURL: URL?
    
    // Wah LFO timer
    private var wahTimer: Timer?
    private var wahPhase: Double = 0
    
    //record
    private var recordingFile: AVAudioFile?
    
    // play
    @Published var uiLevel: UILevel = .basic
    @Published var isPlaying: Bool = false
    @Published var loadedFilename: String = "No audio file selected"
    @Published var volume: Double = 1.0 {didSet { player.volume = Float(volume) }}
    
    // mode: FX On/Off
    @Published var distOn: Bool = false { didSet { applyFX() } }
    @Published var delayOn: Bool = false { didSet { applyFX() } }
    @Published var wahOn: Bool = false { didSet { applyFX() } }
    
    // Distortion params
    // 0...1
    @Published var distAmount: Double = 0 { didSet { applyFX() } }// 0...1
    @Published var distMix: Double = 1.0 { didSet { applyFX() } }// 0...1
    // Delay params
    @Published var delayMix: Double = 0.35 { didSet { applyFX() } }// 0...1
    @Published var delayTime: Double = 0 { didSet { applyFX() } }//sec
    @Published var delayFeedback: Double = 25 { didSet { applyFX() } }// 0...95(%)
    // Wah params
    @Published var wahMode: WahMode = .lfo { didSet { applyFX() } }
    @Published var wahMinFreq: Double = 350 { didSet { applyFX() } }     // Hz
    @Published var wahMaxFreq: Double = 2200 { didSet { applyFX() } }    // Hz
    @Published var wahBandwidth: Double = 0.55 { didSet { applyFX() } }  // 0.2...2.0
    @Published var wahResonanceGain: Double = 14 { didSet { applyFX() } } // dB
    @Published var wahRate: Double = 2.0 { didSet { applyFX() } }        // Hz
    @Published var wahDepth: Double = 1.0 { didSet { applyFX() } }       // 0...1
    @Published var wahPedal: Double = 0 { didSet { applyFX() } }       // 0...1
    //limit
    @Published var basicDistMax: Double = 1.0   // 0...1
    @Published var basicWahMax: Double = 1.0    // 0...1
    @Published var basicDelayMax: Double = 1.0  // 0...1
    
    //record
    @Published var isRecording = false
    @Published var currentRecordingURL: URL?
    
    // Init
    private init() {
        setupAudioSessionIfNeeded()
        setupGraph()
        configureDefaults()
        
        do {
            try engine.start()
            player.volume = Float(volume)
            applyFX() // initial bypass states
            print("Engine started")
        } catch {
            print("Engine start error:", error)
        }
    }
    
    deinit {
        stopWahLFO()
        releaseSecurityScopedURL()
    }
    
    // Setup
    private func setupAudioSessionIfNeeded() {
#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("AudioSession error:", error)
        }
#endif
    }
    
    private func setupGraph() {
        engine.attach(player)
        engine.attach(distortionUnit)
        engine.attach(delayUnit)
        engine.attach(wahUnit)
        
        // Chain: player -> distortion -> delay -> wah -> fuzz -> metal -> mainMixer
        engine.connect(player, to: distortionUnit, format: nil)
        engine.connect(distortionUnit, to: delayUnit, format: nil)
        engine.connect(delayUnit, to: wahUnit, format: nil)
        engine.connect(wahUnit, to: engine.mainMixerNode, format: nil)
    }
    
    private func configureDefaults() {
        if uiLevel == .basic {
            distAmount = 0
            delayTime = 0
            wahPedal = 0
        }
        // Dist 參數
        distortionUnit.loadFactoryPreset(.drumsBitBrush)
        distortionUnit.preGain = Float(distAmount * 18.0)
        
        // Delay 參數
        delayUnit.delayTime = delayTime
        delayUnit.feedback = Float(delayFeedback)
        delayUnit.wetDryMix = Float(delayMix * 100)
        
        // Wah 參數
        let band = wahUnit.bands[0]
        band.filterType = .bandPass
        band.bypass = false
        band.gain = Float(wahResonanceGain)
        band.bandwidth = Float(wahBandwidth)
        band.frequency = Float(clamp(wahMinFreq, 200, 6000))
    }
    
    // MARK: Public: File Load
    func loadAVAudio(url: URL) {
        releaseSecurityScopedURL()
        
        // sandbox: try security-scoped
        let ok = url.startAccessingSecurityScopedResource()
        securityScopedURL = ok ? url : nil
        
        do {
            audioFile = try AVAudioFile(forReading: url)
            loadedFilename = url.lastPathComponent
            print("Loaded:", loadedFilename)
        } catch {
            print("Load failed:", error)
            loadedFilename = "Load failed"
        }
        
        // If startAccessing failed, don't keep it
        if !ok { securityScopedURL = nil }
    }
    
    private func releaseSecurityScopedURL() {
        if let u = securityScopedURL {
            u.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
    }
    
    // MARK: Public: Transport
    func playOrStop() {
        guard let file = audioFile else {
            print("No audio file loaded")
            return
        }
        
        if isPlaying {
            player.stop()
            isPlaying = false
            // wah LFO can keep running; but we can stop to save CPU
            stopWahLFO()
        } else {
            applyFX() // ensure bypass + params correct before play
            player.stop()
            player.scheduleFile(file, at: nil, completionHandler: nil)
            player.play()
            isPlaying = true
            
            // restart wah if needed
            if wahOn && wahMode == .lfo { startWahLFO() }
        }
    }
    
    func setAllOff() {
        distOn = false
        delayOn = false
        wahOn = false
        applyFX()
    }
    
    // MARK: FX Core
    private func applyFX() {
        // 1) bypass by on/off
        distortionUnit.bypass = !distOn
        delayUnit.bypass = !delayOn
        wahUnit.bypass = !wahOn
        
        // 2) distortion params
        if distOn {
            // distAmount 0...1 -> preGain 0...18
            let pg = distAmount * 18.0
            distortionUnit.preGain = Float(pg)
            // wetDryMix 0...100
            distortionUnit.wetDryMix = Float(clamp(distMix, 0, 1) * 100.0)
        }
        
        // 3) delay params
        if delayOn {
            delayUnit.wetDryMix = Float(clamp(delayMix, 0, 1) * 100.0)
            delayUnit.delayTime = clamp(delayTime, 0.01, 2.0)
            delayUnit.feedback = Float(clamp(delayFeedback, 0, 95))
        }
        
        // 4) wah params
        updateWahBandShape()
        
        if wahOn {
            if wahMode == .lfo {
                // start LFO (if playing)
                if isPlaying { startWahLFO() }
                else { stopWahLFO() }
            } else {
                // manual: set frequency by pedal and stop timer
                stopWahLFO()
                setWahFrequencyByPedal()
            }
        } else {
            stopWahLFO()
        }
    }
    
    private func updateWahBandShape() {
        let band = wahUnit.bands[0]
        band.gain = Float(clamp(wahResonanceGain, 0, 24))
        band.bandwidth = Float(clamp(wahBandwidth, 0.2, 2.0))
    }
    
    private func setWahFrequencyByPedal() {
        let band = wahUnit.bands[0]
        let minF = clamp(wahMinFreq, 200, 3000)
        let maxF = clamp(wahMaxFreq, minF + 50, 6000)
        let p = clamp(wahPedal, 0, 1)
        let shaped = p * p
        let f = minF + shaped * (maxF - minF)
        band.frequency = Float(clamp(f, 200, 6000))
    }
    
    // MARK: Wah LFO
    private func startWahLFO() {
        stopWahLFO()
        
        wahPhase = 0
        let fps = 60.0
        wahTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            self?.tickWahLFO(dt: 1.0 / fps)
        }
        if let t = wahTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
    
    private func stopWahLFO() {
        wahTimer?.invalidate()
        wahTimer = nil
    }
    
    private func tickWahLFO(dt: Double) {
        guard wahOn, wahMode == .lfo else { return }
        
        let band = wahUnit.bands[0]
        
        let minF = clamp(wahMinFreq, 200, 3000)
        let maxF = clamp(wahMaxFreq, minF + 50, 6000)
        let depth = clamp(wahDepth, 0, 1)
        let rate = clamp(wahRate, 0.05, 12.0)
        
        // phase += 2π f dt
        wahPhase += (2.0 * Double.pi) * rate * dt
        
        // LFO -1..1
        let s = sin(wahPhase)
        
        // Map to 0..1, apply depth
        let t = (s + 1.0) * 0.5
        let mixT = (1.0 - depth) * 0.5 + depth * t
        
        // Frequency sweep
        let f = minF + mixT * (maxF - minF)
        band.frequency = Float(clamp(f, 200, 6000))
    }
    
    // MARK: Helpers
    private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }
    //record
    
    func startRecording() {
        guard !isRecording else { return }
        
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HH-mm"
        let fileName = "SFX_\(formatter.string(from: Date())).m4a"
        
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(fileName)
        
        do {
            recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
            currentRecordingURL = url
        } catch {
            print("File create error:", error)
            return
        }
        
        engine.mainMixerNode.installTap(onBus: 0,
                                        bufferSize: 1024,
                                        format: format) { buffer, _ in
            try? self.recordingFile?.write(from: buffer)
        }
        self.isRecording = true
    }
        
    func stopRecording() {
        guard isRecording else { return }
            
        engine.mainMixerNode.removeTap(onBus: 0)
        recordingFile = nil
        isRecording = false
            
        
    }
}
