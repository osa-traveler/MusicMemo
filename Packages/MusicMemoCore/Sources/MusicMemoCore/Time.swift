/// 時間の位置。4分音符 = 480 tick（3連符も整数で表せる）。
public typealias Tick = Int

public enum Timing {
    public static let ticksPerQuarter: Tick = 480
}
