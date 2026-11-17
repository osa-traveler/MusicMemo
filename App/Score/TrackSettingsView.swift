import MusicMemoCore
import SwiftUI

/// トラックの設定（トラック情報のメニュー「トラックの設定…」や「音色…」から開くポップオーバー）。
/// 名前・音色・役割・音部記号・色。変えたらすぐ反映する（元に戻すで戻せる）。
struct TrackSettingsView: View {
    let store: SketchStore
    let trackID: Track.ID

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var track: Track? { store.sketch.tracks.first { $0.id == trackID } }

    var body: some View {
        if let track {
            content(track)
        }
    }

    private func content(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("トラックの設定")
                .font(.system(size: 15, weight: .bold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    label("名前")
                    TextField(GMInstruments.name(of: track.program), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($isNameFocused)
                        .onSubmit(commitName)
                }
                GridRow {
                    label("音色")
                    instrumentMenu(track)
                }
                GridRow {
                    label("役割")
                    Picker("役割", selection: Binding(get: { track.role }, set: { store.setTrackRole($0, of: trackID) })) {
                        ForEach(TrackRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                GridRow {
                    label("音部記号")
                    Picker("音部記号", selection: Binding(get: { track.clef }, set: { store.setTrackClef($0, of: trackID) })) {
                        Text("ト音記号").tag(Clef.treble)
                        Text("ヘ音記号").tag(Clef.bass)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                GridRow {
                    label("色")
                    HStack(spacing: 8) {
                        ForEach(TrackColor.allCases, id: \.self) { color in
                            colorButton(color, isSelected: track.color == color)
                        }
                    }
                }
            }

            if track.role == .chords {
                Text("役割が「コード」のトラックは、五線の上にコードネームを出します。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .onAppear { name = track.name }
        .onChange(of: track.name) { if !isNameFocused { name = track.name } }
        .onChange(of: isNameFocused) {
            store.isEditingText = isNameFocused
            if !isNameFocused { commitName() }
        }
        .onDisappear {
            commitName()
            store.isEditingText = false
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
            .gridColumnAlignment(.trailing)
    }

    private func commitName() {
        guard let track, name != track.name else { return }
        store.setTrackName(name, of: trackID)
        name = store.sketch.tracks.first { $0.id == trackID }?.name ?? name
    }

    /// 音色：GM の16の系統 → 8つの音色。選ぶと試しに1音鳴る。
    private func instrumentMenu(_ track: Track) -> some View {
        Menu {
            ForEach(GMInstruments.families) { family in
                Menu(family.name) {
                    ForEach(family.programs, id: \.self) { program in
                        Button {
                            store.setTrackProgram(program, of: trackID)
                        } label: {
                            if program == track.program {
                                Label(GMInstruments.name(of: program), systemImage: "checkmark")
                            } else {
                                Text(GMInstruments.name(of: program))
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(GMInstruments.name(of: track.program))
                    .font(.system(size: 13, weight: .medium))
                Text(GMInstruments.family(of: track.program)?.name ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkTertiary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Palette.paperMuted, in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.ruleStrong, lineWidth: 1))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func colorButton(_ color: TrackColor, isSelected: Bool) -> some View {
        Button {
            store.setTrackColor(color, of: trackID)
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 22, height: 22)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Palette.paper, lineWidth: 2)
                        Circle().strokeBorder(color.color, lineWidth: 1).padding(-3)
                    }
                }
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension TrackColor {
    var displayName: String {
        switch self {
        case .blue: "青"
        case .orange: "オレンジ"
        case .green: "緑"
        case .purple: "紫"
        case .ochre: "黄土"
        case .gray: "グレー"
        }
    }
}
