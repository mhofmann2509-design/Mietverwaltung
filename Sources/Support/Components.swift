import SwiftUI

/// Kompaktes Status-Label mit Punkt/Icon und Farbe aus `Theme.StatusTone` – ersetzt lose
/// `Text(...).foregroundStyle(...)`-Zeilen durch einen einheitlichen Baustein.
struct StatusBadge: View {
    let label: String
    let tone: Theme.StatusTone

    var body: some View {
        Label(label, systemImage: tone.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tone.color)
    }
}

/// Schmaler Ist/Soll-Balken (z.B. Auslastung der 15-%-Grenze) – funktioniert unver ändert sowohl
/// auf dem Bildschirm als auch im PDF-Export, da `PDFExporter` beliebige SwiftUI-Views rendert.
struct UtilizationBar: View {
    /// 0...1 (Werte > 1 werden sichtbar als Überschreitung markiert, nicht abgeschnitten).
    let fraction: Double
    var tone: Theme.StatusTone = .good
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Theme.cardBorder)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(tone.color)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
                if fraction > 1 {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Theme.statusCritical)
                        .frame(width: 3)
                        .offset(x: proxy.size.width - 3)
                }
            }
        }
        .frame(height: height)
    }
}

/// Große, hervorgehobene Ergebniskachel (z.B. „Einkünfte aus Vermietung und Verpachtung") – für die
/// eine Kernzahl, die ein Bericht oder Cockpit zuerst zeigen soll, deutlich abgesetzt von den
/// unterst ützenden Kennzahlen daneben.
struct HeroResultTile: View {
    let title: String
    let value: String
    var tone: Theme.StatusTone = .neutral
    var subtitle: String? = nil

    var body: some View {
        Theme.card {
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(title)
                    .font(Theme.metricLabelFont)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(Theme.heroValueFont)
                    .foregroundStyle(tone == .neutral ? .primary : tone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Eine anklickbare „offener Punkt"-Zeile, die direkt zur betroffenen Stelle führt – ersetzt reine
/// Hinweistexte ohne Sprungziel.
struct OpenItemRow: View {
    let title: String
    let detail: String
    var tone: Theme.StatusTone = .warning

    var body: some View {
        HStack {
            Image(systemName: tone.systemImage)
                .foregroundStyle(tone.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Kompakte Kennzahlenkachel (Titel + Wert + Icon) – geteilter Baustein für Portfolio- und
/// Objekt-Cockpits, damit Steuer-, Dashboard- und andere Übersichten dieselbe Kartenoptik teilen.
struct KPITile: View {
    let title: String
    let value: String
    var systemImage: String = "circle"
    var valueColor: Color = .primary

    var body: some View {
        Theme.card {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                Text(value)
                    .font(Theme.metricValueFont)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(Theme.metricLabelFont)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Horizontale Chip-Leiste zur Auswahl eines Detailbereichs (z.B. AfA / 15-%-Grenze / Werbungs-
/// kosten) – ersetzt eine lange, gleichrangige Section-Liste durch fokussierbare Unterbereiche.
struct TabChipPicker<Tab: Hashable & CaseIterable & Identifiable>: View where Tab.AllCases: RandomAccessCollection {
    @Binding var selection: Tab
    let label: (Tab) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacingS) {
                ForEach(Array(Tab.allCases)) { tab in
                    Button {
                        selection = tab
                    } label: {
                        Text(label(tab))
                            .font(.subheadline.weight(selection == tab ? .semibold : .regular))
                            .padding(.horizontal, Theme.spacingM)
                            .padding(.vertical, Theme.spacingS)
                            .background(
                                Capsule().fill(selection == tab ? Color.accentColor.opacity(0.15) : Theme.cardBackground)
                            )
                            .foregroundStyle(selection == tab ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
