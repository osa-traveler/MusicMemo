import SwiftUI

/// 数値の入力欄と −／＋。入力欄は Return かフォーカスが外れたときに確定する。
struct NumberStepper: View {
    let prefix: String?
    let value: Int
    let range: ClosedRange<Int>
    @Binding var isEditing: Bool
    let onCommit: (Int) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let prefix {
                Text(prefix)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSecondary)
            }
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .focused($isFocused)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onSubmit(commit)
            stepButton("minus", label: "減らす", enabled: value > range.lowerBound) { commit(value - 1) }
            stepButton("plus", label: "増やす", enabled: value < range.upperBound) { commit(value + 1) }
        }
        .onAppear { text = String(value) }
        .onChange(of: value) { text = String(value) }
        .onChange(of: isFocused) {
            isEditing = isFocused
            if !isFocused { commit() }
        }
    }

    private func commit() {
        guard let number = Int(text.trimmingCharacters(in: .whitespaces)) else {
            text = String(value)
            return
        }
        commit(number)
    }

    private func commit(_ number: Int) {
        let clamped = min(max(number, range.lowerBound), range.upperBound)
        text = String(value)
        if clamped != value { onCommit(clamped) }
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 28)
                .background(Palette.paperMuted, in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.ruleStrong, lineWidth: 1))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}
