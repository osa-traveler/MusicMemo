import CoreGraphics
import MusicMemoCore

/// 譜面の座標計算。音符・ルーラ・編集位置はすべてここを通すので位置が必ず揃う。
/// 基準値は倍率100%（docs/reference/01_main_100.html）。
struct ScoreLayout {
    var zoom: CGFloat
    var timeSignature: TimeSignature
    var keySignature: KeySignature
    var barCount: Int

    // MARK: 縦

    var staffSpace: CGFloat { 8 * zoom }
    /// 1トラック行の最小の高さ。
    var minimumRowHeight: CGFloat { 90 * zoom }
    /// 行の高さが最小値のときの、第5線（一番上の線）の y。
    private var baseTopLineY: CGFloat { 40 * zoom }
    /// コードネームのベースライン（第5線からの距離）。
    var chordSymbolOffset: CGFloat { 16 * zoom }

    /// 入力中の小節の塗り（行内の上下位置）。
    func inputBarRect(bar: Int, rowHeight: CGFloat) -> CGRect {
        let top = (rowHeight - minimumRowHeight) / 2 + 14 * zoom
        return CGRect(x: barLineX(bar: bar) + 2 * zoom, y: top, width: barWidth - 4 * zoom, height: 74 * zoom)
    }

    /// コードネームの左端（音符の位置からの距離）。
    var chordSymbolLeading: CGFloat { -10 * zoom }

    /// 行の高さに応じた第1線（一番下の線）の y。余った高さは上下に均等に配る。
    func bottomLineY(rowHeight: CGFloat) -> CGFloat {
        (rowHeight - minimumRowHeight) / 2 + baseTopLineY + staffSpace * 4
    }

    /// 五線上の位置（第1線 = 0、1段 = 半間隔）の y。
    func y(staffPosition: Int, bottomLineY: CGFloat) -> CGFloat {
        bottomLineY - CGFloat(staffPosition) * staffSpace / 2
    }

    // MARK: 横

    /// 左端に固定する音部記号の位置。
    var clefX: CGFloat { 8 * zoom }
    var keySignatureX: CGFloat { 34 * zoom }
    var keySignatureAdvance: CGFloat { 9 * zoom }

    /// 左端に固定する領域（音部記号＋調号）の幅。調号が無いとき 56pt。
    var stickyWidth: CGFloat {
        let count = CGFloat(keySignature.letters.count)
        return max(56 * zoom, keySignatureX + count * keySignatureAdvance + 10 * zoom)
    }

    /// 拍子記号（曲頭のみ）の幅。
    var timeSignatureWidth: CGFloat { 24 * zoom }

    /// 1小節目の小節頭の x（コンテンツ座標）。
    var contentLeading: CGFloat { stickyWidth + timeSignatureWidth }

    /// 小節線から1拍目までの余白。
    var barLead: CGFloat { 28 * zoom }
    var barTrail: CGFloat { 2 * zoom }
    /// 1tick あたりの幅（100%で4分音符 = 48pt）。
    var pointsPerTick: CGFloat { 0.1 * zoom }

    var barWidth: CGFloat {
        barLead + CGFloat(timeSignature.ticksPerBar) * pointsPerTick + barTrail
    }

    var contentWidth: CGFloat { barLineX(bar: barCount + 1) + 8 * zoom }

    /// 小節の先頭の小節線の x（小節番号は1始まり）。
    func barLineX(bar: Int) -> CGFloat {
        contentLeading + CGFloat(bar - 1) * barWidth
    }

    /// 音符・編集位置の x。
    func x(tick: Tick) -> CGFloat {
        let bar = timeSignature.bar(containing: tick)
        let inBar = tick - timeSignature.startTick(ofBar: bar)
        return barLineX(bar: bar) + barLead + CGFloat(inBar) * pointsPerTick
    }

    /// 再生範囲の端の x。小節頭なら小節線、それ以外は音符の位置（基準画面の再生範囲と点線に合わせる）。
    func boundaryX(tick: Tick) -> CGFloat {
        let ticksPerBar = timeSignature.ticksPerBar
        if tick % ticksPerBar == 0 {
            return barLineX(bar: tick / ticksPerBar + 1)
        }
        return x(tick: tick)
    }

    /// boundaryX の逆。曲の終わり（最終小節の終わりの小節線）も選べる。
    func boundaryTick(atContentX x: CGFloat, grid: Tick) -> Tick {
        if x >= barLineX(bar: barCount + 1) - barTrail {
            return barCount * timeSignature.ticksPerBar
        }
        let bar = bar(atContentX: x)
        let inBar = (x - barLineX(bar: bar) - barLead) / pointsPerTick
        let clamped = min(max(inBar, 0), CGFloat(timeSignature.ticksPerBar))
        let snapped = Int((clamped / CGFloat(grid)).rounded()) * grid
        return timeSignature.startTick(ofBar: bar) + snapped
    }

    /// コンテンツ座標の x に最も近い位置（grid 単位に丸める）。小節線〜1拍目の余白は1拍目に寄せる。
    func tick(atContentX x: CGFloat, grid: Tick) -> Tick {
        let bar = bar(atContentX: x)
        let ticksPerBar = timeSignature.ticksPerBar
        let inBar = (x - barLineX(bar: bar) - barLead) / pointsPerTick
        let clamped = min(max(inBar, 0), CGFloat(ticksPerBar))
        let snapped = Int((clamped / CGFloat(grid)).rounded()) * grid
        let tick = timeSignature.startTick(ofBar: bar) + snapped
        return min(tick, barCount * ticksPerBar - grid)
    }

    /// コンテンツ座標の x にある小節（範囲外は端の小節）。
    func bar(atContentX x: CGFloat) -> Int {
        let index = Int(((x - contentLeading) / barWidth).rounded(.down)) + 1
        return min(max(index, 1), barCount)
    }
}
