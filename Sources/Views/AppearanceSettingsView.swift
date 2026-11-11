import SwiftUI

/// Auswahl des App-weiten Erscheinungsbilds (siehe `AppearanceStyle`/`AppearanceStore`). Die
/// Auswahl gilt sofort und für alle Bereiche der App, da `ContentView` die ganze
/// `NavigationSplitView` bei einem Wechsel per `.id(...)` neu aufbaut.
struct AppearanceSettingsView: View {
    @ObservedObject private var store = AppearanceStore.shared

    var body: some View {
        List {
            Section {
                ForEach(AppearanceStyle.allCases) { style in
                    Button {
                        store.style = style
                    } label: {
                        HStack(spacing: Theme.spacingM) {
                            Circle()
                                .fill(style.previewAccent)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(style.label)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(style.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.style == style {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Erscheinungsbild")
            } footer: {
                Text("Gilt sofort für die gesamte App – Übersicht, Immobilien, Finanzen und Steuerbereich. Die PDF-Steuerreports (Erstanlage, laufender Betrieb, 15-%-Grenze, AfA-Bericht) nutzen unabhängig davon ein festes, einheitliches Dokumentdesign für das Finanzamt.")
            }
        }
        .themedScrollBackground()
        .navigationTitle("Darstellung")
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
