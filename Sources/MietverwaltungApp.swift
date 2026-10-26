import SwiftUI
import SwiftData

@main
struct MietverwaltungApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Property.self,
            Unit.self,
            Tenant.self,
            Tenancy.self,
            RentPayment.self,
            Expense.self,
            Document.self,
            DepreciableAsset.self,
            UtilityStatement.self,
            UtilityCostLineItem.self,
            Landlord.self,
            RemainingUsefulLifeAppraisal.self,
            WirtschaftsplanStatement.self,
            WirtschaftsplanLineItem.self,
            TrackedYear.self,
            TaxChecklistItem.self,
            ThreeYearThresholdCase.self,
            ThresholdExpenseAssessment.self,
            TravelExpense.self,
            HomeOfficeEntry.self
        ])

        // Lokale Speicherung auf dem jeweiligen Gerät.
        // Hinweis: Siehe README.md, Abschnitt "iCloud-Sync aktivieren (optional)",
        // um die Daten automatisch zwischen Mac und iPhone zu synchronisieren.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("ModelContainer konnte nicht erstellt werden: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                .task {
                    DemoSeeder.seedIfNeeded(context: sharedModelContainer.mainContext)
                    DemoSeeder.expandIfNeeded(context: sharedModelContainer.mainContext)
                    DemoSeeder.enrichTenantContactDataIfNeeded(context: sharedModelContainer.mainContext)
                }
                #endif
        }
        .modelContainer(sharedModelContainer)
    }
}
