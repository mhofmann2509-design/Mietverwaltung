import XCTest
import SwiftData
import CoreData
@testable import Mietverwaltung

/// Datenbank-Versionierung: `Fixtures/MietverwaltungV1.store` wurde mit dem Datenmodell vor der
/// Versionierung erzeugt (erfundene Beispieldaten, ein Datensatz je Modell). Die Tests stellen
/// sicher, dass bestehende Datenbanken erkannt und ohne Datenverlust migriert werden.
@MainActor
final class MigrationTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Kopie der V1-Beispieldatenbank – das Original im Repository bleibt unverändert.
    private func copyOfV1Fixture() throws -> URL {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/MietverwaltungV1.store")
        let target = workDirectory.appendingPathComponent("Mietverwaltung.store")
        try FileManager.default.copyItem(at: fixture, to: target)
        return target
    }

    private func storeHashes(at url: URL) throws -> [String: Data] {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        return try XCTUnwrap(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
    }

    /// Die eingefrorene Version 1 muss Feld für Feld dem Modell entsprechen, mit dem bestehende
    /// Datenbanken angelegt wurden – sonst würde SwiftData sie nicht als Version 1 erkennen.
    func testFrozenSchemaV1MatchesExistingDatabases() throws {
        let stored = try storeHashes(at: copyOfV1Fixture())
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV1.models))
        XCTAssertEqual(Set(model.entityVersionHashesByName.keys), Set(stored.keys))
        for (entity, hash) in model.entityVersionHashesByName {
            XCTAssertEqual(hash, stored[entity], "Abweichung bei \(entity)")
        }
    }

    func testVersionsAreOrderedAndDistinct() {
        let versions = MietverwaltungMigrationPlan.schemas.map { $0.versionIdentifier }
        XCTAssertEqual(versions, versions.sorted())
        XCTAssertEqual(Set(versions.map { "\($0)" }).count, versions.count)
        XCTAssertTrue(MietverwaltungMigrationPlan.schemas.last == SchemaLatest.self)
    }

    /// Eine Version-1-Datenbank wird auf die aktuelle Version migriert, alle Daten und
    /// Verknüpfungen bleiben erhalten.
    func testV1DatabaseMigratesWithoutDataLoss() throws {
        let url = try copyOfV1Fixture()
        let schema = Schema(versionedSchema: SchemaLatest.self)
        let container = try ModelContainer(for: schema, migrationPlan: MietverwaltungMigrationPlan.self, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = container.mainContext

        for type in SchemaV1.models {
            XCTAssertGreaterThan(try count(type, in: context), 0, "\(type) leer nach Migration")
        }

        let property = try XCTUnwrap(context.fetch(FetchDescriptor<Property>()).first)
        XCTAssertEqual(property.name, "Fixture-Haus")
        XCTAssertEqual(property.purchasePrice, 400_000)
        XCTAssertEqual(property.units?.count, 2)
        XCTAssertEqual(property.wirtschaftsplaene?.first?.lineItems?.count, 3)

        let tenancy = try XCTUnwrap(context.fetch(FetchDescriptor<Tenancy>()).first)
        XCTAssertEqual(tenancy.tenant?.lastName, "Fixture")
        XCTAssertEqual(tenancy.contractType, .staffel)
        XCTAssertEqual(tenancy.rentSteps?.first?.coldRent, 950)
        XCTAssertEqual(tenancy.payments?.first?.isPaid, true)
        XCTAssertEqual(tenancy.documents?.first?.data.count, 2_048, "Dokumentinhalt erhalten")

        let decision = try XCTUnwrap(context.fetch(FetchDescriptor<CapitalizationDecision>()).first)
        XCTAssertEqual(decision.resultingAsset?.name, "Küche")
        XCTAssertEqual(decision.thresholdCase?.assessments?.first?.expense?.amount, 1_190)

        // Neue Felder der aktuellen Version starten leer.
        XCTAssertTrue((property.units ?? []).allSatisfy { ($0.hausgeldPlans ?? []).isEmpty })
        XCTAssertTrue((property.specialLevies ?? []).isEmpty)

        // Nach der Migration ist die Datenbank normal beschreib- und wieder lesbar.
        let unit = try XCTUnwrap(property.units?.first)
        let plan = HausgeldPlan(validFrom: .now, monthlyAmount: 300)
        plan.unit = unit
        context.insert(plan)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HausgeldPlan>()), 1)
    }

    /// Eine bereits migrierte Datenbank wird beim nächsten Start ohne erneute Migration geöffnet.
    func testMigratedDatabaseReopens() throws {
        let url = try copyOfV1Fixture()
        let schema = Schema(versionedSchema: SchemaLatest.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        do {
            let first = try ModelContainer(for: schema, migrationPlan: MietverwaltungMigrationPlan.self, configurations: [configuration])
            try first.mainContext.save()
        }
        let second = try ModelContainer(for: schema, migrationPlan: MietverwaltungMigrationPlan.self, configurations: [configuration])
        XCTAssertEqual(try second.mainContext.fetchCount(FetchDescriptor<Property>()), 1)
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: SchemaLatest.models))
        XCTAssertEqual(try storeHashes(at: url), model.entityVersionHashesByName, "Datenbank steht auf der aktuellen Version")
    }

    /// Datenbank eines unbekannten, älteren Modellstands: Der Migrationsplan kennt ihn nicht, die
    /// App öffnet sie trotzdem per automatischer Migration und behält die Daten.
    func testUnknownOlderDatabaseFallsBackToAutomaticMigration() throws {
        let url = workDirectory.appendingPathComponent("Aelter.store")
        do {
            let olderSchema = Schema([SchemaV1.Landlord.self])
            let older = try ModelContainer(for: olderSchema, configurations: [ModelConfiguration(schema: olderSchema, url: url, cloudKitDatabase: .none)])
            let landlord = SchemaV1.Landlord()
            landlord.name = "Alt-Vermieter"
            older.mainContext.insert(landlord)
            try older.mainContext.save()
        }
        let configuration = ModelConfiguration(schema: AppSchema.schema, url: url, cloudKitDatabase: .none)
        let container = try AppSchema.makeContainer(configuration: configuration)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Landlord>()).first?.name, "Alt-Vermieter")
        container.mainContext.insert(Property(name: "Neu"))
        try container.mainContext.save()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Property>()), 1)
    }

    func testAppContainerOpensV1Database() throws {
        let url = try copyOfV1Fixture()
        let container = try AppSchema.makeContainer(configuration: ModelConfiguration(schema: AppSchema.schema, url: url, cloudKitDatabase: .none))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Tenancy>()), 1)
    }

    private func count(_ type: any PersistentModel.Type, in context: ModelContext) throws -> Int {
        func typed<T: PersistentModel>(_: T.Type) throws -> Int { try context.fetchCount(FetchDescriptor<T>()) }
        return try typed(type)
    }
}
