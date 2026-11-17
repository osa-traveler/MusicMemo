#if DEBUG
import Foundation
import MusicMemoCore
import OSLog

/// 開発用：MUSICMEMO_SECTION_DEMO でセクションの操作を自動で流す。結果はログ（category == "SectionDemo"）に出す。
/// - 1：編集位置のセクションの名前と長さを開く（撮影用。開くのは SectionBarView）
/// - 2：曲の最後に追加・分ける・名前・長さ・複製・つなげる・消すを流して、その状態で止める。
///   最後に元に戻す／やり直すで戻るかを確かめる
enum DebugSectionDemo {
    static var mode: String? {
        ProcessInfo.processInfo.environment["MUSICMEMO_SECTION_DEMO"]
    }

    private static let log = Logger(subsystem: "MusicMemo", category: "SectionDemo")

    private static func describe(_ sketch: Sketch) -> String {
        let sections = sketch.sections.map { "\($0.name) \($0.startBar)–\($0.bars.upperBound)" }.joined(separator: ", ")
        let notes = sketch.tracks.reduce(0) { $0 + $1.notes.filter { !$0.isRest }.count }
        return "\(sketch.barCount)小節 [\(sections)] 音符\(notes) コード\(sketch.chords.count)"
    }

    @MainActor
    static func runIfRequested(_ store: SketchStore) {
        guard mode == "2" else { return }
        let before = store.sketch
        log.info("前: \(describe(before), privacy: .public)")
        var steps = 0
        let step = { (title: String, action: () -> Void) in
            action()
            steps += 1
            log.info("\(title, privacy: .public): \(describe(store.sketch), privacy: .public)")
        }
        let sabi = { store.sketch.sections.first { $0.name == "サビ" }!.id }
        step("サビを複製") { store.duplicateSection(sabi()) }
        step("曲の最後に追加") { store.appendSection() }
        step("名前をアウトロに") { store.renameSection(store.sketch.sections.last!.id, to: "アウトロ") }
        step("アウトロを4小節に") { store.resizeSection(store.sketch.sections.last!.id, to: 4) }
        store.jump(toBar: 5)
        step("5小節目から分ける") { store.splitSectionAtEditPosition() }
        step("分けたセクションを間奏に") { store.renameSection(store.currentSection!.id, to: "間奏") }
        step("Aメロを2小節に（3〜4小節目が消える）") { store.resizeSection(store.sketch.sections.first!.id, to: 2) }
        let after = store.sketch
        for _ in 0..<steps { store.undo() }
        log.info("\(steps)回元に戻した: \(store.sketch == before ? "元どおり" : "違う: " + describe(store.sketch), privacy: .public)")
        for _ in 0..<steps { store.redo() }
        log.info("\(steps)回やり直した: \(store.sketch == after ? "同じ" : "違う: " + describe(store.sketch), privacy: .public)")
        store.jump(toBar: 1)
    }
}
#endif
