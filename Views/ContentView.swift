import SwiftUI
import UniformTypeIdentifiers


// MARK: - Toggle Button
struct FXToggleButton: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isOn ? Color.white.opacity(0.20) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isOn ? Color.white.opacity(0.60) : Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isOn ? 0.35 : 0.18), radius: isOn ? 10 : 6, y: 6)
        .foregroundStyle(isOn ? .white : .white.opacity(0.9))
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}

// MARK: - Unified Slider Row (NO generic Slider param -> avoids your errors)
struct RowSlider: View {
    let title: String
    let valueText: String
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double
    var fixedTitleWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: fixedTitleWidth, alignment: .leading)

            Slider(value: $value, in: range, step: step)
                .tint(.blue)

            Text(valueText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
    }
}

struct ContentView: View {
    @StateObject private var audio = AudioManager.shared
    @State private var showImporter = false
    @State private var showExporter = false

    // iPhone 自適應欄位
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 110), spacing: 12)]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.96), Color.black.opacity(0.80)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    uiLevelPicker
                    statusBlock
                    transportButtons
                    fxGrid
                    if audio.uiLevel == .basic {
                        basicLimitControls
                    }
                    if audio.uiLevel == .pro {
                        proControls
                    }

                    volumeControl
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: UI Blocks

    private var header: some View {
        Text("SFX.v3")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.top, 8)
    }

    private var uiLevelPicker: some View {
        VStack(spacing: 8) {
            if audio.uiLevel == .basic {
                DollSceneView(audio: audio)
                    .padding(.horizontal)
                
            }
            Picker("模式", selection: $audio.uiLevel) {
                Text("基礎").tag(UILevel.basic)
                Text("進階").tag(UILevel.pro)
            }
            .pickerStyle(.segmented)
            Button(audio.isRecording ? "停止錄音" : "錄音") {
                if audio.isRecording {
                    audio.stopRecording()
                    showExporter = true
                } else {
                    audio.startRecording()
                }
            }
            .buttonStyle(.borderedProminent)

            Text(audio.uiLevel == .basic ? "一鍵套用效果（只開/關）" : "調整參數，做出你的音色")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: audio.currentRecordingURL.map { AudioDocument(url: $0) },
            contentType: .mpeg4Audio,
            defaultFilename: audio.currentRecordingURL?.lastPathComponent ?? "SFX_Record.m4a"
        ) { result in
            switch result {
            case .success:
                print("Saved successfully")
            case .failure(let error):
                print(error)
            }
        }
    }
    

    private var statusBlock: some View {
        VStack(spacing: 6) {
            Text(audio.isPlaying ? "狀態：播放中" : "狀態：停止")
                .foregroundStyle(.secondary)

            Text("已載入：\(audio.loadedFilename)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.top, 6)
    }
    private var transportButtons: some View {
        HStack(spacing: 12) {
            Button("選擇音檔") { showImporter = true }
                .buttonStyle(.bordered)
                .controlSize(.large)

            Button(audio.isPlaying ? "停止" : "播放") { audio.playOrStop() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { audio.loadAVAudio(url: url) }
            case .failure(let error):
                print("Import error:", error)
            }
        }
        .padding(.top, 8)
    }

    private var fxGrid: some View {
        VStack(spacing: 10) {

            HStack {
                Text("效果（可疊加）")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button("Clean") { audio.setAllOff() }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.bordered)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                FXToggleButton(title: "Dist",  isOn: audio.distOn)  { audio.distOn.toggle() }
                FXToggleButton(title: "Delay", isOn: audio.delayOn) { audio.delayOn.toggle() }
                FXToggleButton(title: "Wah",   isOn: audio.wahOn)   { audio.wahOn.toggle() }
            }
        }
        .padding(.top, 12)
    }
    private var basicLimitControls: some View {
        GroupBox("Basic 模式上限") {
            VStack(spacing: 12) {

                RowSlider(
                    title: "Dist Max",
                    valueText: String(format: "%.2f", audio.basicDistMax),
                    range: 0...1,
                    step: 0.01,
                    value: $audio.basicDistMax
                )

                RowSlider(
                    title: "Wah Max",
                    valueText: String(format: "%.2f", audio.basicWahMax),
                    range: 0...1,
                    step: 0.01,
                    value: $audio.basicWahMax
                )

                RowSlider(
                    title: "Delay Max",
                    valueText: String(format: "%.2f", audio.basicDelayMax),
                    range: 0...1,
                    step: 0.01,
                    value: $audio.basicDelayMax
                )
            }
            .padding(.vertical, 6)
        }
    }


    private var proControls: some View {
        VStack(spacing: 14) {
            

            if audio.distOn {
                GroupBox("Distortion") {
                    VStack(spacing: 12) {
                        RowSlider(
                            title: "Drive",
                            valueText: String(format: "%.2f", audio.distAmount),
                            range: 0...1,
                            step: 0.01,
                            value: $audio.distAmount
                        )
                        RowSlider(
                            title: "Mix",
                            valueText: String(format: "%.2f", audio.distMix),
                            range: 0...1,
                            step: 0.01,
                            value: $audio.distMix
                        )
                    }
                    .padding(.vertical, 6)
                }
            }
            if audio.delayOn {
                GroupBox("Delay") {
                    VStack(spacing: 12) {
                        RowSlider(
                            title: "Mix",
                            valueText: String(format: "%.2f", audio.delayMix),
                            range: 0...1,
                            step: 0.01,
                            value: $audio.delayMix
                        )
                        RowSlider(
                            title: "Time",
                            valueText: String(format: "%.2f s", audio.delayTime),
                            range: 0.01...2.0,
                            step: 0.01,
                            value: $audio.delayTime
                        )
                        RowSlider(
                            title: "FB",
                            valueText: "\(Int(audio.delayFeedback))%",
                            range: 0...95,
                            step: 1,
                            value: $audio.delayFeedback
                        )
                    }
                    .padding(.vertical, 6)
                }
            }

            if audio.wahOn {
                GroupBox("Wah") {
                    VStack(spacing: 12) {
                        Picker("Wah Mode", selection: $audio.wahMode) {
                            Text("Auto").tag(WahMode.lfo)
                            Text("Pedal").tag(WahMode.manual)
                        }
                        .pickerStyle(.segmented)

                        RowSlider(
                            title: "Min",
                            valueText: "\(Int(audio.wahMinFreq)) Hz",
                            range: 200...1200,
                            step: 10,
                            value: $audio.wahMinFreq
                        )
                        RowSlider(
                            title: "Max",
                            valueText: "\(Int(audio.wahMaxFreq)) Hz",
                            range: 800...4000,
                            step: 10,
                            value: $audio.wahMaxFreq
                        )
                        RowSlider(
                            title: "Reso",
                            valueText: String(format: "%.1f", audio.wahResonanceGain),
                            range: 0...24,
                            step: 0.5,
                            value: $audio.wahResonanceGain
                        )
                        RowSlider(
                            title: "Sharp",
                            valueText: String(format: "%.2f", audio.wahBandwidth),
                            range: 0.2...2.0,
                            step: 0.01,
                            value: $audio.wahBandwidth
                        )

                        if audio.wahMode == .lfo {
                            RowSlider(
                                title: "Rate",
                                valueText: String(format: "%.2f Hz", audio.wahRate),
                                range: 0.05...10.0,
                                step: 0.05,
                                value: $audio.wahRate
                            )
                            RowSlider(
                                title: "Depth",
                                valueText: String(format: "%.2f", audio.wahDepth),
                                range: 0...1,
                                step: 0.01,
                                value: $audio.wahDepth
                            )
                        } else {
                            Text("滑動 Pedal 來 Wah")
                                .foregroundStyle(.secondary)

                            RowSlider(
                                title: "Pedal",
                                valueText: String(format: "%.2f", audio.wahPedal),
                                range: 0...1,
                                step: 0.01,
                                value: $audio.wahPedal
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.top, 10)
        .groupBoxStyle(.automatic)
    }

    private var volumeControl: some View {
        GroupBox("Volume") {
            RowSlider(
                title: "Vol",
                valueText: String(format: "%.2f", audio.volume),
                range: 0...2,
                step: 0.01,
                value: $audio.volume
            )
            .padding(.vertical, 6)
        }
        .padding(.top, 10)
    }
}

#Preview {
    ContentView()
}


