import MusicMemoCore
import SwiftUI

/// 1曲の編集画面。上から「トップバー／セクション行／譜面ビュー／全体ビュー／入力パレット」の5段で、譜面ビューだけが高さ可変。
/// 曲の変更はファイル（document）へ書き戻し、DocumentGroup が自動で保存する。
struct SketchScreen: View {
    @Binding var document: SketchDocument
    /// 開いているファイル。曲名はファイル名と同じにする（未保存なら nil）。
    let fileURL: URL?

    /// ファイルを開いたときに1回だけ作る。
    /// （ファイルの中身が変わるたびにこのビューは作り直されるので、init で作るとストアと音源の読み込みが何度も走る）
    @State private var store: SketchStore?

    var body: some View {
        if let store {
            SketchEditor(store: store, document: $document, fileURL: fileURL)
        } else {
            Palette.background
                .onAppear { store = SketchStore(file: document.file) }
        }
    }
}

/// 編集画面の本体。
private struct SketchEditor: View {
    let store: SketchStore
    @Binding var document: SketchDocument
    let fileURL: URL?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topBar
            VStack(spacing: Metrics.scoreAreaSpacing) {
                sectionRow
                scoreView
                overview
            }
            .padding(.horizontal, Metrics.outerHorizontalPadding)
            .padding(.top, Metrics.scoreAreaTopPadding)
            .padding(.bottom, Metrics.scoreAreaBottomPadding)
            inputPalette
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .focusedSceneValue(\.sketchStore, store)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)  // トップバーは自前で持つ
        #endif
        .onAppear { syncTitle() }
        .onChange(of: fileURL) { syncTitle() }
        // 曲の変更と、開き直したときに戻す画面状態をファイルへ書き戻す
        .onChange(of: store.sketch) { document.file.sketch = store.sketch }
        .onChange(of: store.savedEditorState) { document.file.editor = store.savedEditorState }
        #if DEBUG
        .onAppear {
            DebugInputDemo.runIfRequested(store)
            DebugPlaybackCheck.runIfRequested(store)
        }
        #endif
    }

    private var topBar: some View {
        TopBarView(sketch: store.sketch, isPlaying: store.isPlaying, isMetronomeOn: store.isMetronomeOn,
                   canUndo: store.canUndo, canRedo: store.canRedo,
                   onBack: { store.stopPlayback(); dismiss() },
                   onTogglePlayback: store.togglePlayback, onToggleMetronome: store.toggleMetronome,
                   onToggleLoop: store.toggleLoop, onUndo: store.undo, onRedo: store.redo,
                   onExport: { Exporter.export(store.sketch, format: $0) })
    }

    /// 曲名をファイル名にそろえる（書き出すファイルの名前にも使う）。
    private func syncTitle() {
        guard let name = fileURL?.deletingPathExtension().lastPathComponent, store.sketch.title != name else { return }
        store.sketch.title = name
    }

    private var sectionRow: some View {
        SectionBarView(store: store)
    }

    private var scoreView: some View {
        ScoreView(store: store)
            .frame(maxHeight: .infinity)
            .background(Palette.paper)
            .clipShape(.rect(cornerRadius: Metrics.panelCornerRadius))
        .shadow(color: Color(hex: 0x14161A, opacity: 0.06), radius: 1, y: 1)
    }

    private var overview: some View {
        OverviewView(store: store)
            .frame(height: Metrics.overviewHeight, alignment: .bottom)
            .padding(.leading, Metrics.trackHeaderWidth)
            .padding(.trailing, Metrics.verticalScrollbarWidth)
    }

    private var inputPalette: some View {
        InputPaletteView(store: store)
    }

    private func placeholder(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.inkTertiary)
    }
}

#Preview(traits: .fixedLayout(width: 1194, height: 834)) {
    let sketch = SampleData.sketch03()
    SketchScreen(document: .constant(SketchDocument(file: SketchFile(sketch: sketch, editor: SampleData.editorState(for: sketch)))), fileURL: nil)
}
