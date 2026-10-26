import SwiftUI
import SwiftData

/// Übersicht aller Nebenkostenabrechnungen (Ist) und Wirtschaftspläne (Prognose) über alle
/// Immobilien hinweg, nach Objekt gruppiert – eigener Reiter unter „Mietverwaltung“, damit man
/// nicht erst in die jeweilige Immobilie wechseln muss, um eine Abrechnung oder einen
/// Wirtschaftsplan zu erfassen, zu prüfen oder anzupassen. Ein Tracker zeigt zusätzlich, für
/// welche Objekte/Jahre noch eine Abrechnung bzw. ein Wirtschaftsplan fehlt, und ein
/// Soll-Ist-Vergleich stellt beide für gemeinsame Jahre gegenüber.
struct UtilityStatementListView: View {
    @Environment(\.modelContext) private var modelContext
    // Sortierung nach `periodEnd` statt dem abgeleiteten `year` – SwiftData kann `@Query(sort:)`
    // nur für tatsächlich gespeicherte Attribute auflösen, nicht für eine berechnete Eigenschaft.
    @Query(sort: \UtilityStatement.periodEnd, order: .reverse) private var statements: [UtilityStatement]
    @Query(sort: \WirtschaftsplanStatement.year, order: .reverse) private var plans: [WirtschaftsplanStatement]
    @Query(sort: \Property.name) private var properties: [Property]
    @State private var propertyForNewStatement: Property?
    @State private var propertyForNewPlan: Property?
    @State private var searchText = ""
    @State private var pendingDeletion: (entries: [Entry], offsets: IndexSet)?
    /// Welche Objekte im Tracker aufgeklappt sind – bei mehreren Immobilien startet jedes
    /// eingeklappt (Überfälligkeiten bleiben trotzdem als Zähler im Titel sichtbar), bei genau
    /// einer Immobilie bleibt es wie bisher direkt sichtbar.
    @State private var expandedTrackerProperties: Set<String> = []
    @State private var didSetInitialTrackerExpansion = false

    /// Ein Eintrag in der Objekt-Liste – entweder eine tatsächliche Abrechnung (Ist) oder ein
    /// Wirtschaftsplan (Prognose/Soll).
    enum Entry: Identifiable {
        case actual(UtilityStatement)
        case forecast(WirtschaftsplanStatement)

        var id: ObjectIdentifier {
            switch self {
            case .actual(let statement): return ObjectIdentifier(statement)
            case .forecast(let plan): return ObjectIdentifier(plan)
            }
        }

        var year: Int {
            switch self {
            case .actual(let statement): return statement.year
            case .forecast(let plan): return plan.year
            }
        }

        var sortRank: Int {
            switch self {
            case .actual: return 0
            case .forecast: return 1
            }
        }
    }

    private struct PropertyGroup: Identifiable {
        let propertyName: String
        let entries: [Entry]
        var id: String { propertyName }
    }

    private var groupedByProperty: [PropertyGroup] {
        let all = statements.map { Entry.actual($0) } + plans.map { Entry.forecast($0) }
        let grouped = Dictionary(grouping: all) { entry -> String in
            switch entry {
            case .actual(let statement): return statement.property?.name ?? "Ohne Immobilie"
            case .forecast(let plan): return plan.property?.name ?? "Ohne Immobilie"
            }
        }
        return grouped
            .map { propertyName, entries in
                PropertyGroup(propertyName: propertyName, entries: entries.sorted {
                    if $0.year != $1.year { return $0.year > $1.year }
                    return $0.sortRank < $1.sortRank
                })
            }
            .sorted { $0.propertyName < $1.propertyName }
    }

    private var filteredGroupedByProperty: [PropertyGroup] {
        guard !searchText.isEmpty else { return groupedByProperty }
        return groupedByProperty.compactMap { group in
            if group.propertyName.localizedCaseInsensitiveContains(searchText) {
                return group
            }
            let filteredEntries = group.entries.filter { String($0.year).contains(searchText) }
            guard !filteredEntries.isEmpty else { return nil }
            return PropertyGroup(propertyName: group.propertyName, entries: filteredEntries)
        }
    }

    // MARK: - Tracker

    private struct TrackerRow: Identifiable {
        let year: Int
        /// Ob für dieses Jahr überhaupt schon eine Abrechnung erwartet werden kann (nicht für
        /// Zukunftsjahre, die noch nicht begonnen haben).
        let showsStatement: Bool
        let hasStatement: Bool
        let statementOverdue: Bool
        let hasPlan: Bool
        let planOverdue: Bool
        var id: Int { year }
    }

    private struct TrackerGroup: Identifiable {
        let propertyName: String
        let rows: [TrackerRow]
        var id: String { propertyName }
        /// Anzahl überfälliger Abrechnungen/Wirtschaftspläne – bleibt auch bei eingeklapptem
        /// Objekt sichtbar, damit man bei mehreren Immobilien nicht jede einzeln aufklappen muss.
        var overdueCount: Int { rows.filter { $0.statementOverdue || $0.planOverdue }.count }
    }

    /// Für jedes Objekt mit mindestens einer Einheit (auch bei Leerstand, da WEG-Betriebskosten
    /// unabhängig von der Vermietung anfallen) das kommende sowie die letzten drei Jahre: liegt
    /// eine Abrechnung bzw. ein Wirtschaftsplan vor? „Überfällig“ bei der Abrechnung richtet sich
    /// nach der gesetzlichen Frist (12 Monate nach Ablauf des Abrechnungsjahres, §556 Abs. 3 BGB),
    /// beim Wirtschaftsplan nach demselben 1.-April-Cutoff wie die Dashboard-Hinweise.
    private var trackerGroups: [TrackerGroup] {
        let calendar = Calendar.current
        let today = Date.now
        let currentYear = calendar.component(.year, from: today)
        let years = [currentYear + 1, currentYear, currentYear - 1, currentYear - 2]
        let planCutoff = calendar.date(from: DateComponents(year: currentYear, month: 4, day: 1)) ?? today

        return properties.compactMap { property -> TrackerGroup? in
            guard !(property.units ?? []).isEmpty else { return nil }
            let statementYears = Set((property.utilityStatements ?? []).map { $0.year })
            let planYears = Set((property.wirtschaftsplaene ?? []).map { $0.year })

            let rows = years.map { year -> TrackerRow in
                let showsStatement = year <= currentYear
                let hasStatement = statementYears.contains(year)
                let deadline = calendar.date(from: DateComponents(year: year + 1, month: 12, day: 31)) ?? today
                let statementOverdue = showsStatement && !hasStatement && deadline < today
                let hasPlan = planYears.contains(year)
                let planOverdue = year == currentYear && !hasPlan && today >= planCutoff
                return TrackerRow(
                    year: year,
                    showsStatement: showsStatement,
                    hasStatement: hasStatement,
                    statementOverdue: statementOverdue,
                    hasPlan: hasPlan,
                    planOverdue: planOverdue
                )
            }
            return TrackerGroup(propertyName: property.name.isEmpty ? property.address : property.name, rows: rows)
        }
        .sorted { $0.propertyName < $1.propertyName }
    }

    // MARK: - Soll-Ist-Vergleich

    private struct ComparisonRow: Identifiable {
        let propertyName: String
        let year: Int
        let planApportionable: Double
        let actualApportionable: Double
        let planNonApportionable: Double
        let actualNonApportionable: Double
        var planTotal: Double { planApportionable + planNonApportionable }
        var actualTotal: Double { actualApportionable + actualNonApportionable }
        var difference: Double { actualTotal - planTotal }
        var id: String { "\(propertyName)-\(year)" }
    }

    /// Für jedes Objekt/Jahr, in dem sowohl eine Abrechnung als auch ein Wirtschaftsplan
    /// vorliegen, die Gegenüberstellung von Soll (Wirtschaftsplan) und Ist (Abrechnung).
    private var comparisonRows: [ComparisonRow] {
        var rows: [ComparisonRow] = []
        for property in properties {
            let statementsByYear = Dictionary(grouping: property.utilityStatements ?? []) { $0.year }
            let plansByYear = Dictionary(grouping: property.wirtschaftsplaene ?? []) { $0.year }
            let commonYears = Set(statementsByYear.keys).intersection(plansByYear.keys)
            for year in commonYears {
                guard let statement = statementsByYear[year]?.first, let plan = plansByYear[year]?.first else { continue }
                rows.append(ComparisonRow(
                    propertyName: property.name.isEmpty ? property.address : property.name,
                    year: year,
                    planApportionable: plan.totalApportionableCosts,
                    actualApportionable: statement.totalApportionableCosts,
                    planNonApportionable: plan.nonApportionableLineItemsTotal,
                    actualNonApportionable: statement.nonApportionableLineItemsTotal
                ))
            }
        }
        return rows.sorted {
            $0.year != $1.year ? $0.year > $1.year : $0.propertyName < $1.propertyName
        }
    }

    var body: some View {
        List {
            if !trackerGroups.isEmpty {
                Section {
                    ForEach(trackerGroups) { group in
                        DisclosureGroup(isExpanded: trackerExpansionBinding(for: group.propertyName)) {
                            ForEach(group.rows) { row in
                                HStack(spacing: 14) {
                                    Text(String(row.year))
                                        .frame(width: 40, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    if row.showsStatement {
                                        trackerBadge(label: "Abrechnung", present: row.hasStatement, overdue: row.statementOverdue)
                                    } else {
                                        Label("Abrechnung", systemImage: "minus.circle")
                                            .foregroundStyle(.secondary.opacity(0.5))
                                    }
                                    trackerBadge(label: "Wirtschaftsplan", present: row.hasPlan, overdue: row.planOverdue)
                                }
                                .font(.caption)
                                .padding(.vertical, 1)
                            }
                        } label: {
                            HStack {
                                Text(group.propertyName)
                                    .font(.subheadline.weight(.semibold))
                                if group.overdueCount > 0 {
                                    Spacer()
                                    Label("\(group.overdueCount)", systemImage: "exclamationmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.statusCritical)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tracker")
                } footer: {
                    Text("Kommendes sowie letzte drei Jahre je Objekt, auch bei Leerstand. Rot bei Abrechnung = gesetzliche Frist (12 Monate nach Ablauf des Abrechnungsjahres, §556 Abs. 3 BGB) bereits abgelaufen. Rot bei Wirtschaftsplan = für das laufende Jahr nach dem 1. April noch nicht erfasst. „–“ = für dieses Jahr noch keine Abrechnung erwartbar. Die Zahl neben einem eingeklappten Objekt zeigt überfällige Punkte.")
                }
                .onAppear {
                    guard !didSetInitialTrackerExpansion else { return }
                    didSetInitialTrackerExpansion = true
                    if trackerGroups.count == 1, let only = trackerGroups.first {
                        expandedTrackerProperties = [only.propertyName]
                    }
                }
            }

            if !comparisonRows.isEmpty {
                Section {
                    ForEach(comparisonRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(row.propertyName) · \(String(row.year))")
                                .font(.subheadline.weight(.semibold))
                            HStack {
                                Text("Umlagefähig")
                                Spacer()
                                Text("Soll \(row.planApportionable.asCurrency) · Ist \(row.actualApportionable.asCurrency)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack {
                                Text("Nicht umlagefähig")
                                Spacer()
                                Text("Soll \(row.planNonApportionable.asCurrency) · Ist \(row.actualNonApportionable.asCurrency)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack {
                                Text("Differenz gesamt (Ist − Soll)")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(row.difference >= 0 ? "+\(row.difference.asCurrency)" : row.difference.asCurrency)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(row.difference > 0.5 ? Theme.statusCritical : (row.difference < -0.5 ? Theme.statusGood : .secondary))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Soll-Ist-Vergleich")
                } footer: {
                    Text("Vergleicht den Wirtschaftsplan (Soll) mit der tatsächlichen Abrechnung (Ist) für Jahre, in denen beides vorliegt. Positive Differenz = höhere tatsächliche Kosten als geplant.")
                }
            }

            ForEach(filteredGroupedByProperty) { group in
                Section {
                    ForEach(group.entries) { entry in
                        switch entry {
                        case .actual(let statement):
                            NavigationLink(value: statement) {
                                HStack {
                                    Text("\(String(statement.year)) · Abrechnung")
                                    Spacer()
                                    Text(statement.totalCosts.asCurrency)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        case .forecast(let plan):
                            NavigationLink(value: plan) {
                                HStack {
                                    Text("\(String(plan.year)) · Wirtschaftsplan (Prognose)")
                                    Spacer()
                                    Text(plan.totalCosts.asCurrency)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in pendingDeletion = (group.entries, offsets) }
                } header: {
                    Text(group.propertyName)
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle("Nebenkostenabrechnung")
        .searchable(text: $searchText, prompt: "Objekt oder Jahr suchen")
        // UtilityStatement: zentral in ContentView deklariert, siehe dortiger Kommentar.
        .navigationDestination(for: WirtschaftsplanStatement.self) { plan in
            WirtschaftsplanDetailView(plan: plan)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(properties) { property in
                        Button(property.name.isEmpty ? property.address : property.name) {
                            propertyForNewStatement = property
                        }
                    }
                } label: {
                    Label("Abrechnung hochladen", systemImage: "doc.text.viewfinder")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(properties.isEmpty)
                .help("Abrechnung der Hausverwaltung hochladen")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(properties) { property in
                        Button(property.name.isEmpty ? property.address : property.name) {
                            propertyForNewPlan = property
                        }
                    }
                } label: {
                    Label("Wirtschaftsplan hochladen", systemImage: "doc.badge.clock")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(properties.isEmpty)
            }
        }
        .sheet(item: $propertyForNewStatement) { property in
            UtilityStatementEditView(property: property, statement: nil)
        }
        .sheet(item: $propertyForNewPlan) { property in
            WirtschaftsplanEditView(property: property, plan: nil)
        }
        .alert(
            "Wirklich löschen?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
            Button("Löschen", role: .destructive) {
                if let pendingDeletion {
                    deleteEntries(in: pendingDeletion.entries, at: pendingDeletion.offsets)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("Die Abrechnung bzw. der Wirtschaftsplan mit allen Kostenarten wird endgültig gelöscht.")
        }
        .overlay {
            if properties.isEmpty {
                ContentUnavailableView(
                    "Keine Immobilien",
                    systemImage: "building.2",
                    description: Text("Lege zuerst eine Immobilie an, um eine Nebenkostenabrechnung zu erfassen.")
                )
            } else if statements.isEmpty && plans.isEmpty {
                ContentUnavailableView(
                    "Keine Nebenkostenabrechnungen",
                    systemImage: "doc.text",
                    description: Text("Erfasse die Abrechnung deiner Hausverwaltung oder den Wirtschaftsplan – per Hand, aus einem gescannten Beleg oder aus einer CSV-Datei.")
                )
            } else if filteredGroupedByProperty.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func trackerExpansionBinding(for propertyName: String) -> Binding<Bool> {
        Binding(
            get: { expandedTrackerProperties.contains(propertyName) },
            set: { isExpanded in
                if isExpanded { expandedTrackerProperties.insert(propertyName) } else { expandedTrackerProperties.remove(propertyName) }
            }
        )
    }

    @ViewBuilder
    private func trackerBadge(label: String, present: Bool, overdue: Bool) -> some View {
        Label(label, systemImage: present ? "checkmark.circle.fill" : (overdue ? "exclamationmark.circle.fill" : "circle"))
            .foregroundStyle(present ? Theme.statusGood : (overdue ? Theme.statusCritical : .secondary))
    }

    private func deleteEntries(in group: [Entry], at offsets: IndexSet) {
        for index in offsets {
            switch group[index] {
            case .actual(let statement): modelContext.delete(statement)
            case .forecast(let plan): modelContext.delete(plan)
            }
        }
    }
}

#Preview {
    NavigationStack {
        UtilityStatementListView()
    }
    .modelContainer(PreviewData.container)
}
