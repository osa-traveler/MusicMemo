import MusicMemoCore
import SwiftUI

/// セクション行。セクションのチップ（押すとその頭へ移る。右クリック／長押しでメニュー）と「＋ セクション」、
/// 右端に表示範囲と入力位置。
struct SectionBarView: View {
    let store: SketchStore

    /// 名前と長さを開いているセクション。
    @State private var editingSectionID: SongSection.ID?
    /// 確かめてから行う操作（音符が消えるとき）。
    @State private var pendingRemoval: PendingRemoval?

    struct PendingRemoval {
        var title: String
        var message: String
        var action: () -> Void
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(store.sketch.sections.sorted { $0.startBar < $1.startBar }) { section in
                chip(section)
            }
            addMenu
            Spacer(minLength: 0)

            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSecondary)
                .monospacedDigit()
        }
        .frame(height: Metrics.sectionRowHeight)
        .alert(pendingRemoval?.title ?? "", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { pending in
            Button("消す", role: .destructive, action: pending.action)
            Button("キャンセル", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
        #if DEBUG
        .onAppear {
            // 開発用：MUSICMEMO_SECTION_DEMO=1 なら、編集位置のセクションの名前と長さを開く（撮影用）
            if DebugSectionDemo.mode == "1" { editingSectionID = store.currentSection?.id }
        }
        #endif
    }

    private func chip(_ section: SongSection) -> some View {
        let isCurrent = store.currentSection?.id == section.id
        return Button {
            store.jump(toBar: section.startBar)
        } label: {
            Text(section.name)
                .font(.system(size: 12, weight: isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? Palette.paper : Palette.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isCurrent ? Palette.ink : .clear, in: .capsule)
                .overlay {
                    if !isCurrent { Capsule().strokeBorder(Palette.ruleStrong, lineWidth: 1) }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems(section) }
        .popover(isPresented: Binding(get: { editingSectionID == section.id }, set: { if !$0 { editingSectionID = nil } }),
                 arrowEdge: .bottom) {
            SectionSettingsView(store: store, sectionID: section.id, onResize: requestResize)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityHint("右クリック（長押し）でセクションのメニュー")
    }

    @ViewBuilder
    private func menuItems(_ section: SongSection) -> some View {
        Button("名前と長さ…") { editingSectionID = section.id }
        Button("複製（すぐ後ろへ）") { store.duplicateSection(section.id) }
            .disabled(!SectionEditing.canDuplicate(section.id, in: store.sketch))
        Button("前のセクションとつなげる") { store.mergeSectionWithPrevious(section.id) }
            .disabled(SectionEditing.previous(of: section.id, in: store.sketch) == nil)
        Divider()
        Button("セクションを消す（小節ごと）…", role: .destructive) { requestDelete(section) }
            .disabled(!SectionEditing.canDelete(section.id, in: store.sketch))
    }

    /// 「＋ セクション」：曲の最後に足す、編集位置で分ける。
    private var addMenu: some View {
        Menu {
            Button("曲の最後に追加（\(SectionEditing.defaultBarCount)小節）") { store.appendSection() }
                .disabled(store.sketch.barCount + SectionEditing.defaultBarCount > SongSettings.barCountRange.upperBound)
            Button("\(store.editPositionBar)小節目から分ける") { store.splitSectionAtEditPosition() }
                .disabled(!store.canSplitSectionAtEditPosition)
        } label: {
            Text("＋ セクション")
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(Palette.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .contentShape(.capsule)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func requestDelete(_ section: SongSection) {
        let removed = SectionEditing.notesRemoved(byDeleting: section.id, in: store.sketch)
        guard removed > 0 else {
            store.deleteSection(section.id)
            return
        }
        pendingRemoval = PendingRemoval(
            title: "「\(section.name)」を消しますか？",
            message: "\(section.startBar)〜\(section.bars.upperBound)小節（音符\(removed)個）を消して、後ろを詰めます。元に戻すで戻せます。",
            action: { store.deleteSection(section.id) }
        )
    }

    /// 長さを変える。縮めて音符が消えるときは確かめる。
    private func requestResize(_ section: SongSection, _ barCount: Int) {
        let removed = SectionEditing.notesRemoved(byResizing: section.id, to: barCount, in: store.sketch)
        guard removed > 0 else {
            store.resizeSection(section.id, to: barCount)
            return
        }
        let first = section.startBar + barCount
        pendingRemoval = PendingRemoval(
            title: "「\(section.name)」を\(barCount)小節にしますか？",
            message: "\(first)〜\(section.bars.upperBound)小節（音符\(removed)個）を消して、後ろを詰めます。元に戻すで戻せます。",
            action: { store.resizeSection(section.id, to: barCount) }
        )
    }

    /// 「表示 5〜8小節 · 入力位置 7小節 1拍目」
    private var status: String {
        let bars = store.visibleBars
        let position = store.sketch.timeSignature.position(of: store.editor.editPosition)
        let visible = bars.count == 1 ? "\(bars.lowerBound)小節" : "\(bars.lowerBound)〜\(bars.upperBound)小節"
        // トラック数は、全部が見えていないときかズーム中だけ出す（基準画面の100%には無い）
        let total = store.sketch.tracks.count
        let tracks = store.visibleTrackCount < total || store.editor.zoom != 1 ? " · \(store.visibleTrackCount)/\(total)トラック" : ""
        return "表示 \(visible)\(tracks) · 入力位置 \(position.bar)小節 \(position.beat)拍目"
    }
}

/// セクションの名前と長さ（チップのメニュー「名前と長さ…」から開くポップオーバー）。
struct SectionSettingsView: View {
    let store: SketchStore
    let sectionID: SongSection.ID
    /// 長さを変える（音符が消えるときの確認は呼ぶ側で）。
    let onResize: (SongSection, Int) -> Void

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var section: SongSection? { store.sketch.sections.first { $0.id == sectionID } }

    var body: some View {
        if let section {
            VStack(alignment: .leading, spacing: 14) {
                Text("セクション")
                    .font(.system(size: 15, weight: .bold))

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        label("名前")
                        TextField(section.name, text: $name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 290)
                            .focused($isNameFocused)
                            .onSubmit(commitName)
                    }
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        suggestions(current: section.name)
                    }
                    GridRow {
                        label("長さ")
                        HStack(spacing: 8) {
                            NumberStepper(prefix: nil, value: section.barCount, range: 1...SongSettings.barCountRange.upperBound,
                                          isEditing: editingBinding) { onResize(section, $0) }
                            Text("小節（\(section.startBar)〜\(section.bars.upperBound)）")
                                .font(.system(size: 12))
                                .fixedSize()
                                .foregroundStyle(Palette.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                }

                Text("長さを変えると、セクションの終わりで小節を足す・消して、後ろをずらします。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(width: 400, alignment: .leading)
            .foregroundStyle(Palette.ink)
            .tint(Palette.accent)
            .onAppear { name = section.name }
            .onChange(of: section.name) { if !isNameFocused { name = section.name } }
            .onChange(of: isNameFocused) {
                store.isEditingText = isNameFocused
                if !isNameFocused { commitName() }
            }
            .onDisappear {
                commitName()
                store.isEditingText = false
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
            .gridColumnAlignment(.trailing)
    }

    /// 名前の候補（押すとその名前にする）。4つずつ2行に並べる。
    private func suggestions(current: String) -> some View {
        let names = SectionEditing.suggestedNames
        let rows = stride(from: 0, to: names.count, by: 4).map { Array(names[$0..<min($0 + 4, names.count)]) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { suggestion in
                        suggestionButton(suggestion, isCurrent: suggestion == current)
                    }
                }
            }
        }
    }

    private func suggestionButton(_ suggestion: String, isCurrent: Bool) -> some View {
        Button {
            name = suggestion
            store.renameSection(sectionID, to: suggestion)
        } label: {
            Text(suggestion)
                .font(.system(size: 12))
                .foregroundStyle(isCurrent ? Palette.paper : Palette.inkSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCurrent ? Palette.ink : Palette.paper)
                        .stroke(isCurrent ? Palette.ink : Palette.ruleStrong, lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var editingBinding: Binding<Bool> {
        Binding(get: { store.isEditingText }, set: { store.isEditingText = $0 })
    }

    private func commitName() {
        guard let section, name != section.name else { return }
        store.renameSection(sectionID, to: name)
        name = store.sketch.sections.first { $0.id == sectionID }?.name ?? name
    }
}
