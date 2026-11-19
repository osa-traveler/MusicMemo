import MusicMemoCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 譜面ビュー。全トラックを縦に並べ、各トラックを改行しない横一行の五線で表示する。
/// 左にトラック情報列（固定）、右に縦スクロール列。全トラックは同じ横位置でスクロールする。
struct ScoreView: View {
    @Bindable var store: SketchStore
    @State private var verticalPosition = ScrollPosition()
    @State private var vertical = VerticalMetrics()

    @State private var rowsAreaHeight: CGFloat = 0
    @State private var pinch: ZoomAnchor?
    @State private var isHUDVisible = false
    @State private var hudToken = 0
    @State private var didInitialScroll = false
    /// Mac のマウスドラッグ：始めた位置の音符（nil = まだ判定していない、.some(nil) = 音符の外から始めた）。
    @State private var mouseDragNote: Note.ID??
    /// iPad の範囲選択：長押しした位置。
    @State private var boxStart: CGPoint?
    /// 設定を開いているトラック。
    @State private var settingsTrackID: Track.ID?
    /// 消す前に確かめているトラック（音符があるとき）。
    @State private var pendingRemoval: Track?
    /// トラック情報のドラッグでの並べ替え。
    @State private var trackDrag: TrackDrag?

    private struct TrackDrag {
        var id: Track.ID
        var index: Int
        /// ドラッグを始めた位置（画面全体の座標の y）。
        var startY: CGFloat
        var offset: CGFloat = 0
    }

    /// 「＋ トラック」の行の高さ。
    private static let addTrackRowHeight: CGFloat = 40

    private struct VerticalMetrics: Equatable {
        var offset: CGFloat = 0
        var contentHeight: CGFloat = 0
        var visibleHeight: CGFloat = 0
    }

    /// ズームの基準：開始時の倍率と、指（マウス）の下にあった内容の位置。
    private struct ZoomAnchor {
        var zoom: Double
        var anchorX: CGFloat
        var contentX: CGFloat
        var anchorY: CGFloat
        var contentY: CGFloat
        var rowHeight: CGFloat
    }

    /// 再生範囲バー＋ルーラの高さ（倍率によらず一定）。
    private var headerHeight: CGFloat { Metrics.playRangeBarHeight + Metrics.rulerHeight }

    var body: some View {
        let layout = store.layout
        let horizontalOffset = store.horizontalOffset
        VStack(spacing: 0) {
            headerRow(height: Metrics.playRangeBarHeight) {
                PlayRangeHeaderView(range: store.sketch.playRange, timeSignature: store.sketch.timeSignature)
            } content: {
                PlayRangeView(layout: layout, offset: horizontalOffset, range: store.sketch.playRange, isLooping: store.sketch.isLooping) {
                    store.setPlayRange(start: $0, end: $1)
                }
            }

            headerRow(height: Metrics.rulerHeight) {
                RulerHeaderView(position: store.sketch.timeSignature.position(of: store.playheadTick ?? store.editor.editPosition))
            } content: {
                RulerView(layout: layout, offset: horizontalOffset, editPosition: store.playheadTick ?? store.editor.editPosition) {
                    store.setEditPosition($0)
                }
            }
            .overlay(alignment: .bottom) { Palette.rule.frame(height: 1) }

            GeometryReader { geometry in
                let rowHeight = rowHeight(available: geometry.size.height, zoom: store.editor.zoom)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        trackHeaders(rowHeight: rowHeight)
                        staffRows(layout: layout, rowHeight: rowHeight)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollPosition($verticalPosition)
                .onScrollGeometryChange(for: VerticalMetrics.self) { geometry in
                    VerticalMetrics(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        contentHeight: geometry.contentSize.height,
                        visibleHeight: geometry.containerSize.height
                    )
                } action: { _, metrics in
                    vertical = metrics
                    // 半分以上見えているトラックを数える
                    let row = self.rowHeight(available: metrics.visibleHeight, zoom: store.editor.zoom)
                    store.visibleTrackCount = min(Int((metrics.visibleHeight / row + 0.5).rounded(.down)), store.sketch.tracks.count)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsAreaHeight = $0 }
            }
        }
        .overlay { positionLines(layout: layout) }
        .padding(.trailing, Metrics.verticalScrollbarWidth)
        .overlay(alignment: .trailing) {
            VerticalScrollbar(offset: vertical.offset, contentHeight: vertical.contentHeight, visibleHeight: vertical.visibleHeight) {
                verticalPosition.scrollTo(y: $0)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 4)
        }
        .overlay(alignment: .top) {
            if isHUDVisible {
                ZoomHUD(zoom: store.editor.zoom,
                        onZoomOut: { store.stepZoom(-1) },
                        onZoomIn: { store.stepZoom(1) },
                        onReset: { store.setZoom(1) })
                    .padding(.top, 42)
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let anchor = pinch ?? zoomAnchor(at: value.startLocation)
                    pinch = anchor
                    applyZoom(anchor.zoom * value.magnification, from: anchor)
                }
                .onEnded { _ in pinch = nil }
        )
        .commandScrollZoom { factor, location in
            applyZoom(store.editor.zoom * factor, from: zoomAnchor(at: location))
        }
        #if DEBUG
        .onAppear {
            // 開発用：MUSICMEMO_TRACK_DEMO=1 なら先頭のトラックの設定を開く（撮影用）
            if DebugTrackDemo.mode == "1" { settingsTrackID = store.sketch.tracks.first?.id }
        }
        #endif
        .onChange(of: store.editor.zoom) {
            withAnimation(.easeOut(duration: 0.15)) { isHUDVisible = true }
            hudToken += 1
        }
        .task(id: hudToken) {
            guard hudToken > 0 else { return }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled, pinch == nil else { return }
            withAnimation(.easeOut(duration: 0.3)) { isHUDVisible = false }
        }
    }

    // MARK: ズーム

    /// location（譜面ビューの座標）にある内容を基準にする。トラック情報列や見出しの上なら、譜面部分の端を基準にする。
    private func zoomAnchor(at location: CGPoint) -> ZoomAnchor {
        let anchorX = max(location.x - Metrics.trackHeaderWidth, 0)
        let anchorY = max(location.y - headerHeight, 0)
        return ZoomAnchor(
            zoom: store.editor.zoom,
            anchorX: anchorX,
            contentX: store.horizontalOffset + anchorX,
            anchorY: anchorY,
            contentY: vertical.offset + anchorY,
            rowHeight: rowHeight(available: rowsAreaHeight, zoom: store.editor.zoom)
        )
    }

    /// 倍率を変え、基準の内容が同じ場所に残るよう縦横のスクロールを補正する。
    private func applyZoom(_ zoom: Double, from anchor: ZoomAnchor) {
        store.setZoom(zoom, anchorX: anchor.anchorX, contentX: anchor.contentX, baseZoom: anchor.zoom)
        let newRowHeight = rowHeight(available: rowsAreaHeight, zoom: store.editor.zoom)
        let maxY = max(newRowHeight * CGFloat(store.sketch.tracks.count) + Self.addTrackRowHeight - rowsAreaHeight, 0)
        let targetY = anchor.contentY * newRowHeight / max(anchor.rowHeight, 1) - anchor.anchorY
        verticalPosition.scrollTo(y: min(max(targetY, 0), maxY))
    }

    /// 再生範囲バー・ルーラの1段（左にトラック情報列と同じ幅の見出し）。
    private func headerRow(height: CGFloat, @ViewBuilder header: () -> some View, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 0) {
            header()
                .frame(width: Metrics.trackHeaderWidth, height: height)
                .overlay(alignment: .trailing) { Palette.rule.frame(width: 1) }
            content()
        }
        .frame(height: height)
        .background(Palette.paperMuted)
    }

    /// 再生範囲の青い点線（ルーラから全トラックを貫く）と、赤い編集位置ライン（ルーラの三角の下から最下部まで）。
    /// 音部記号の領域に入ったら隠す。
    private func positionLines(layout: ScoreLayout) -> some View {
        Canvas { context, size in
            let visible = { (x: CGFloat) in x >= layout.stickyWidth - 1 && x <= size.width }

            let rulerTop = Metrics.playRangeBarHeight
            var dashes = Path()
            for tick in [store.sketch.playRange.lowerBound, store.sketch.playRange.upperBound] {
                let x = layout.boundaryX(tick: tick) - store.horizontalOffset
                guard visible(x) else { continue }
                dashes.move(to: CGPoint(x: x + 0.5, y: rulerTop))
                dashes.addLine(to: CGPoint(x: x + 0.5, y: size.height))
            }
            context.stroke(dashes, with: .color(Palette.accent.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            let x = layout.x(tick: store.playheadTick ?? store.editor.editPosition) - store.horizontalOffset
            guard visible(x) else { return }
            let top = rulerTop + 14
            context.fill(Path(CGRect(x: x - 1, y: top, width: 2, height: size.height - top)), with: .color(Palette.playhead))
        }
        .padding(.leading, Metrics.trackHeaderWidth)
        .allowsHitTesting(false)
    }

    /// 編集位置の小節が、見える小節数の6割ほどの位置に来るように横スクロールする
    /// （基準画面：100%で 5〜8 の中に7小節目）。譜面の幅が決まってから一度だけ行う。
    private func scrollToEditPosition() {
        let layout = store.layout
        let visibleCount = Int((store.visibleStaffWidth - layout.stickyWidth) / layout.barWidth)
        let leadingBar = max(store.editPositionBar - Int((Double(max(visibleCount, 1)) * 0.6).rounded()), 1)
        guard leadingBar > 1 else { return }
        store.scroll(toLeadingBar: leadingBar)
    }

    private var headerDensity: TrackHeaderDensity {
        headerDensity(zoom: store.editor.zoom)
    }

    private func headerDensity(zoom: Double) -> TrackHeaderDensity {
        let layout = store.layout(zoom: zoom)
        if layout.isMinimal { return .minimal }
        if layout.isCompact { return .compact }
        return layout.showsDetail ? .detailed : .regular
    }

    /// 行の高さ。五線に必要な高さとトラック情報が収まる高さの大きい方。
    /// トラックが少ないときは譜面ビューを埋めるよう伸ばすが、縮小時に行間が空きすぎないよう五線の高さの1.1倍までにする。
    private func rowHeight(available: CGFloat, zoom: Double) -> CGFloat {
        let count = max(store.sketch.tracks.count, 1)
        let staffHeight = store.layout(zoom: zoom).minimumRowHeight
        let filled = min((available / CGFloat(count)).rounded(.down), staffHeight * 1.1)
        return max(staffHeight, filled, headerDensity(zoom: zoom).minimumRowHeight)
    }

    private func trackHeaders(rowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(store.sketch.tracks.enumerated()), id: \.element.id) { index, track in
                TrackHeaderView(
                    track: track,
                    isSelected: store.editor.selectedTrackID == track.id,
                    density: headerDensity,
                    isAudible: isAudible(track),
                    volume: Binding(get: { track.volume }, set: { store.setVolume($0, of: track.id) }),
                    pan: Binding(get: { track.pan }, set: { store.setPan($0, of: track.id) }),
                    onToggleMute: { store.toggleMute(of: track.id) },
                    onToggleSolo: { store.toggleSolo(of: track.id) },
                    onShowSettings: { settingsTrackID = track.id }
                ) {
                    trackMenuItems(track)
                }
                .frame(height: rowHeight)
                .overlay(alignment: .bottom) { Palette.ruleSoft.frame(height: 1) }
                .onTapGesture { store.selectTrack(track.id) }
                .popover(isPresented: Binding(get: { settingsTrackID == track.id }, set: { if !$0 { settingsTrackID = nil } }),
                         arrowEdge: .trailing) {
                    TrackSettingsView(store: store, trackID: track.id)
                        .presentationCompactAdaptation(.popover)
                }
                #if os(macOS)
                .contextMenu { trackMenuItems(track) }
                // Mac：トラック情報をドラッグして並べ替える（スライダやボタンの上は、そちらの操作が先）
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { drag in updateTrackDrag(track: track, index: index, startY: drag.startLocation.y, y: drag.location.y) }
                        .onEnded { _ in endTrackDrag(rowHeight: rowHeight) }
                )
                #else
                // iPad：長押ししてからドラッグして並べ替える（普通のドラッグは縦スクロール）
                .gesture(LongPressDragGesture(
                    usesGlobalCoordinates: true,
                    onBegan: { location in updateTrackDrag(track: track, index: index, startY: location.y, y: location.y) },
                    onChanged: { location in updateTrackDrag(track: track, index: index, startY: nil, y: location.y) },
                    onEnded: { endTrackDrag(rowHeight: rowHeight) }
                ))
                #endif
                .modifier(TrackDragEffect(offset: trackDragOffset(for: track.id)))
            }
            addTrackRow
        }
        .overlay(alignment: .topLeading) { trackDropIndicator(rowHeight: rowHeight) }
        .alert("「\(pendingRemoval?.name ?? "")」を消しますか？", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { track in
            Button("消す", role: .destructive) { store.removeTrack(track.id) }
            Button("キャンセル", role: .cancel) {}
        } message: { track in
            Text("音符が\(track.notes.filter { !$0.isRest }.count)個あります。元に戻すで戻せます。")
        }
    }

    /// トラック情報のメニュー（「…」と、Mac の右クリック）。
    @ViewBuilder
    private func trackMenuItems(_ track: Track) -> some View {
        Button("トラックの設定…") { settingsTrackID = track.id }
        Menu("下にトラックを追加") {
            ForEach(TrackRole.selectable, id: \.self) { role in
                Button(Self.addTitle(for: role)) { store.addTrack(role: role, below: track.id) }
            }
        }
        .disabled(!store.canAddTrack)
        Button("複製") { store.duplicateTrack(track.id) }
            .disabled(!store.canAddTrack || track.isDrums)  // ドラムは曲に1本だけ
        Divider()
        Button("トラックを消す…", role: .destructive) { requestRemoval(of: track) }
            .disabled(store.sketch.tracks.count <= 1)
    }

    /// 「メロディ（Piano）」のように、役割とその音色。
    private static func addTitle(for role: TrackRole) -> String {
        "\(role.displayName)（\(GMInstruments.name(of: TrackEditing.template(for: role).program))）"
    }

    /// 音符があるときだけ確かめてから消す。
    private func requestRemoval(of track: Track) {
        if track.notes.contains(where: { !$0.isRest }) {
            pendingRemoval = track
        } else {
            store.removeTrack(track.id)
        }
    }

    /// トラック列の一番下の「＋ トラック」（役割を選んで、選択中のトラックの下に足す）。
    private var addTrackRow: some View {
        Menu {
            ForEach(TrackRole.selectable, id: \.self) { role in
                Button(Self.addTitle(for: role)) { store.addTrack(role: role) }
            }
        } label: {
            Label("トラック", systemImage: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(store.canAddTrack ? Palette.inkSecondary : Palette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .frame(height: Self.addTrackRowHeight)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(!store.canAddTrack)
        .frame(width: Metrics.trackHeaderWidth)
        .background(Palette.paper)
        .overlay(alignment: .trailing) { Palette.rule.frame(width: 1) }
        .accessibilityLabel(store.canAddTrack ? "トラックを追加" : "トラックは\(TrackEditing.maximumCount)本まで")
    }

    // MARK: トラックの並べ替え

    private func updateTrackDrag(track: Track, index: Int, startY: CGFloat?, y: CGFloat) {
        if trackDrag?.id != track.id {
            guard let startY else { return }
            store.selectTrack(track.id)
            trackDrag = TrackDrag(id: track.id, index: index, startY: startY)
        }
        trackDrag?.offset = y - (trackDrag?.startY ?? y)
    }

    private func endTrackDrag(rowHeight: CGFloat) {
        guard let drag = trackDrag else { return }
        let destination = trackDropIndex(drag, rowHeight: rowHeight)
        withAnimation(.easeOut(duration: 0.15)) {
            trackDrag = nil
            store.moveTrack(drag.id, to: destination)
        }
    }

    /// ドラッグ中のトラックの中心がある位置から、挿入位置（動かす前の並びで 0…トラック数）を求める。
    private func trackDropIndex(_ drag: TrackDrag, rowHeight: CGFloat) -> Int {
        let center = (CGFloat(drag.index) + 0.5) * rowHeight + drag.offset
        return min(max(Int((center / rowHeight).rounded()), 0), store.sketch.tracks.count)
    }

    private func trackDragOffset(for id: Track.ID) -> CGFloat? {
        trackDrag.flatMap { $0.id == id ? $0.offset : nil }
    }

    /// 挿入位置の青い線（動かない位置なら出さない）。
    @ViewBuilder
    private func trackDropIndicator(rowHeight: CGFloat) -> some View {
        if let drag = trackDrag {
            let destination = trackDropIndex(drag, rowHeight: rowHeight)
            if destination != drag.index, destination != drag.index + 1 {
                Palette.accent
                    .frame(width: Metrics.trackHeaderWidth, height: 3)
                    .offset(y: CGFloat(destination) * rowHeight - 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 音符の当たり判定。左端の音部記号の下に隠れている音符は選ばない。再生中は選ばない。
    private func hitNote(at location: CGPoint, track: Track, layout: ScoreLayout, rowHeight: CGFloat) -> Note.ID? {
        guard !store.isPlaying, location.x > store.horizontalOffset + layout.stickyWidth else { return nil }
        return StaffRowView.hitNote(at: location, track: track, sketch: store.sketch, layout: layout, rowHeight: rowHeight)
    }

    /// 範囲選択の箱を広げる。箱は行の中に収め、左端の音部記号の下は含めない。
    private func updateBox(from start: CGPoint, to end: CGPoint, track: Track, layout: ScoreLayout, rowHeight: CGFloat) {
        let visibleLeft = store.horizontalOffset + layout.stickyWidth
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            .intersection(CGRect(x: visibleLeft, y: 0, width: max(layout.contentWidth - visibleLeft, 0), height: rowHeight))
        guard !rect.isNull else {
            store.updateBoxSelection(rect: .zero, hits: [])
            return
        }
        let hits = StaffRowView.notes(in: rect, track: track, sketch: store.sketch, layout: layout, rowHeight: rowHeight)
        store.updateBoxSelection(rect: rect, hits: hits)
    }

    /// ミュート・ソロで、トラックが鳴っているか（再生の決まりと同じ：ソロがあればソロのトラックだけ）。
    private func isAudible(_ track: Track) -> Bool {
        let anySolo = store.sketch.tracks.contains(where: \.isSoloed)
        return !track.isMuted && (!anySolo || track.isSoloed)
    }

    /// Mac で ⇧を押しているか（⇧クリック・⇧＋箱で選択に足す）。
    private static var isShiftDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift)
        #else
        false
        #endif
    }

    private func staffRows(layout: ScoreLayout, rowHeight: CGFloat) -> some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                ForEach(store.sketch.tracks) { track in
                    let isSelectedTrack = store.editor.selectedTrackID == track.id
                    StaffRowView(
                        track: track, sketch: store.sketch, editor: store.editor, layout: layout, rowHeight: rowHeight,
                        isAudible: isAudible(track),
                        selectedNoteIDs: isSelectedTrack ? store.selectedNoteIDs : [],
                        dragPreview: isSelectedTrack ? store.noteDrag?.preview ?? [] : [],
                        selectionBox: store.selectionBox.flatMap { $0.trackID == track.id ? $0.rect : nil },
                        onDragSelection: { store.dragSelection(translation: $0) },
                        onEndDragSelection: { store.endDragSelection() }
                    )
                    .equatable()
                    .overlay(alignment: .topLeading) {
                        PlayingNotesLayer(store: store, track: track, key: store.sketch.key, layout: layout, rowHeight: rowHeight,
                                          isAudible: isAudible(track))
                    }
                    .overlay(alignment: .bottom) { Palette.ruleSoft.frame(height: 1) }
                    .modifier(TrackDragEffect(offset: trackDragOffset(for: track.id)))
                    .onTapGesture { location in
                        // 音符（休符）の上なら選ぶ（Mac の ⇧クリックは足す／外す）。
                        // それ以外は、タップしたトラックを選び、編集位置もそこへ動かす
                        if let note = hitNote(at: location, track: track, layout: layout, rowHeight: rowHeight) {
                            store.selectNote(note, track: track.id, toggles: Self.isShiftDown)
                            return
                        }
                        store.clearNoteSelection()
                        store.selectTrack(track.id)
                        store.setEditPosition(layout.tick(atContentX: location.x, grid: RulerView.seekGrid))
                    }
                    #if os(macOS)
                    // Mac はマウスのドラッグで譜面がスクロールしないので、
                    // 音符の上から始めたら（選んでいなくても）つかんで動かし、何も無い所から始めたら範囲選択の箱を出す
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { drag in
                                if mouseDragNote == nil {
                                    let note = hitNote(at: drag.startLocation, track: track, layout: layout, rowHeight: rowHeight)
                                    mouseDragNote = .some(note)
                                    if let note {
                                        if !isSelectedTrack || !store.selectedNoteIDs.contains(note) {
                                            store.selectNote(note, track: track.id, toggles: Self.isShiftDown)
                                        }
                                    } else {
                                        store.beginBoxSelection(track: track.id, adding: Self.isShiftDown)
                                    }
                                }
                                if case .some(.some) = mouseDragNote {
                                    store.dragSelection(translation: drag.translation)
                                } else {
                                    updateBox(from: drag.startLocation, to: drag.location, track: track, layout: layout, rowHeight: rowHeight)
                                }
                            }
                            .onEnded { _ in
                                if case .some(.some) = mouseDragNote { store.endDragSelection() } else { store.endBoxSelection() }
                                mouseDragNote = nil
                            }
                    )
                    #else
                    // iPad：長押ししてからドラッグすると範囲選択の箱（普通のドラッグは譜面のスクロール）
                    .gesture(LongPressDragGesture(
                        onBegan: { location in
                            boxStart = location
                            store.beginBoxSelection(track: track.id, adding: false)
                            updateBox(from: location, to: location, track: track, layout: layout, rowHeight: rowHeight)
                        },
                        onChanged: { location in
                            guard let start = boxStart else { return }
                            updateBox(from: start, to: location, track: track, layout: layout, rowHeight: rowHeight)
                        },
                        onEnded: {
                            boxStart = nil
                            store.endBoxSelection()
                        }
                    ))
                    #endif
                }
                // 「＋ トラック」の行の分
                Color.clear.frame(width: layout.contentWidth, height: Self.addTrackRowHeight)
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($store.horizontalPosition)
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            geometry.visibleRect
        } action: { _, visible in
            store.horizontalOffset = visible.minX
            store.visibleStaffWidth = visible.width
            if !didInitialScroll, visible.width > 0 {
                didInitialScroll = true
                scrollToEditPosition()
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(Array(store.sketch.tracks.enumerated()), id: \.element.id) { index, track in
                    Group {
                        if index == 0 {
                            LeadingStickyClef(store: store, track: track, layout: layout, rowHeight: rowHeight)
                        } else {
                            StickyClefView(track: track, layout: layout, rowHeight: rowHeight, leadingBarNumber: nil)
                        }
                    }
                    .overlay(alignment: .bottom) { Palette.ruleSoft.frame(height: 1) }
                    .modifier(TrackDragEffect(offset: trackDragOffset(for: track.id)))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// 先頭トラックの音部記号の欄（左上に、表示領域の左端にある小節の番号を出す）。
/// 横スクロール量はここだけで読む（譜面の行で読むと、スクロールのたびに全トラックの五線が作り直されて重くなる）。
private struct LeadingStickyClef: View {
    let store: SketchStore
    let track: Track
    let layout: ScoreLayout
    let rowHeight: CGFloat

    var body: some View {
        StickyClefView(track: track, layout: layout, rowHeight: rowHeight,
                       leadingBarNumber: layout.bar(atContentX: store.horizontalOffset + layout.stickyWidth + 1))
    }
}

/// 並べ替えでドラッグ中のトラック（情報・五線・音部記号）を指に合わせて動かし、浮いて見せる。
private struct TrackDragEffect: ViewModifier {
    let offset: CGFloat?

    func body(content: Content) -> some View {
        content
            .offset(y: offset ?? 0)
            .shadow(color: .black.opacity(offset == nil ? 0 : 0.18), radius: 8, y: 2)
            .zIndex(offset == nil ? 0 : 1)
            .opacity(offset == nil ? 1 : 0.92)
    }
}
