import SwiftData

/// Aktuelle Version des Datenmodells (siehe `MietverwaltungMigrationPlan`).
typealias SchemaLatest = SchemaV2

/// Version 2.0.0: WEG-Hausgeld (`HausgeldPlan`, `HausgeldPayment`) und Sonderumlagen
/// (`SpecialLevy`) – rein ergänzend, damit iCloud-kompatibel. Nutzt die aktuellen Modellklassen.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Property.self, Unit.self, Tenant.self, Tenancy.self, RentStep.self, RentPayment.self,
            Expense.self, Document.self, DocumentFolder.self, DepreciableAsset.self,
            UtilityStatement.self, UtilityCostLineItem.self, UtilityStatementDispatch.self,
            Landlord.self, RemainingUsefulLifeAppraisal.self,
            WirtschaftsplanStatement.self, WirtschaftsplanLineItem.self,
            TrackedYear.self, TaxChecklistItem.self, TaxFilingStatus.self,
            ThreeYearThresholdCase.self, ThresholdExpenseAssessment.self, CapitalizationDecision.self,
            TravelExpense.self, HomeOfficeEntry.self, OwnersMeetingEvent.self,
            HausgeldPlan.self, HausgeldPayment.self, SpecialLevy.self,
        ]
    }
}

/// Migrationsweg aller Datenbankversionen. Regel wegen iCloud: nur ergänzende Änderungen (neue
/// Modelle, neue Felder mit Standardwert/optional) – keine Umbenennungen oder Löschungen.
/// Jede neue Version: vorige Version als `SchemaVn` einfrieren, Stufe ergänzen, `MigrationTests`
/// erweitern.
enum MietverwaltungMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

/// Die einzige Liste aller persistierten Modelltypen – von App, Previews und Tests gemeinsam
/// genutzt, damit ein neuer `@Model`-Typ nicht an einer von mehreren Kopien vergessen wird.
enum AppSchema {
    static let schema = Schema(versionedSchema: SchemaLatest.self)

    /// Öffnet die Datenbank über den Migrationsplan. Stammt sie von einem Modellstand, der keiner
    /// eingefrorenen Version entspricht (z.B. ein Gerät, auf dem die App seit vor Version 1 nicht
    /// mehr lief), meldet SwiftData `unknownDataStoreSchema` – dann wird sie wie vor der
    /// Versionierung mit der automatischen, rein ergänzenden Migration geöffnet, statt abzustürzen.
    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        do {
            return try ModelContainer(for: schema, migrationPlan: MietverwaltungMigrationPlan.self, configurations: [configuration])
        } catch {
            let unversioned = Schema(SchemaLatest.models)
            return try ModelContainer(for: unversioned, configurations: [configuration])
        }
    }
}
