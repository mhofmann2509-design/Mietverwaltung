import SwiftUI
import SwiftData

@main
struct MietverwaltungApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = AppSchema.schema

        // Synchronisiert automatisch über die private iCloud-Datenbank des angemeldeten
        // Apple-Accounts (Container "iCloud.com.marcelhofmann.mietverwaltung", siehe
        // Mietverwaltung-{iOS,macOS}.entitlements) – Mac und iPhone sehen so denselben
        // Datenbestand, wenn auf beiden dieselbe Apple-ID angemeldet ist. Siehe README.md,
        // Abschnitt "iCloud-Sync (CloudKit)", für den dafür nötigen einmaligen Xcode-Schritt
        // (Team in Signing & Capabilities auswählen) sowie zum Zurückschalten auf rein lokale
        // Speicherung ohne Sync.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("ModelContainer konnte nicht erstellt werden: \(error)")
        }
    }()

    init() {
        ExportFileStore.purge()
        ExportFileStore.purgeLegacyExports()
    }

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
