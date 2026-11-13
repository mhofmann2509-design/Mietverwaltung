import SwiftUI
import SwiftData

struct PaymentsOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tenancies: [Tenancy]
    @State private var paymentEntryRequest: PaymentEntryRequest?
    @State private var showingAddYearSheet = false

    /// Wenn gesetzt, zeigt diese Instanz nur dieses eine Jahr – für den Jahres-Unterreiter in der
    /// Seitenleiste. Ohne Vorgabe werden alle Jahre mit laufenden Mietverhältnissen angezeigt,
    /// dafür aber nur die aktuellen Mietrückstände statt der vollen Monatsliste.
    var fixedYear: Int? = nil

    /// Trägt zusammen, für welchen Mieter/welchen Monat gerade eine Zahlung erfasst werden soll.
    private struct PaymentEntryRequest: Identifiable {
        let tenancy: Tenancy
        let month: Date
        var id: String { "\(tenancy.persistentModelID)-\(month)" }
    }

    private struct LedgerRow: Identifiable {
        let month: Date
        let due: Double
        let paid: Double
        let runningBalance: Double
        var id: Date { month }
    }

    /// Das Mietrückstandskonto eines Mieters für das gewählte Jahr: der Saldo läuft dabei vom
    /// Jahresanfang (inkl. etwaiger Rückstände aus Vorjahren) durch, damit er dem tatsächlichen
    /// Kontostand entspricht und nicht jedes Jahr bei 0 neu beginnt.
    private struct TenantYearGroup: Identifiable {
        let tenancy: Tenancy
        let rows: [LedgerRow]
        var id: PersistentIdentifier { tenancy.persistentModelID }
        var totalDue: Double { rows.reduce(0) { $0 + $1.due } }
        var finalBalance: Double { rows.last?.runningBalance ?? 0 }
    }

    private func tenantGroups(forYear year: Int) -> [TenantYearGroup] {
        tenancies
            .filter { RentLedger.isRelevant($0, inYear: year) }
            .map { tenancy in
                let rows = RentLedger.rows(for: tenancy, year: year).map {
                    LedgerRow(month: $0.month, due: $0.due, paid: $0.paid, runningBalance: $0.runningBalance)
                }
                return TenantYearGroup(tenancy: tenancy, rows: rows)
            }
            .sorted { ($0.tenancy.tenant?.fullName ?? "") < ($1.tenancy.tenant?.fullName ?? "") }
    }

    /// Alle Jahre, in denen mindestens ein Mietverhältnis läuft (aus Beginn-/Enddatum
    /// abgeleitet), plus das laufende Jahr – absteigend sortiert.
    private var availableYears: [Int] { RentLedger.availableYears(for: tenancies) }

    private struct YearSection: Identifiable {
        let year: Int
        let groups: [TenantYearGroup]
        var id: Int { year }
        var totalDue: Double { groups.reduce(0) { $0 + $1.totalDue } }
    }

    /// Die anzuzeigenden Jahre: entweder nur `fixedYear` oder alle Jahre mit Daten.
    private var displayedYearSections: [YearSection] {
        if let fixedYear {
            let groups = tenantGroups(forYear: fixedYear)
            return groups.isEmpty ? [] : [YearSection(year: fixedYear, groups: groups)]
        }
        return availableYears
            .map { YearSection(year: $0, groups: tenantGroups(forYear: $0)) }
            .filter { !$0.groups.isEmpty }
    }

    /// Aktuelle Mietrückstände je Mieter (unabhängig vom Jahr) – für die Übersicht im
    /// allgemeinen Zahlungen-Reiter, über alle Jahre hinweg zum heutigen Stichtag.
    private var currentArrears: [(tenancy: Tenancy, balance: Double)] {
        RentLedger.currentArrears(tenancies)
    }

    var body: some View {
        List {
            if fixedYear == nil && !currentArrears.isEmpty {
                Section {
                    ForEach(currentArrears, id: \.tenancy.persistentModelID) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.tenancy.tenant?.fullName ?? "Unbekannter Mieter")
                                Text("\(entry.tenancy.unit?.property?.name ?? "") · \(entry.tenancy.unit?.name ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(label: "Rückstand \(entry.balance.asCurrency)", tone: .critical)
                        }
                    }
                } header: {
                    Text("Mietrückstände")
                } footer: {
                    Text("Offene Soll-Beträge aus allen Vorjahren und dem laufenden Jahr, Stand heute.")
                }
            }

            if displayedYearSections.isEmpty {
                ContentUnavailableView(
                    "Keine Mietverhältnisse",
                    systemImage: "eurosign.circle",
                    description: Text(fixedYear.map { "In \(String($0)) läuft kein Mietverhältnis." } ?? "Noch keine Mietverhältnisse erfasst.")
                )
            } else {
                ForEach(displayedYearSections) { section in
                    Section {
                        ForEach(section.groups) { group in
                            DisclosureGroup {
                                ForEach(group.rows) { row in
                                    paymentRow(for: group.tenancy, row: row)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.tenancy.tenant?.fullName ?? "Unbekannter Mieter")
                                            .font(.headline)
                                        Text("\(group.tenancy.unit?.property?.name ?? "") · \(group.tenancy.unit?.name ?? "")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if group.finalBalance > 0.005 {
                                        StatusBadge(label: "Rückstand \(group.finalBalance.asCurrency)", tone: .critical)
                                    } else if group.finalBalance < -0.005 {
                                        StatusBadge(label: "Guthaben \(abs(group.finalBalance).asCurrency)", tone: .good)
                                    } else {
                                        StatusBadge(label: "Ausgeglichen", tone: .neutral)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(String(section.year))
                            .font(.title3.weight(.bold))
                    } footer: {
                        Text("Gesamteinnahmen \(String(section.year)): \(section.totalDue.asCurrency)")
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle(fixedYear.map { "Zahlungen \(String($0))" } ?? "Zahlungen")
        .toolbar {
            if fixedYear == nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddYearSheet = true
                    } label: {
                        Label("Jahr hinzufügen", systemImage: "calendar.badge.plus")
                    }
                }
            }
        }
        .sheet(item: $paymentEntryRequest) { request in
            RecordPaymentView(tenancy: request.tenancy, month: request.month)
        }
        .sheet(isPresented: $showingAddYearSheet) {
            AddYearView(category: "payments", existingYears: availableYears)
        }
    }

    @ViewBuilder
    private func paymentRow(for tenancy: Tenancy, row: LedgerRow) -> some View {
        let payment = tenancy.payment(forMonthContaining: row.month)
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.month.asMonthYear)
                    .font(.subheadline)
                Text("Soll: \(row.due.asCurrency) · Bezahlt: \(row.paid.asCurrency)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(for: payment)
                Text("Saldo: \(row.runningBalance.asCurrency)")
                    .font(.caption2)
                    .foregroundStyle(row.runningBalance > 0.005 ? Theme.statusCritical : .secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            paymentEntryRequest = PaymentEntryRequest(tenancy: tenancy, month: row.month)
        }
        .swipeActions(edge: .trailing) {
            if payment?.isPaid != true {
                Button("Als bezahlt markieren") {
                    markPaid(tenancy: tenancy, month: row.month)
                }
                .tint(Theme.statusGood)
            } else {
                Button("Als offen markieren") {
                    markUnpaid(tenancy: tenancy, month: row.month)
                }
                .tint(Theme.statusWarning)
            }
        }
        .swipeActions(edge: .leading) {
            if let payment, payment.isOverdue {
                #if os(iOS)
                Button {
                    SharePresenter.present([mahnungText(tenancy: tenancy, payment: payment)])
                } label: {
                    Label("Mahnung", systemImage: "exclamationmark.bubble")
                }
                .tint(Theme.statusCritical)
                #else
                ShareLink(item: mahnungText(tenancy: tenancy, payment: payment)) {
                    Label("Mahnung", systemImage: "exclamationmark.bubble")
                }
                .tint(Theme.statusCritical)
                #endif
            }
        }
    }

    private func mahnungText(tenancy: Tenancy, payment: RentPayment) -> String {
        """
        Zahlungserinnerung

        Sehr geehrte(r) \(tenancy.tenant?.fullName ?? "Mieter/in"),

        für \(tenancy.unit?.property?.name ?? "") · \(tenancy.unit?.name ?? "") ist die Miete für \(payment.dueDate.asMonthYear) noch nicht bei uns eingegangen:

        Fälliger Betrag: \(payment.totalDue.asCurrency)
        Fällig seit: \(payment.dueDate.asShortDate)

        Wir bitten um kurzfristigen Ausgleich des offenen Betrags. Sollte die Zahlung bereits veranlasst worden sein, betrachten Sie dieses Schreiben als gegenstandslos.

        Mit freundlichen Grüßen
        """
    }

    @ViewBuilder
    private func statusBadge(for payment: RentPayment?) -> some View {
        if let payment, payment.isPaid {
            StatusBadge(label: "Bezahlt", tone: .good)
        } else if let payment, payment.isOverdue {
            StatusBadge(label: "Überfällig", tone: .critical)
        } else {
            StatusBadge(label: "Offen", tone: .warning)
        }
    }

    private func markPaid(tenancy: Tenancy, month: Date) {
        RentLedger.markPaid(tenancy: tenancy, month: month, context: modelContext)
    }

    private func markUnpaid(tenancy: Tenancy, month: Date) {
        RentLedger.markUnpaid(tenancy: tenancy, month: month)
    }
}

#Preview {
    NavigationStack {
        PaymentsOverviewView()
    }
    .modelContainer(PreviewData.container)
}
