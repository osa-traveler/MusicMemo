import AVFoundation
import MusicMemoCore

/// 再生のスケジューラ。専用の高優先度スレッドが数ミリ秒ごとに起き、時刻どおりにサンプラーへ発音・消音を送る。
/// 再生位置は経過時間から計算する。ループ・ミュート・ソロ・メトロノームもここで扱う。
final class PlaybackScheduler: @unchecked Sendable {
    /// メトロノームの音（GM ドラムの Hi / Low Wood Block）。
    static let clickAccent: UInt8 = 76
    static let clickBeat: UInt8 = 77

    private struct Event {
        var tick: Tick
        var isOn: Bool
        var pitch: UInt8
        var velocity: UInt8
        /// 鳴らすトラック（nil ならメトロノーム）。
        var part: UUID?
    }

    private struct Sounding: Hashable {
        var part: UUID?
        var pitch: UInt8
    }

    private let lock = NSLock()
    private var thread: Thread?
    private var isRunning = false

    // 以下は lock で守る
    private var events: [Event] = []
    private var nextIndex = 0
    private var outputs: [UUID: AVAudioUnitSampler] = [:]
    private var click: AVAudioUnitSampler?
    private var audibleParts: Set<UUID> = []
    private var metronome = false
    private var loop: Range<Tick>?
    private var totalTicks: Tick = 0
    private var ticksPerSecond: Double = 0
    /// 基準：startTick の位置を startTime（秒、単調増加の時計）に鳴らした。
    private var startTick: Tick = 0
    private var startTime: Double = 0
    private var sounding: Set<Sounding> = []

    /// score を start から鳴らす。再生中なら内容を差し替えて、その位置から続ける。
    func start(_ score: PlaybackScore, from start: Tick, outputs: [UUID: AVAudioUnitSampler], click: AVAudioUnitSampler) {
        lock.lock()
        silenceAll()
        self.outputs = outputs
        self.click = click
        events = Self.events(for: score)
        apply(score)
        loop = score.loop
        totalTicks = score.totalTicks
        ticksPerSecond = score.tempo / 60 * Double(Timing.ticksPerQuarter)
        reset(to: start, at: Self.now())
        let needsThread = !isRunning
        isRunning = true
        lock.unlock()

        if needsThread {
            let thread = Thread { [weak self] in self?.run() }
            thread.qualityOfService = .userInteractive
            thread.name = "MusicMemo.Playback"
            self.thread = thread
            thread.start()
        }
    }

    func stop() {
        lock.lock()
        isRunning = false
        silenceAll()
        lock.unlock()
        thread = nil
    }

    func position() -> Tick? {
        lock.lock()
        defer { lock.unlock() }
        return isRunning ? currentTick(at: Self.now()) : nil
    }

    func updateMix(_ score: PlaybackScore) {
        lock.lock()
        apply(score)
        // 聞こえなくなったトラックの音を止める
        for note in sounding where note.part.map({ !audibleParts.contains($0) }) ?? !metronome {
            output(for: note.part)?.stopNote(note.pitch, onChannel: 0)
            sounding.remove(note)
        }
        lock.unlock()
    }

    // MARK: 内部

    private static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private static func events(for score: PlaybackScore) -> [Event] {
        var events: [Event] = []
        for part in score.parts {
            for note in part.notes {
                let pitch = UInt8(clamping: note.pitch)
                events.append(Event(tick: note.start, isOn: true, pitch: pitch, velocity: 90, part: part.id))
                events.append(Event(tick: note.start + note.duration, isOn: false, pitch: pitch, velocity: 0, part: part.id))
            }
        }
        for tick in stride(from: 0, to: score.totalTicks, by: score.ticksPerBeat) {
            let accent = tick % score.ticksPerBar == 0
            let pitch = accent ? clickAccent : clickBeat
            events.append(Event(tick: tick, isOn: true, pitch: pitch, velocity: accent ? 120 : 85, part: nil))
            events.append(Event(tick: tick + Timing.ticksPerSixteenth, isOn: false, pitch: pitch, velocity: 0, part: nil))
        }
        // 同じ位置では消音を先に
        return events.sorted { ($0.tick, $0.isOn ? 1 : 0) < ($1.tick, $1.isOn ? 1 : 0) }
    }

    /// lock の中で呼ぶ。
    private func apply(_ score: PlaybackScore) {
        let anySolo = score.parts.contains { $0.isSoloed }
        audibleParts = Set(score.parts.filter { !$0.isMuted && (!anySolo || $0.isSoloed) }.map(\.id))
        metronome = score.metronome
    }

    /// lock の中で呼ぶ。
    private func reset(to tick: Tick, at time: Double) {
        startTick = tick
        startTime = time
        nextIndex = events.firstIndex { $0.tick >= tick } ?? events.count
    }

    /// lock の中で呼ぶ。
    private func currentTick(at time: Double) -> Tick {
        startTick + Int((time - startTime) * ticksPerSecond)
    }

    private func output(for part: UUID?) -> AVAudioUnitSampler? {
        part.map { outputs[$0] } ?? click
    }

    /// lock の中で呼ぶ。
    private func silenceAll() {
        for note in sounding {
            output(for: note.part)?.stopNote(note.pitch, onChannel: 0)
        }
        sounding.removeAll()
    }

    private func run() {
        while true {
            lock.lock()
            guard isRunning else {
                lock.unlock()
                return
            }
            let time = Self.now()
            var tick = currentTick(at: time)

            if let loop, tick >= loop.upperBound {
                // 範囲の終わり：鳴っている音を止めて、始点から（はみ出した時間はそのまま持ち越す）
                silenceAll()
                let overshoot = Double(tick - loop.upperBound) / ticksPerSecond
                reset(to: loop.lowerBound, at: time - overshoot)
                tick = currentTick(at: time)
            } else if loop == nil, tick >= totalTicks {
                silenceAll()
                isRunning = false
                lock.unlock()
                return
            }

            while nextIndex < events.count, events[nextIndex].tick <= tick {
                let event = events[nextIndex]
                nextIndex += 1
                if loop.map({ event.tick >= $0.upperBound }) == true { break }
                let key = Sounding(part: event.part, pitch: event.pitch)
                if event.isOn {
                    let audible = event.part.map { audibleParts.contains($0) } ?? metronome
                    guard audible, let output = output(for: event.part) else { continue }
                    if sounding.contains(key) { output.stopNote(event.pitch, onChannel: 0) }
                    output.startNote(event.pitch, withVelocity: event.velocity, onChannel: 0)
                    sounding.insert(key)
                } else if sounding.contains(key) {
                    output(for: event.part)?.stopNote(event.pitch, onChannel: 0)
                    sounding.remove(key)
                }
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.002)
        }
    }
}
