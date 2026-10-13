import MusicMemoCore
import SwiftUI

/// 音高ブロック：見出し（コードトーン、戻って消す、オクターブ移動）＋2オクターブの鍵盤。
struct PianoKeyboardBlock: View {
    let store: SketchStore
    var onKeyDown: (MIDINote) -> Void = { _ in }
    var onKeyUp: (MIDINote) -> Void = { _ in }
    var onBackspace: () -> Void = {}
    /// いま押されている鍵（複数可）。
    var pressedKeys: Set<MIDINote> = []

    var body: some View {
        let lowest = store.keyboardLowestNote
        let chord = store.chordAtEditPosition
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PaletteHeading("音高")
                if let chord {
                    HStack(spacing: 4) {
                        Circle().fill(Palette.chord).frame(width: 8, height: 8)
                        Text("\(chord.symbol) のコードトーン")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.chord)
                }
                Spacer(minLength: 0)
                headerButton(action: onBackspace) {
                    Label("戻って消す", systemImage: "delete.left")
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                }
                .accessibilityLabel("直前の音符を消して戻る")
                headerButton(action: { store.shiftKeyboard(octaves: -1) }) {
                    Image(systemName: "chevron.left").frame(width: 44)
                }
                .accessibilityLabel("1オクターブ下げる")
                Text("\(Pitch.noteName(lowest))–\(Pitch.noteName(lowest + 23))")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 64)
                headerButton(action: { store.shiftKeyboard(octaves: 1) }) {
                    Image(systemName: "chevron.right").frame(width: 44)
                }
                .accessibilityLabel("1オクターブ上げる")
            }
            .frame(height: 32)

            PianoKeyboardView(
                lowestNote: lowest,
                chordTones: Set(chord?.pitchClasses ?? []),
                highlighted: pressedKeys.isEmpty ? Set([store.editor.previewPitch].compactMap { $0 }) : pressedKeys,
                onKeyDown: onKeyDown,
                onKeyUp: onKeyUp
            )
        }
    }

    private func headerButton(action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(Palette.ink)
                .frame(height: 32)
                .background(Palette.paper, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.rule, lineWidth: 1))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// 2オクターブの鍵盤（白鍵14・黒鍵10）。C の白鍵に音名、コードトーンにオレンジの点、押した鍵は青。
/// 鍵ごとに押す／離すを伝える（iPad では複数の指で同時に押せる）。
struct PianoKeyboardView: View {
    let lowestNote: MIDINote
    let chordTones: Set<PitchClass>
    let highlighted: Set<MIDINote>
    let onKeyDown: (MIDINote) -> Void
    let onKeyUp: (MIDINote) -> Void

    /// 白鍵の左端からの半音数（1オクターブ分）。
    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    /// 黒鍵：(半音数, 左にある白鍵の番号)
    private static let blackKeys = [(1, 0), (3, 1), (6, 3), (8, 4), (10, 5)]

    var body: some View {
        GeometryReader { geometry in
            let whiteWidth = geometry.size.width / 14
            let blackWidth = whiteWidth * 0.6
            let blackHeight = geometry.size.height * 0.58
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<14, id: \.self) { index in
                        let note = lowestNote + (index / 7) * 12 + Self.whiteOffsets[index % 7]
                        KeyView(note: note, isBlack: false, isChordTone: chordTones.contains(Pitch.pitchClass(of: note)),
                                isHighlighted: highlighted.contains(note), onKeyDown: onKeyDown, onKeyUp: onKeyUp)
                    }
                }
                ForEach(0..<10, id: \.self) { index in
                    let (offset, whiteIndex) = Self.blackKeys[index % 5]
                    let octave = index / 5
                    let note = lowestNote + octave * 12 + offset
                    KeyView(note: note, isBlack: true, isChordTone: chordTones.contains(Pitch.pitchClass(of: note)),
                            isHighlighted: highlighted.contains(note), onKeyDown: onKeyDown, onKeyUp: onKeyUp)
                        .frame(width: blackWidth, height: blackHeight)
                        .offset(x: CGFloat(octave * 7 + whiteIndex + 1) * whiteWidth - blackWidth / 2)
                }
            }
        }
    }
}

private struct KeyView: View {
    let note: MIDINote
    let isBlack: Bool
    let isChordTone: Bool
    let isHighlighted: Bool
    let onKeyDown: (MIDINote) -> Void
    let onKeyUp: (MIDINote) -> Void

    @State private var isPressed = false

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: isBlack ? 4 : 8, bottomTrailingRadius: isBlack ? 4 : 8)
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            if isChordTone {
                Circle().fill(Palette.chord).frame(width: 8, height: 8)
            }
            if !isBlack, Pitch.pitchClass(of: note) == 0 {
                Text(Pitch.noteName(note))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(.bottom, isBlack ? 6 : (Pitch.pitchClass(of: note) == 0 ? 6 : 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background, in: shape)
        .overlay {
            shape.strokeBorder(isHighlighted && !isBlack ? Palette.accent : Palette.ruleStrong,
                               lineWidth: isHighlighted && !isBlack ? 2 : (isBlack ? 0 : 1))
        }
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onKeyDown(note)
                }
                .onEnded { _ in
                    isPressed = false
                    onKeyUp(note)
                }
        )
        .accessibilityLabel(Pitch.noteName(note))
        .accessibilityAddTraits(.isButton)
    }

    private var background: Color {
        if isBlack { return isHighlighted ? Palette.accent : Palette.ink }
        return isHighlighted ? Palette.accentTintStrong : Palette.paper
    }
}
