import SwiftUI
import SwiftData

/// Zeitraum-Granularität für die Kopfzeilen-Auswahl – bestimmt, welcher Ausschnitt für
/// „Kaltmiete", „Zahlungseingänge", „offene Forderungen" und „Ausgaben" betrachtet wird.
/// Vorauswahl ist der laufende Monat.
private enum DashboardPeriod: String, CaseIterable, Identifiable {
    case month, quarter, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: return "Monat"
        case .quarter: return "Quartal"
        case .year: return "Jahr"
        }
    }

    /// Anfang/Ende des aktuellen Zeitraums dieser Granularität, ausgehend von heute.
    var currentRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date.now
        switch self {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            return (start, end)
        case .quarter:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let month = comps.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            let start = calendar.date(from: DateComponents(year: comps.year, month: quarterStartMonth, day: 1)) ?? now
            let end = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: start) ?? now
            return (start, end)
        case .year:
            let year = calendar.component(.year, from: now)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? now
            return (start, end)
        }
    }

    /// Lesbare Bezeichnung des aktuellen Zeitraums, z.B. „Oktober 2026" / „Q4 2026" / „2026".
    var currentRangeLabel: String {
        let now = Date.now
        let calendar = Calendar.current
        switch self {
        case .month:
            return now.asMonthYear
        case .quarter:
            let month = calendar.component(.month, from: now)
            let quarter = (month - 1) / 3 + 1
            return "Q\(quarter) \(String(calendar.component(.year, from: now)))"
        case .year:
            return String(calendar.component(.year, from: now))
        }
    }
}

private enum PaymentStatusKind: String {
    case paid = "Bezahlt"
    case open = "Offen"
    case overdue = "Überfällig"

    var color: Color {
        switch self {
        case .paid: return Theme.statusGood
        case .open: return Theme.statusWarning
        case .overdue: return Theme.statusCritical
        }
    }

    var systemImage: String {
        switch self {
        case .paid: return "checkmark.circle.fill"
        case .open: return "circle"
        case .overdue: return "exclamationmark.circle.fill"
        }
    }
}

private struct TenancyRow: Identifiable {
    let tenancy: Tenancy
    var id: PersistentIdentifier { tenancy.persistentModelID }
    var tenantName: String { tenancy.tenant?.fullName ?? "Unbekannter Mieter" }
    var unitLabel: String { "\(tenancy.unit?.property?.name ?? "") · \(tenancy.unit?.name ?? "")" }
    var sollMiete: Double { tenancy.coldRent }
    var status: PaymentStatusKind {
        guard let payment = tenancy.payment(forMonthContaining: .now) else { return .open }
        if payment.isPaid { return .paid }
        if payment.isOverdue { return .overdue }
        return .open
    }
    var statusLabel: String { status.rawValue }
    var arrears: Double { max(0, tenancy.arrearsBalance(upTo: .now)) }
}

struct DashboardView: View {
    @Query(sort: \Property.name) private var properties: [Property]
    @Query private var units: [Unit]
    @Query private var tenancies: [Tenancy]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var landlords: [Landlord]

    /// `nil` = alle Objekte. Scoped in der Kopfzeile, filtert Kennzahlen, Mietverhältnis-Tabelle
    /// und Aufgaben-Liste gemeinsam.
    @State private var selectedProperty: Property?
    @State private var selectedPeriod: DashboardPeriod = .month
    @State private var showingMoreMetrics = false
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<TenancyRow>] = [KeyPathComparator(\.tenantName)]
    @State private var selectedTaxYear = Calendar.current.component(.year, from: .now)

    // MARK: - Scope

    private var scopedProperties: [Property] {
        selectedProperty.map { [$0] } ?? properties
    }

    private var scopedUnits: [Unit] {
        guard let selectedProperty else { return units }
        return units.filter { $0.property == selectedProperty }
    }

    private var scopedTenancies: [Tenancy] {
        guard let selectedProperty else { return tenancies }
        return tenancies.filter { $0.unit?.property == selectedProperty }
    }

    private var scopedActiveTenancies: [Tenancy] {
        scopedTenancies.filter { $0.isActive }
    }

    private var scopedExpenses: [Expense] {
        guard let selectedProperty else { return expenses }
        return expenses.filter { $0.property == selectedProperty || $0.unit?.property == selectedProperty }
    }

    // MARK: - Kennzahlenkarten

    /// Summe der Kaltmiete aller im Zeitraum jeweils laufenden Mietverhältnisse, monatsgenau
    /// anteilig für die tatsächlich überlappenden Monate – nutzt dieselbe Methode wie
    /// `Property.annualColdRent(forYear:)` (`Tenancy.coldRentContribution(from:to:)`), nur
    /// granular für Monat/Quartal/Jahr statt nur für ein volles Kalenderjahr. Zuvor hatte diese
    /// Funktion eine eigene Tag-1-Stichprobe je Monat, die ein unterjährig begonnenes
    /// Mietverhältnis für den Startmonat auf 0 € statt anteilig zählte – im Widerspruch zu den
    /// Renditekacheln, die bereits `annualColdRent(forYear:)` nutzen.
    private func coldRent(in range: (start: Date, end: Date)) -> Double {
        scopedTenancies.reduce(0.0) { $0 + $1.coldRentContribution(from: range.start, to: range.end) }
    }

    private var kaltmieteInPeriod: Double {
        coldRent(in: selectedPeriod.currentRange)
    }

    private var paymentsReceivedInPeriod: Double {
        let range = selectedPeriod.currentRange
        return scopedTenancies.flatMap { $0.payments ?? [] }
            .filter { payment in
                guard let paidDate = payment.paidDate else { return false }
                return paidDate >= range.start && paidDate <= range.end
            }
            .reduce(0) { $0 + ($1.paidAmount ?? $1.totalDue) }
    }

    /// Ob ein Mietverhältnis im gewählten Zeitraum mindestens eine offene (nicht bezahlte)
    /// Position hat – Monat für Monat geprüft, auch wenn für einen Monat gar kein `RentPayment`
    /// existiert (dann gilt er als offen, konsistent mit `PaymentsOverviewView`).
    private func hasOpenPosition(_ tenancy: Tenancy, in range: (start: Date, end: Date)) -> Bool {
        let calendar = Calendar.current
        var date = range.start
        while date <= range.end {
            if tenancy.isRunning(on: date), tenancy.payment(forMonthContaining: date)?.isPaid != true {
                return true
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: date) else { break }
            date = next
        }
        return false
    }

    /// Mieter mit offenen Forderungen im gewählten Zeitraum, summiert dann aber ihren **gesamten**
    /// aktuellen Rückstand (nicht nur den Anteil aus dem Zeitraum).
    private var openArrearsInPeriod: Double {
        let range = selectedPeriod.currentRange
        return scopedTenancies
            .filter { hasOpenPosition($0, in: range) }
            .reduce(0) { $0 + max(0, $1.arrearsBalance(upTo: .now)) }
    }

    // MARK: - Mietverhältnis-Tabelle

    private var tenancyRows: [TenancyRow] {
        let rows = scopedActiveTenancies.map { TenancyRow(tenancy: $0) }
        let filtered = searchText.isEmpty ? rows : rows.filter {
            $0.tenantName.localizedCaseInsensitiveContains(searchText) || $0.unitLabel.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: sortOrder)
    }

    // MARK: - Aufgaben

    private var reminders: [ReminderItem] {
        RemindersEngine.reminders(properties: scopedProperties, tenancies: scopedTenancies)
    }

    // MARK: - Weitere Kennzahlen (eingeklappt)

    private var vacantUnits: [Unit] {
        scopedUnits.filter { $0.activeTenancy == nil }
    }

    private var vacancyRatePercent: Double? {
        guard !scopedUnits.isEmpty else { return nil }
        return Double(vacantUnits.count) / Double(scopedUnits.count) * 100
    }

    private var estimatedMonthlyVacancyLoss: Double {
        vacantUnits.reduce(0.0) { sum, unit in
            let lastPastTenancy = (unit.tenancies ?? [])
                .filter { $0.endDate != nil }
                .sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }
                .first
            return sum + (lastPastTenancy?.coldRent ?? 0)
        }
    }

    private var totalInvestment: Double {
        scopedProperties.reduce(0) { $0 + $1.purchasePrice }
    }

    private var portfolioGrossYieldPercent: Double? {
        let relevant = scopedProperties.filter { $0.purchasePrice > 0 }
        guard !relevant.isEmpty else { return nil }
        let totalPrice = relevant.reduce(0) { $0 + $1.purchasePrice }
        guard totalPrice > 0 else { return nil }
        let totalAnnualRent = relevant.reduce(0) { $0 + $1.annualColdRentFromActiveTenancies }
        return (totalAnnualRent / totalPrice) * 100
    }

    private var expensesInPeriod: Double {
        let range = selectedPeriod.currentRange
        return scopedExpenses
            .filter { $0.date >= range.start && $0.date <= range.end }
            .reduce(0) { $0 + $1.amount }
    }

    /// Bruttomietrendite für das gewählte Steuerjahr (Jahreskaltmiete ÷ Kaufpreis), portfolioweit
    /// gewichtet aufsummiert – anders als `portfolioGrossYieldPercent` oben (immer „jetzt") hier
    /// konsistent mit dem Steuerjahr-Picker der Rendite-/Steuer-/Cashflow-Blöcke.
    private var portfolioGrossYieldForSelectedYear: Double? {
        let relevant = scopedProperties.filter { $0.purchasePrice > 0 }
        guard !relevant.isEmpty else { return nil }
        let totalPrice = relevant.reduce(0.0) { $0 + $1.purchasePrice }
        guard totalPrice > 0 else { return nil }
        let totalRent = relevant.reduce(0.0) { $0 + $1.annualColdRent(forYear: selectedTaxYear) }
        return (totalRent / totalPrice) * 100
    }

    /// Nettomietrendite für das gewählte Steuerjahr: (Jahreskaltmiete − Jahresausgaben) ÷
    /// Investitionssumme inkl. Kaufnebenkosten, portfolioweit gewichtet aufsummiert.
    private var portfolioNetYieldForSelectedYear: Double? {
        let relevant = scopedProperties.filter { $0.totalInvestment > 0 }
        guard !relevant.isEmpty else { return nil }
        let totalInvestment = relevant.reduce(0.0) { $0 + $1.totalInvestment }
        guard totalInvestment > 0 else { return nil }
        let totalNetIncome = relevant.reduce(0.0) { $0 + ($1.annualColdRent(forYear: selectedTaxYear) - $1.totalExpenses(forYear: selectedTaxYear)) }
        return (totalNetIncome / totalInvestment) * 100
    }

    private var availableTaxYears: [Int] {
        let years = Set(scopedProperties.flatMap { $0.availableTaxYears })
        return years.isEmpty ? [Calendar.current.component(.year, from: .now)] : years.sorted(by: >)
    }

    private var totalRentForSelectedYear: Double {
        scopedProperties.reduce(0) { $0 + $1.annualColdRent(forYear: selectedTaxYear) }
    }

    private var totalWerbungskostenForSelectedYear: Double {
        scopedProperties.reduce(0) { $0 + $1.werbungskosten(forYear: selectedTaxYear) }
    }

    private var totalAfaForSelectedYear: Double {
        scopedProperties.reduce(0) { $0 + $1.totalAfa(forYear: selectedTaxYear) }
    }

    private var totalTaxableResultForSelectedYear: Double {
        scopedProperties.reduce(0) { $0 + $1.estimatedTaxableResult(forYear: selectedTaxYear) }
    }

    private var totalOperativeCashFlowForSelectedYear: Double {
        scopedProperties.reduce(0) { $0 + $1.operativeCashFlow(forYear: selectedTaxYear) }
    }

    private var totalFreeCashFlowForSelectedYear: Double {
        scopedProperties.reduce(0) { $0 + $1.freeCashFlow(forYear: selectedTaxYear) }
    }

    private var estimatedTaxBurdenForSelectedYear: Double {
        guard let landlord = landlords.first else { return 0 }
        return max(0, totalTaxableResultForSelectedYear) * landlord.marginalTaxRatePercent / 100
    }

    private var cashFlowAfterTaxForSelectedYear: Double {
        totalFreeCashFlowForSelectedYear - estimatedTaxBurdenForSelectedYear
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header

                kpiGrid

                if properties.isEmpty {
                    ContentUnavailableView(
                        "Keine Immobilien",
                        systemImage: "building.2",
                        description: Text("Lege deine erste Immobilie an, um das Dashboard mit Kennzahlen zu füllen.")
                    )
                    .padding(.top, 40)
                } else {
                    tenancyTableSection
                    tasksSection
                    moreMetricsSection
                }
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Übersicht")
        // Property/Unit: zentral in ContentView deklariert (siehe dortiger Kommentar) – hier
        // nicht erneut, sonst ignoriert SwiftUI eine der beiden Deklarationen stillschweigend.
        .navigationDestination(for: Tenancy.self) { tenancy in
            if let tenant = tenancy.tenant {
                TenantDetailView(tenant: tenant)
            }
        }
        .navigationDestination(for: KPIDestination.self) { destination in
            switch destination {
            case .properties: PropertyListView()
            case .payments: PaymentsOverviewView()
            }
        }
        .searchable(text: $searchText, prompt: "Mieter oder Einheit suchen")
        #if os(iOS)
        .toolbar {
            if !tenancyRows.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("Mieter") { sortOrder = [KeyPathComparator(\.tenantName)] }
                        Button("Einheit") { sortOrder = [KeyPathComparator(\.unitLabel)] }
                        Button("Soll-Miete") { sortOrder = [KeyPathComparator(\.sollMiete, order: .reverse)] }
                        Button("Rückstand") { sortOrder = [KeyPathComparator(\.arrears, order: .reverse)] }
                    } label: {
                        Label("Sortieren", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        #endif
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack {
            Picker("Objekt", selection: $selectedProperty) {
                Text("Alle Objekte").tag(Optional<Property>.none)
                ForEach(properties) { property in
                    Text(property.name.isEmpty ? property.address : property.name).tag(Optional(property))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Picker("Zeitraum", selection: $selectedPeriod) {
                ForEach(DashboardPeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Spacer()

            Text(selectedPeriod.currentRangeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - KPI-Karten

    /// Ständig sichtbare Portfolio-Kennzahlen: Bestand, Wert und Rendite der Immobilien selbst.
    /// Zeitraumbezogene, transaktionale Werte (Ausgaben, Zahlungseingänge, offene Forderungen)
    /// stehen dagegen unter „Weitere Kennzahlen", da sie situativ und nicht Teil des
    /// Portfolio-Überblicks auf den ersten Blick sind.
    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
            NavigationLink(value: KPIDestination.properties) {
                KPITile(title: "Immobilien", value: "\(scopedProperties.count)", systemImage: "building.2")
            }
            .buttonStyle(.plain)

            KPITile(title: "Einheiten", value: "\(scopedUnits.count) (\(scopedUnits.filter { $0.activeTenancy != nil }.count) vermietet)", systemImage: "door.left.hand.open")

            KPITile(title: "Kaltmiete (\(selectedPeriod.label.lowercased()))", value: kaltmieteInPeriod.asCurrency, systemImage: "eurosign.circle")

            if totalInvestment > 0 {
                KPITile(title: "Investiertes Kapital", value: totalInvestment.asCurrency, systemImage: "banknote")
            }

            if let portfolioGrossYieldPercent {
                KPITile(title: "Ø Bruttorendite", value: portfolioGrossYieldPercent.asPercent, systemImage: "chart.line.uptrend.xyaxis")
            }

            if let vacancyRatePercent {
                KPITile(title: "Leerstandsquote", value: vacancyRatePercent.asPercent, systemImage: "door.left.hand.closed", valueColor: vacancyRatePercent > 0 ? Theme.statusWarning : Theme.statusGood)
            }
        }
    }

    private enum KPIDestination: Hashable {
        case properties, payments
    }

    // MARK: - Mietverhältnis-Tabelle

    private var tenancyTableSection: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Mietverhältnisse & Zahlungsstatus")
                .font(Theme.sectionTitleFont)

            if tenancyRows.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Keine laufenden Mietverhältnisse" : "Keine Treffer",
                    systemImage: "person.2",
                    description: Text(searchText.isEmpty ? "Für das gewählte Objekt läuft aktuell kein Mietverhältnis." : "Keine Mietverhältnisse für „\(searchText)“.")
                )
                .frame(minHeight: 120)
            } else {
                #if os(macOS)
                Table(tenancyRows, sortOrder: $sortOrder) {
                    TableColumn("Mieter", value: \.tenantName)
                    TableColumn("Einheit", value: \.unitLabel)
                    TableColumn("Soll-Miete", value: \.sollMiete) { row in
                        Text(row.sollMiete.asCurrency)
                    }
                    TableColumn("Status", value: \.statusLabel) { row in
                        Label(row.status.rawValue, systemImage: row.status.systemImage)
                            .foregroundStyle(row.status.color)
                    }
                    TableColumn("Rückstand", value: \.arrears) { row in
                        Text(row.arrears > 0 ? row.arrears.asCurrency : "–")
                            .foregroundStyle(row.arrears > 0 ? Theme.statusCritical : .secondary)
                    }
                }
                .frame(minHeight: 160, idealHeight: CGFloat(tenancyRows.count) * 28 + 40)
                #else
                Theme.card {
                    VStack(spacing: 0) {
                        ForEach(tenancyRows) { row in
                            NavigationLink(value: row.tenancy) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.tenantName)
                                            .foregroundStyle(.primary)
                                        Text(row.unitLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(row.sollMiete.asCurrency)
                                            .font(.subheadline)
                                        Label(row.status.rawValue, systemImage: row.status.systemImage)
                                            .font(.caption2)
                                            .foregroundStyle(row.status.color)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            if row.id != tenancyRows.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Aufgaben

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            Text("Anstehende Aufgaben")
                .font(Theme.sectionTitleFont)

            if reminders.isEmpty {
                ContentUnavailableView(
                    "Keine anstehenden Aufgaben",
                    systemImage: "checkmark.seal",
                    description: Text("Für das gewählte Objekt liegen aktuell keine Fristen oder Hinweise vor.")
                )
                .frame(minHeight: 100)
            } else {
                Theme.card {
                    VStack(spacing: 0) {
                        ForEach(reminders) { reminder in
                            HStack(alignment: .top, spacing: Theme.rowSpacing) {
                                Image(systemName: reminder.systemImage)
                                    .foregroundStyle(reminder.severity.color)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(reminder.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            if reminder.id != reminders.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Weitere Kennzahlen (eingeklappt)

    private var moreMetricsSection: some View {
        DisclosureGroup("Weitere Kennzahlen", isExpanded: $showingMoreMetrics) {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                // Zeitraumbezogene, transaktionale Kennzahlen – reagieren wie die Mietverhältnis-
                // Tabelle auf den Zeitraum-Picker in der Kopfzeile.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.rowSpacing)], spacing: Theme.rowSpacing) {
                    KPITile(title: "Ausgaben (\(selectedPeriod.label.lowercased()))", value: expensesInPeriod.asCurrency, systemImage: "wrench.and.screwdriver")

                    NavigationLink(value: KPIDestination.payments) {
                        KPITile(title: "Zahlungseingänge (\(selectedPeriod.label.lowercased()))", value: paymentsReceivedInPeriod.asCurrency, systemImage: "checkmark.circle", valueColor: Theme.statusGood)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: KPIDestination.payments) {
                        KPITile(title: "Offene Mietforderungen", value: openArrearsInPeriod.asCurrency, systemImage: "exclamationmark.circle", valueColor: openArrearsInPeriod > 0 ? Theme.statusCritical : .primary)
                    }
                    .buttonStyle(.plain)

                    if estimatedMonthlyVacancyLoss > 0 {
                        KPITile(title: "Entgangene Miete/Monat", value: estimatedMonthlyVacancyLoss.asCurrency, systemImage: "arrow.down.circle", valueColor: Theme.statusCritical)
                    }
                }
                .padding(.top, 4)

                if !scopedProperties.isEmpty {
                    HStack {
                        Spacer()
                        Picker("Steuerjahr", selection: $selectedTaxYear) {
                            ForEach(availableTaxYears, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    // 1) Rendite – lohnt sich die Immobilie überhaupt.
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        Text("Rendite \(String(selectedTaxYear))")
                            .font(Theme.sectionTitleFont)
                        HStack(alignment: .top, spacing: 0) {
                            taxMetric(label: "Bruttomietrendite", value: portfolioGrossYieldForSelectedYear?.asPercent ?? "–", color: .primary)
                            Divider()
                            taxMetric(label: "Nettomietrendite", value: portfolioNetYieldForSelectedYear?.asPercent ?? "–", color: .primary)
                            Spacer()
                        }
                        Text("Brutto: Jahreskaltmiete ÷ Kaufpreis. Netto: (Jahreskaltmiete − Jahresausgaben) ÷ Investitionssumme inkl. Kaufnebenkosten.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // 2) Steuerliche Übersicht – was meldet das dem Finanzamt.
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        Text("Steuerliche Übersicht \(String(selectedTaxYear))")
                            .font(Theme.sectionTitleFont)
                        HStack(alignment: .top, spacing: 0) {
                            taxMetric(label: "Mieteinnahmen (Kaltmiete)", value: totalRentForSelectedYear.asCurrency, color: .primary)
                            Divider()
                            taxMetric(label: "Werbungskosten", value: "− " + totalWerbungskostenForSelectedYear.asCurrency, color: Theme.statusCritical)
                            Divider()
                            taxMetric(label: "AfA", value: "− " + totalAfaForSelectedYear.asCurrency, color: Theme.statusCritical)
                        }
                        HStack(alignment: .top, spacing: 0) {
                            taxMetric(label: totalTaxableResultForSelectedYear >= 0 ? "Steuerlicher Überschuss" : "Steuerlicher Verlust", value: abs(totalTaxableResultForSelectedYear).asCurrency, color: totalTaxableResultForSelectedYear >= 0 ? Theme.statusGood : Theme.statusWarning)
                            if landlords.first != nil {
                                Divider()
                                taxMetric(label: "Geschätzte Steuerlast", value: estimatedTaxBurdenForSelectedYear.asCurrency, color: Theme.statusWarning)
                            }
                            Spacer()
                        }
                        Text("Vereinfachte Näherung (Kaltmiete − Werbungskosten − AfA), ersetzt keine Steuerberatung. Steuerlast grob geschätzt aus dem Grenzsteuersatz im Vermieterprofil.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // 3) Cashflow – was bleibt tatsächlich an Geld übrig.
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        Text("Cashflow \(String(selectedTaxYear))")
                            .font(Theme.sectionTitleFont)
                        HStack(alignment: .top, spacing: 0) {
                            taxMetric(label: "Operativer Cashflow", value: totalOperativeCashFlowForSelectedYear.asCurrency, color: totalOperativeCashFlowForSelectedYear >= 0 ? Theme.statusGood : Theme.statusCritical)
                            Divider()
                            taxMetric(label: "Freier Cashflow", value: totalFreeCashFlowForSelectedYear.asCurrency, color: totalFreeCashFlowForSelectedYear >= 0 ? Theme.statusGood : Theme.statusCritical)
                            if landlords.first != nil {
                                Divider()
                                taxMetric(label: "Cashflow nach Steuer", value: cashFlowAfterTaxForSelectedYear.asCurrency, color: cashFlowAfterTaxForSelectedYear >= 0 ? Theme.statusGood : Theme.statusCritical)
                            }
                            Spacer()
                        }
                        Text("Operativer Cashflow: Kaltmiete abzüglich Barausgaben, aller Betriebskosten (umlagefähig + nicht umlagefähig) und Annuität. Freier Cashflow: wie operativ, aber ohne Abzug der umlagefähigen Betriebskosten. Cashflow nach Steuer: freier Cashflow abzüglich geschätzter Steuerlast.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        Text("Immobilien im Überblick")
                            .font(Theme.sectionTitleFont)
                        ForEach(scopedProperties) { property in
                            NavigationLink(value: property) {
                                PropertyInvestmentCard(property: property, year: selectedTaxYear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !scopedExpenses.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        Text("Letzte Ausgaben")
                            .font(Theme.sectionTitleFont)
                        ForEach(scopedExpenses.prefix(5)) { expense in
                            HStack {
                                Image(systemName: expense.category.systemImage)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text(expense.title.isEmpty ? expense.category.label : expense.title)
                                    Text(expense.date.asShortDate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(expense.amount.asCurrency)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.top, Theme.rowSpacing)
        }
        .font(Theme.sectionTitleFont)
    }

    @ViewBuilder
    private func taxMetric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

/// A richer card for one property: purchase price, yield, size and features —
/// everything an investor wants to see at a glance without opening the detail view.
private struct PropertyInvestmentCard: View {
    let property: Property
    let year: Int

    var body: some View {
        Theme.card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(property.name.isEmpty ? property.address : property.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(property.unitCount) Einheit\(property.unitCount == 1 ? "" : "en") · \(property.occupiedUnitCount) vermietet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let gross = property.grossYieldPercent {
                        yieldBadge(gross)
                    }
                }

                HStack(spacing: 18) {
                    metric(label: "Kaufpreis", value: property.purchasePrice > 0 ? property.purchasePrice.asCurrency : "–")
                    metric(label: "Wohnfläche", value: property.totalSizeSquareMeters > 0 ? "\(property.totalSizeSquareMeters.formatted()) m²" : "–")
                    metric(label: "Kaltmiete/Jahr", value: property.annualColdRentFromActiveTenancies > 0 ? property.annualColdRentFromActiveTenancies.asCurrency : "–")
                }

                if property.purchasePrice > 0 {
                    HStack(spacing: 18) {
                        metric(label: "AfA \(String(year))", value: property.totalAfa(forYear: year).asCurrency)
                        metric(label: "Werbungskosten \(String(year))", value: property.werbungskosten(forYear: year).asCurrency)
                        let result = property.estimatedTaxableResult(forYear: year)
                        metric(label: result >= 0 ? "Steuerl. Überschuss" : "Steuerl. Verlust", value: abs(result).asCurrency, color: result >= 0 ? Theme.statusGood : Theme.statusWarning)
                    }
                }

                if !property.aggregatedFeatures.isEmpty {
                    FlowBadges(features: property.aggregatedFeatures)
                }
            }
        }
    }

    @ViewBuilder
    private func metric(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func yieldBadge(_ value: Double) -> some View {
        let color: Color = value >= 5 ? Theme.statusGood : (value >= 3 ? Theme.statusWarning : Theme.statusCritical)
        VStack(alignment: .trailing, spacing: 2) {
            Text(value.asPercent)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text("Bruttorendite")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(PreviewData.container)
}
