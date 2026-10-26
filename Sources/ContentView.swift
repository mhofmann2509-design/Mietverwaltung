import SwiftUI
import SwiftData

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case properties
    case tenants
    case payments
    case utilityStatements
    case landlord
    case expenses
    case furniture
    case improvements
    case documents
    case taxGlossary
    case tax
    case appearance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Übersicht"
        case .properties: return "Immobilien"
        case .tenants: return "Mieter"
        case .payments: return "Zahlungen"
        case .utilityStatements: return "Nebenkostenabrechnung"
        case .landlord: return "Vermieter"
        case .expenses: return "Ausgaben"
        case .furniture: return "Möblierung"
        case .improvements: return "Herstellungskosten"
        case .documents: return "Dokumente"
        case .taxGlossary: return "Steuerbegriffe"
        case .tax: return "Steuern"
        case .appearance: return "Darstellung"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house"
        case .properties: return "building.2"
        case .tenants: return "person.2"
        case .payments: return "eurosign.circle"
        case .utilityStatements: return "doc.text"
        case .landlord: return "person.text.rectangle"
        case .expenses: return "wrench.and.screwdriver"
        case .furniture: return "sofa"
        case .improvements: return "hammer"
        case .documents: return "folder"
        case .taxGlossary: return "book"
        case .tax: return "percent"
        case .appearance: return "paintpalette"
        }
    }
}

/// Entweder ein fester Reiter oder ein direkt in der Seitenleiste angewähltes Unterelement
/// (einzelne Immobilie/Mieter/Jahr/Objekt) – ermöglicht Unterordner/Unterreiter in der Navigation.
enum SidebarSelection: Hashable {
    case section(SidebarSection)
    case property(Property)
    case tenant(Tenant)
    case paymentsYear(Int)
    case expensesYear(Int)
    case improvementsYear(Int)
    case furnitureProperty(Property)
    case furniturePropertyCoRented(Property)
    case documentsUnit(Unit)
    case documentsUtilityStatements
}

struct ContentView: View {
    @ObservedObject private var appearanceStore = AppearanceStore.shared
    @State private var selection: SidebarSelection? = .section(.dashboard)
    @State private var propertiesOverviewExpanded = true
    @State private var tenantsExpanded = true
    @State private var paymentsExpanded = true
    @State private var expensesExpanded = true
    @State private var improvementsExpanded = true
    @State private var furnitureExpanded = true
    @State private var documentsExpanded = true
    @State private var documentsUnitsExpanded = true
    @Query(sort: \Property.name) private var properties: [Property]
    @Query(sort: \Tenant.lastName) private var tenants: [Tenant]
    @Query(sort: \Unit.name) private var units: [Unit]
    @Query private var tenancies: [Tenancy]
    @Query private var expenses: [Expense]
    @Query private var depreciableAssets: [DepreciableAsset]
    @Query private var trackedYears: [TrackedYear]

    private func trackedYears(for category: String) -> Set<Int> {
        Set(trackedYears.filter { $0.category == category }.map { $0.year })
    }

    /// Beschriftung einer Immobilie in der Seitenleiste: zeigt die Straße immer mit an, auch wenn
    /// eine eigene Bezeichnung vergeben wurde (z.B. „Objekt A · Musterstraße 1“) – sonst ist bei
    /// mehreren Immobilien mit frei gewähltem Namen nicht erkennbar, um welches Objekt es geht.
    private func sidebarPropertyLabel(_ property: Property) -> String {
        if property.name.isEmpty { return property.street.isEmpty ? property.address : property.street }
        if property.name == property.street || property.street.isEmpty { return property.name }
        return "\(property.name) · \(property.street)"
    }

    /// Alle Jahre, in denen mindestens ein Mietverhältnis läuft, plus das laufende Jahr und manuell
    /// hinzugefügte Jahre (siehe `TrackedYear`) – absteigend sortiert; Basis für die
    /// Jahres-Unterreiter unter Zahlungen.
    private var paymentYears: [Int] {
        let calendar = Calendar.current
        var years = Set<Int>()
        for tenancy in tenancies {
            let startYear = calendar.component(.year, from: tenancy.startDate)
            let endYear = tenancy.endDate.map { calendar.component(.year, from: $0) } ?? calendar.component(.year, from: .now)
            guard startYear <= endYear else { continue }
            for year in startYear...endYear { years.insert(year) }
        }
        years.insert(calendar.component(.year, from: .now))
        years.formUnion(trackedYears(for: "payments"))
        return years.sorted(by: >)
    }

    /// Alle Jahre mit erfassten Ausgaben, plus das laufende Jahr und manuell hinzugefügte Jahre –
    /// absteigend sortiert; Basis für die Jahres-Unterreiter unter Ausgaben.
    private var expenseYears: [Int] {
        let calendar = Calendar.current
        var years = Set(expenses.map { calendar.component(.year, from: $0.date) })
        years.insert(calendar.component(.year, from: .now))
        years.formUnion(trackedYears(for: "expenses"))
        return years.sorted(by: >)
    }

    /// Alle Anschaffungsjahre erfasster Herstellungskosten, plus das laufende Jahr und manuell
    /// hinzugefügte Jahre – absteigend sortiert; Basis für die Jahres-Unterreiter unter
    /// Herstellungskosten.
    private var improvementYears: [Int] {
        let calendar = Calendar.current
        var years = Set(
            depreciableAssets
                .filter { $0.category == .improvement }
                .map { calendar.component(.year, from: $0.placedInServiceDate) }
        )
        years.insert(calendar.component(.year, from: .now))
        years.formUnion(trackedYears(for: "improvements"))
        return years.sorted(by: >)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(SidebarSection.dashboard.label, systemImage: SidebarSection.dashboard.systemImage)
                    .tag(SidebarSelection.section(.dashboard))

                Section("Immobilien") {
                    DisclosureGroup(isExpanded: $propertiesOverviewExpanded) {
                        Label("Alle Immobilien", systemImage: "list.bullet")
                            .tag(SidebarSelection.section(.properties))
                        ForEach(properties) { property in
                            Label(sidebarPropertyLabel(property), systemImage: "building")
                                .tag(SidebarSelection.property(property))
                        }
                    } label: {
                        Label("Übersicht", systemImage: SidebarSection.properties.systemImage)
                    }
                }

                Section("Mietverwaltung") {
                    DisclosureGroup(isExpanded: $tenantsExpanded) {
                        Label("Alle Mieter", systemImage: "list.bullet")
                            .tag(SidebarSelection.section(.tenants))
                        ForEach(tenants) { tenant in
                            Label(tenant.fullName, systemImage: "person")
                                .tag(SidebarSelection.tenant(tenant))
                        }
                    } label: {
                        Label(SidebarSection.tenants.label, systemImage: SidebarSection.tenants.systemImage)
                    }
                    DisclosureGroup(isExpanded: $paymentsExpanded) {
                        Label("Gesamtübersicht", systemImage: "list.bullet")
                            .tag(SidebarSelection.section(.payments))
                        ForEach(paymentYears, id: \.self) { year in
                            Label(String(year), systemImage: "calendar")
                                .tag(SidebarSelection.paymentsYear(year))
                        }
                    } label: {
                        Label(SidebarSection.payments.label, systemImage: SidebarSection.payments.systemImage)
                    }
                    Label(SidebarSection.utilityStatements.label, systemImage: SidebarSection.utilityStatements.systemImage)
                        .tag(SidebarSelection.section(.utilityStatements))
                    Label(SidebarSection.landlord.label, systemImage: SidebarSection.landlord.systemImage)
                        .tag(SidebarSelection.section(.landlord))
                }

                Section("Steuerliche Erfassung") {
                    DisclosureGroup(isExpanded: $expensesExpanded) {
                        Label("Alle Jahre", systemImage: "list.bullet")
                            .tag(SidebarSelection.section(.expenses))
                        ForEach(expenseYears, id: \.self) { year in
                            Label(String(year), systemImage: "calendar")
                                .tag(SidebarSelection.expensesYear(year))
                        }
                    } label: {
                        Label(SidebarSection.expenses.label, systemImage: SidebarSection.expenses.systemImage)
                    }
                    DisclosureGroup(isExpanded: $furnitureExpanded) {
                        Label("Alle Immobilien", systemImage: "list.bullet")
                            .tag(SidebarSelection.section(.furniture))
                        ForEach(properties) { property in
                            DisclosureGroup {
                                Label("Mitvermietet", systemImage: "key.horizontal")
                                    .tag(SidebarSelection.furniturePropertyCoRented(property))
                            } label: {
                                Label(property.name.isEmpty ? property.address : property.name, systemImage: "building")
                                    .tag(SidebarSelection.furnitureProperty(property))
                            }
                        }
                    } label: {
                        Label(SidebarSection.furniture.label, systemImage: SidebarSection.furniture.systemImage)
                    }
                    DisclosureGroup(isExpanded: $improvementsExpanded) {
                        Label("Alle Jahre", systemImage: "list.bullet")
                            .tag(SidebarSelection.section(.improvements))
                        ForEach(improvementYears, id: \.self) { year in
                            Label(String(year), systemImage: "calendar")
                                .tag(SidebarSelection.improvementsYear(year))
                        }
                    } label: {
                        Label(SidebarSection.improvements.label, systemImage: SidebarSection.improvements.systemImage)
                    }
                    Label(SidebarSection.tax.label, systemImage: SidebarSection.tax.systemImage)
                        .tag(SidebarSelection.section(.tax))
                    Label(SidebarSection.taxGlossary.label, systemImage: SidebarSection.taxGlossary.systemImage)
                        .tag(SidebarSelection.section(.taxGlossary))
                }

                Section("Dokumentenablage") {
                    DisclosureGroup(isExpanded: $documentsExpanded) {
                        Label("Alle Dokumente", systemImage: "list.bullet")
                            .tag(SidebarSelection.section(.documents))
                        DisclosureGroup(isExpanded: $documentsUnitsExpanded) {
                            ForEach(units) { unit in
                                Label("\(unit.property?.name ?? "") · \(unit.name)", systemImage: "door.left.hand.open")
                                    .tag(SidebarSelection.documentsUnit(unit))
                            }
                        } label: {
                            Label("Wohnungen", systemImage: "building")
                        }
                        Label("Abrechnungen", systemImage: "doc.text")
                            .tag(SidebarSelection.documentsUtilityStatements)
                    } label: {
                        Label(SidebarSection.documents.label, systemImage: SidebarSection.documents.systemImage)
                    }
                }

                Section("Einstellungen") {
                    Label(SidebarSection.appearance.label, systemImage: SidebarSection.appearance.systemImage)
                        .tag(SidebarSelection.section(.appearance))
                }
            }
            .themedScrollBackground()
            .navigationTitle("Mietverwaltung")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            // `.id(selection)` erzwingt einen frischen NavigationStack (leerer Pfad) bei jedem
            // Reiterwechsel. Ohne das bleibt der Navigationspfad eines zuvor geöffneten Details
            // (z.B. einer Immobilie) beim Zurückwechseln bestehen und lässt sich nicht mehr schließen.
            NavigationStack {
                // In einem Group gekapselt, damit die navigationDestination-Modifier unten
                // innerhalb des NavigationStack-Inhalts greifen – direkt auf dem NavigationStack
                // selbst angewendet (außerhalb seines Inhalts-Closures) interpretiert SwiftUI sie
                // innerhalb eines NavigationSplitView fälschlich als Ziel für eine nächste Spalte
                // („There is no next column after the detail column“), wodurch der Link gar nicht
                // mehr navigiert.
                Group {
                switch selection ?? .section(.dashboard) {
                case .section(let section):
                    switch section {
                    case .dashboard: DashboardView()
                    case .properties: PropertyListView()
                    case .tenants: TenantListView()
                    case .payments: PaymentsOverviewView()
                    case .utilityStatements: UtilityStatementListView()
                    case .landlord: LandlordView()
                    case .expenses: ExpenseListView()
                    case .furniture: MoeblierungListView()
                    case .improvements: HerstellungskostenListView()
                    case .documents: DocumentListView()
                    case .taxGlossary: TaxGlossaryView()
                    case .tax: TaxModuleView()
                    case .appearance: AppearanceSettingsView()
                    }
                case .property(let property):
                    PropertyDetailView(property: property)
                case .tenant(let tenant):
                    TenantDetailView(tenant: tenant)
                case .paymentsYear(let year):
                    PaymentsOverviewView(fixedYear: year)
                case .expensesYear(let year):
                    ExpenseListView(fixedYear: year)
                case .improvementsYear(let year):
                    HerstellungskostenListView(fixedYear: year)
                case .furnitureProperty(let property):
                    MoeblierungListView(property: property)
                case .furniturePropertyCoRented(let property):
                    MoeblierungListView(property: property, onlyCoRented: true)
                case .documentsUnit(let unit):
                    DocumentListView(unit: unit)
                case .documentsUtilityStatements:
                    DocumentListView(onlyUtilityStatements: true)
                }
                }
                // Zentral hier statt in den einzelnen Views deklariert: Property/Unit/UtilityStatement
                // werden von mehreren Views aus verlinkt (z.B. Dashboard → Immobilie → Einheit). Eine
                // zweite, tiefer im selben Stack liegende Deklaration desselben Typs ignoriert SwiftUI
                // stillschweigend („A navigationDestination … was declared earlier on the stack“),
                // wodurch der Link nicht mehr navigiert – deshalb genau eine Stelle pro Typ.
                .navigationDestination(for: Property.self) { property in
                    PropertyDetailView(property: property)
                }
                .navigationDestination(for: Unit.self) { unit in
                    UnitDetailView(unit: unit)
                }
                .navigationDestination(for: UtilityStatement.self) { statement in
                    UtilityStatementDetailView(statement: statement)
                }
            }
            .id(selection)
        }
        .tint(Theme.accent)
        .preferredColorScheme(appearanceStore.style.colorScheme)
        .id(appearanceStore.style)
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
