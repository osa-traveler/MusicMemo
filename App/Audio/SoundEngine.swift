import AVFoundation
import MusicMemoCore
import os

/// 鍵盤の音を鳴らす。トラックごとに AVAudioUnitSampler を持ち、GeneralUser GS（SoundFont）の GM 音色を読み込む。
/// 音声の操作はすべて専用のキューで行い、画面の処理を止めない。
/// 将来は外部 MIDI 音源や AU に差し替えられるよう、ここだけで音を扱う。
final class SoundEngine: @unchecked Sendable {
    static let soundFontName = "GeneralUser-GS"
    /// GM のメロディ楽器のバンク（kAUSampleBankMSB_Melodic。C のマクロなので値で書く）。
    private static let melodicBankMSB: UInt8 = 0x79

    private let queue = DispatchQueue(label: "MusicMemo.SoundEngine")
    private let engine = AVAudioEngine()
    private var samplers: [UUID: AVAudioUnitSampler] = [:]
    private var programs: [UUID: Int] = [:]
    private let soundFontURL = Bundle.main.url(forResource: soundFontName, withExtension: "sf2")
    private let log = Logger(subsystem: "MusicMemo", category: "Sound")

    init() {
        if soundFontURL == nil {
            log.warning("GeneralUser-GS.sf2 が見つからない（Scripts/fetch-soundfont.sh で取得）。音は鳴らない。")
        }
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
