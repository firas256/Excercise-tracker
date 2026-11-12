import SwiftUI

/// Lets the user lock the exercise (skips auto-detection) or correct a guess.
struct ExercisePickerView: View {
    @Binding var selection: ExerciseType?
    var allowsAuto: Bool
    /// Exercises to show first (e.g. the classifier's top guesses).
    var suggestions: [ExerciseType] = []
    var onPick: () -> Void = {}

    var body: some View {
        List {
            if allowsAuto {
                Button {
                    selection = nil
                    onPick()
                } label: {
                    row(title: "Auto-detect", symbol: "sparkles", selected: selection == nil)
                }
            }
            if !suggestions.isEmpty {
                Section("Suggestions") {
                    ForEach(suggestions) { e in pickButton(e) }
                }
            }
            ForEach(ExerciseCategory.allCases, id: \.self) { category in
                Section(category.displayName) {
                    ForEach(ExerciseType.allCases.filter { $0.category == category }) { e in pickButton(e) }
                }
            }
        }
        .navigationTitle("Exercise")
    }

    private func pickButton(_ e: ExerciseType) -> some View {
        Button {
            selection = e
            onPick()
        } label: {
            row(title: e.displayName, symbol: e.symbolName, selected: selection == e,
                note: e.trackingQuality == .limited ? "Hands fixed – best effort" : nil)
        }
    }

    private func row(title: String, symbol: String, selected: Bool, note: String? = nil) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(title).lineLimit(2)
                if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(.green) }
        }
    }
}
