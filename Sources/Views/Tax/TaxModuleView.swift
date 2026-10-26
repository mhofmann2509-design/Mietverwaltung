import SwiftUI
import SwiftData

/// Portfolio-Cockpit für das Steuermodul: Steuerjahr-weite Summen über alle Immobilien,
/// eine Objekttabelle mit Ergebnis/Status je Objekt und objektübergreifende Hinweise (z.B. die
/// Immobilien-übergreifend gedeckelte Homeoffice-Pauschale) – bevor man in ein einzelnes Objekt
/// wechselt (`TaxModulePropertyView`).
struct TaxModuleView: View {
    @Query(sort: \Property.name) private var properties: [Property]
    @State private var selectedYear: Int = Calendar.current.component(.year, from: .now)

    private var availableYears: [Int] {
        let years = Set(properties.flatMap { $0.availableTaxYears })
        return (years.isEmpty ? [Calendar.current.component(.year, from: .now)] : years).sorted(by: >)
    }

    private var totalIncome: Double { properties.reduce(0) { $0 + $1.annualColdRent(forYear: selectedYear) } }
    private var totalWerbungskosten: Double { properties.reduce(0) { $0 + $1.werbungskosten(forYear: selectedYear) } }
    private var totalAfa: Double { properties.reduce(0) { $0 + $1.totalAfa(forYear: selectedYear) } }
    private var totalResult: Double { totalIncome - totalWerbungskosten - totalAfa }

    /// Immobilien, bei denen die 210-Tage-Grenze der Homeoffice-Pauschale (objektübergreifend)
    /// im gewählten Jahr überschritten ist – wird nur einmal portfolioweit gezeigt, nicht pro Objekt.
    private var homeOfficeCapExceeded: Bool {
        guard let first = properties.first else { return false }
        return HomeOfficeAllocation.isCapExceeded(for: first, taxYear: selectedYear)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header

                if properties.isEmpty {
                    ContentUnavailableView(
                        "Keine Immobilien",
                        systemImage: "building.2",
                        description: Text("Lege zuerst eine Immobilie an, um das Steuermodul zu nutzen.")
                    )
                    .padding(.top, 40)
                } else {
                    kpiGrid
                    objectsSection
                    if homeOfficeCapExceeded {
                        objectWideNoticesSection
                    }
                }
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Steuern")
    }

    private var header: some View {
        HStack {
            Text("Steuerjahr")
                .foregroundStyle(.secondary)
            Picker("Steuerjahr", selection: $selectedYear) {
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer()
        }
    }

    private var kpiGrid: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Portfolio \(String(selectedYear))")
                .font(Theme.sectionTitleFont)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                KPITile(title: "Mieteinnahmen", value: totalIncome.asCurrency, systemImage: "eurosign.circle")
                KPITile(title: "Werbungskosten", value: totalWerbungskosten.asCurrency, systemImage: "minus.circle")
                KPITile(title: "AfA gesamt", value: totalAfa.asCurrency, systemImage: "chart.line.downtrend.xyaxis")
                KPITile(
                    title: totalResult >= 0 ? "Steuerl. Überschuss" : "Steuerl. Verlust",
                    value: abs(totalResult).asCurrency,
                    systemImage: totalResult >= 0 ? "checkmark.circle" : "exclamationmark.circle",
                    valueColor: totalResult >= 0 ? Theme.statusGood : Theme.statusWarning
                )
            }
        }
    }

    private var objectsSection: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Immobilien")
                .font(Theme.sectionTitleFont)
            Theme.card {
                VStack(spacing: 0) {
                    ForEach(properties) { property in
                        NavigationLink {
                            TaxModulePropertyView(property: property, initialYear: selectedYear)
                        } label: {
                            objectRow(property)
                        }
                        .buttonStyle(.plain)
                        if property.id != properties.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func objectRow(_ property: Property) -> some View {
        let result = property.estimatedTaxableResult(forYear: selectedYear)
        let openChecklist = (property.taxChecklistItems ?? []).filter {
            ($0.mode == .initialSetup || $0.taxYear == selectedYear) && $0.status != .done && $0.status != .notApplicable
        }.count

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(property.name.isEmpty ? property.address : property.name)
                    .foregroundStyle(.primary)
                HStack(spacing: Theme.spacingS) {
                    if let thresholdCase = property.thresholdCase {
                        StatusBadge(label: thresholdCase.status.label, tone: thresholdStatusTone(thresholdCase.status))
                    }
                    if openChecklist > 0 {
                        Text("\(openChecklist) offen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.asCurrency)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result >= 0 ? Theme.statusGood : Theme.statusWarning)
                Text("Ergebnis \(String(selectedYear))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var objectWideNoticesSection: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Objektübergreifend offen")
                .font(Theme.sectionTitleFont)
            Theme.card {
                OpenItemRow(
                    title: "Homeoffice-Pauschale über mehrere Immobilien",
                    detail: "210-Tage-/1.260-€-Grenze im Steuerjahr \(String(selectedYear)) insgesamt überschritten – bereits anteilig gedeckelt.",
                    tone: .warning
                )
            }
        }
    }

    private func thresholdStatusTone(_ status: ThresholdCaseStatus) -> Theme.StatusTone {
        switch status {
        case .belowThreshold, .completed: return .good
        case .thresholdReached: return .warning
        case .exceeded: return .critical
        case .notConclusivelyCheckable: return .neutral
        }
    }
}

#Preview {
    NavigationStack {
        TaxModuleView()
    }
    .modelContainer(PreviewData.container)
}
