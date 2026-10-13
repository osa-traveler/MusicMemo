import AVFoundation
import MusicMemoCore
import os

/// 鍵盤の音と再生。トラックごとに AVAudioUnitSampler を持ち、GM 音色を読み込む（音源は soundBankURL() を参照）。
/// 再生は自前のスケジューラ（PlaybackScheduler）で同じサンプラーを鳴らす。メトロノームはドラムキットのウッドブロック。
/// （AVAudioSequencer は、再生中にレンダリングのスレッドで落ちることがあったため使わない）
/// 音声の操作はすべて専用のキューで行い、画面の処理を止めない。
/// 将来は外部 MIDI 音源や AU に差し替えられるよう、ここだけで音を扱う。
final class SoundEngine: @unchecked Sendable {
    static let soundFontName = "FluidR3_GM"
    /// GM のメロディ楽器のバンク（kAUSampleBankMSB_Melodic。C のマクロなので値で書く）。
    private static let melodicBankMSB: UInt8 = 0x79
    /// GM のドラムのバンク（kAUSampleBankMSB_Percussion）。
    private static let percussionBankMSB: UInt8 = 0x78

    private let queue = DispatchQueue(label: "MusicMemo.SoundEngine")
    private let engine = AVAudioEngine()
    private var samplers: [UUID: AVAudioUnitSampler] = [:]
    private var programs: [UUID: Int] = [:]
    private let soundFontURL = SoundEngine.soundBankURL()

    /// 使う音源。同梱の FluidR3_GM（Scripts/fetch-soundfont.sh で取得）。
    /// 無ければ Mac では macOS 標準の音源（gs_instruments.dls）を使う。
    /// （GeneralUser GS は AVAudioUnitSampler で再生すると落ちることがあったため使わない。docs/ROADMAP.md）
    private static func soundBankURL() -> URL? {
        #if DEBUG
        // 開発用：MUSICMEMO_SOUNDBANK で音源ファイルを差し替える（音源ごとの不具合の切り分け用）
        if let path = ProcessInfo.processInfo.environment["MUSICMEMO_SOUNDBANK"] {
            return URL(fileURLWithPath: path)
        }
        #endif
        if let bundled = Bundle.main.url(forResource: soundFontName, withExtension: "sf2") {
            return bundled
        }
        #if os(macOS)
        let systemBank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        if FileManager.default.fileExists(atPath: systemBank.path) {
            return systemBank
        }
        #endif
        return nil
    }

    private let log = Logger(subsystem: "MusicMemo", category: "Sound")

    // 再生
    private let scheduler = PlaybackScheduler()
    private var clickSampler: AVAudioUnitSampler?

    init() {
        if let soundFontURL {
            log.info("音源: \(soundFontURL.lastPathComponent, privacy: .public)")
        } else {
            log.warning("FluidR3_GM.sf2 が見つからない（Scripts/fetch-soundfont.sh で取得）。音は鳴らない。")
        }
        // メトロノームの音も起動時に読み込んでおく（エンジンが動いている間の読み込みを避ける）
        queue.async { [self] in _ = metronomeSampler() }
        #if DEBUG
        // 開発用：MUSICMEMO_SILENT=1 なら出力を消す（再生の自動確認で音を出さない）
        if ProcessInfo.processInfo.environment["MUSICMEMO_SILENT"] == "1" {
            queue.async { [self] in engine.mainMixerNode.outputVolume = 0 }
        }
        #endif
    }

    /// トラックの音色・音量・パンをそろえる（足りないサンプラーは作って音色を読み込む）。
    func prepare(_ tracks: [Track]) {
        let settings = tracks.map { ($0.id, $0.program, $0.volume, $0.pan) }
        queue.async { [self] in
            for (id, program, volume, pan) in settings {
                let sampler = sampler(for: id)
                if programs[id] != program {
                    load(program: program, into: sampler)
                    programs[id] = program
                }
                sampler.volume = Float(volume) / 100
                sampler.pan = Float(pan) / 64
            }
        }
    }

    func noteOn(_ pitch: MIDINote, track id: UUID, velocity: UInt8 = 96) {
        queue.async { [self] in
            guard soundFontURL != nil, let sampler = samplers[id] else { return }
            startEngineIfNeeded()
            sampler.startNote(UInt8(clamping: pitch), withVelocity: velocity, onChannel: 0)
        }
    }

    func noteOff(_ pitch: MIDINote, track id: UUID) {
        queue.async { [self] in
            samplers[id]?.stopNote(UInt8(clamping: pitch), onChannel: 0)
        }
    }

    // MARK: 再生

    /// score を start の位置から再生する（再生中なら内容を差し替えて、同じ位置から続ける）。
    func play(_ score: PlaybackScore, from start: Tick) {
        queue.async { [self] in
            guard soundFontURL != nil else { return }
            startEngineIfNeeded()
            var outputs: [UUID: AVAudioUnitSampler] = [:]
            for part in score.parts { outputs[part.id] = sampler(for: part.id) }
            scheduler.start(score, from: start, outputs: outputs, click: metronomeSampler())
        }
    }

    func stop() {
        scheduler.stop()
    }

    /// 再生位置（tick）。ループ中は再生範囲の中に折り返した位置。止まっていれば nil。
    func playheadTick() -> Tick? {
        scheduler.position()
    }

    /// 再生中にミュート・ソロ・メトロノームを切り替える。
    func updateMix(_ score: PlaybackScore) {
        scheduler.updateMix(score)
    }

    private func metronomeSampler() -> AVAudioUnitSampler {
        if let clickSampler { return clickSampler }
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        if let url = soundFontURL {
            do {
                try sampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: Self.percussionBankMSB, bankLSB: 0)
            } catch {
                log.error("メトロノームの音を読み込めない: \(error.localizedDescription)")
            }
        }
        clickSampler = sampler
        return sampler
    }

    #if DEBUG
    /// 開発用：各サンプラーの出力レベル（RMS）を seconds 秒測ってログに出す。
    func debugMeasureLevels(seconds: Double, names: [UUID: String]) {
        final class Levels: @unchecked Sendable {
            let lock = NSLock()
            var sums: [String: (Double, Int)] = [:]
        }
        queue.async { [self] in
            var list: [(String, AVAudioUnitSampler)] = samplers.map { (names[$0.key] ?? "?", $0.value) }
            if let clickSampler { list.append(("メトロノーム", clickSampler)) }
            let nodes = list
            let levels = Levels()
            for (name, sampler) in nodes {
                sampler.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
                    let data = buffer.floatChannelData![0]
                    var sum = 0.0
                    for i in 0..<Int(buffer.frameLength) { sum += Double(data[i] * data[i]) }
                    levels.lock.lock()
                    let old = levels.sums[name] ?? (0, 0)
                    levels.sums[name] = (old.0 + sum, old.1 + Int(buffer.frameLength))
                    levels.lock.unlock()
                }
            }
            queue.asyncAfter(deadline: .now() + seconds) { [self] in
                for (_, sampler) in nodes { sampler.removeTap(onBus: 0) }
                levels.lock.lock()
                for (name, value) in levels.sums.sorted(by: { $0.key < $1.key }) {
                    let rms = (value.0 / Double(max(value.1, 1))).squareRoot()
                    log.info("出力レベル \(name, privacy: .public): RMS \(rms, format: .fixed(precision: 4))")
                }
                levels.lock.unlock()
            }
        }
    }
    #endif

    // MARK: 内部（queue 上で呼ぶ）

    private func sampler(for id: UUID) -> AVAudioUnitSampler {
        if let sampler = samplers[id] { return sampler }
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        samplers[id] = sampler
        return sampler
    }

    private func load(program: Int, into sampler: AVAudioUnitSampler) {
        guard let url = soundFontURL else { return }
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: UInt8(clamping: program),
                bankMSB: Self.melodicBankMSB,
                bankLSB: 0
            )
            log.info("音色を読み込んだ（program \(program)）")
        } catch {
            log.error("音色を読み込めない（program \(program)）: \(error.localizedDescription)")
        }
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("オーディオセッションを開始できない: \(error.localizedDescription)")
        }
        #endif
        do {
            try engine.start()
        } catch {
            log.error("オーディオエンジンを開始できない: \(error.localizedDescription)")
        }
    }
}

/// 再生する内容（曲から作る。タイは1つの音にまとめておく）。
struct PlaybackScore: Sendable {
    struct Part: Sendable {
        var id: UUID
        var notes: [(start: Tick, duration: Tick, pitch: MIDINote)]
        var isMuted: Bool
        var isSoloed: Bool
    }

    var tempo: Double
    var parts: [Part]
    var ticksPerBeat: Tick
    var ticksPerBar: Tick
    var totalTicks: Tick
    /// ループする範囲（ループがオフなら nil）。
    var loop: Range<Tick>?
    var metronome: Bool

    init(_ sketch: Sketch, metronome: Bool) {
        tempo = sketch.tempo
        parts = sketch.tracks.map { track in
            Part(
                id: track.id,
                notes: MIDIExporter.mergedNotes(track.notes).compactMap { note in
                    note.pitch.map { (note.start, note.duration, $0) }
                },
                isMuted: track.isMuted,
                isSoloed: track.isSoloed
            )
        }
        ticksPerBeat = sketch.timeSignature.ticksPerBeat
        ticksPerBar = sketch.timeSignature.ticksPerBar
        totalTicks = sketch.totalTicks
        loop = sketch.isLooping ? sketch.playRange : nil
        self.metronome = metronome
    }
}
