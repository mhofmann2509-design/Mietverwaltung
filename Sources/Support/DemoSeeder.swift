import Foundation
import SwiftData

/// Befüllt eine frische, leere Datenbank einmalig mit Beispieldaten, die alle Funktionen der
/// App demonstrieren (Immobilie inkl. Finanzierung/Absender/Bankverbindung, zwei Einheiten mit
/// MEA-Anteil, Mieter mit Zahlungen, Ausgaben aller Kategorien, Möblierung/AfA, Nebenkostenabrechnung
/// nach Miteigentumsanteilen und ein Beispieldokument). Nur für Entwicklung/Vorschau gedacht.
@MainActor
enum DemoSeeder {
    static func seedIfNeeded(context: ModelContext) {
        let propertyCount = (try? context.fetchCount(FetchDescriptor<Property>())) ?? 0
        guard propertyCount == 0 else { return }

        let calendar = Calendar.current

        // MARK: Immobilie

        let property = Property(
            name: "Musterstraße 1", street: "Musterstraße 1", zipCode: "12345", city: "Berlin",
            notes: "Mehrfamilienhaus mit zwei Einheiten, Beispieldaten.",
            purchasePrice: 310_000, purchaseAncillaryCosts: 28_000,
            purchaseDate: calendar.date(byAdding: .year, value: -2, to: .now),
            landValue: 70_000, constructionYear: 1998
        )
        // Aufschlüsselung der Kaufnebenkosten (28.000 € Gesamtsumme, unverändert): Grunderwerbsteuer
        // zu 6 % (Berlin) + marktübliche Notar-/Grundbuch-/Maklerkosten, als realistisches
        // Demonstrationsbeispiel für die vollständige Einzelaufschlüsselung im Steuerreport.
        property.purchaseTransferTaxCosts = 18_600
        property.purchaseNotaryCosts = 4_650
        property.purchaseLandRegistryCosts = 1_550
        property.purchaseBrokerCosts = 3_200
        property.loanAmount = 220_000
        property.interestRatePercent = 3.5
        property.initialRepaymentRatePercent = 2.0
        property.loanStartDate = property.purchaseDate
        property.landlordName = "Max Mustermann"
        property.bankAccountHolder = "Max Mustermann"
        property.iban = "DE02 1203 0000 0012 3456 78"
        property.bic = "BYLADEM1001"
        context.insert(property)

        // MARK: Einheiten (mit Miteigentumsanteil für den Umlageschlüssel „Nach MEA“)

        let unit1 = Unit(name: "1. OG rechts", sizeSquareMeters: 68, rooms: 3, coOwnershipShare: 580)
        unit1.property = property
        unit1.features = [.balcony, .fittedKitchen, .cellar]
        context.insert(unit1)

        let unit2 = Unit(name: "2. OG links", sizeSquareMeters: 55, rooms: 2, coOwnershipShare: 420)
        unit2.property = property
        unit2.features = [.cellar, .washerConnection]
        context.insert(unit2)

        // MARK: Mieter & Mietverhältnisse

        let tenant1 = Tenant(firstName: "Erika", lastName: "Musterfrau", email: "erika@example.com", phone: "0151 23456789")
        context.insert(tenant1)

        let tenancy1 = Tenancy(
            startDate: calendar.date(byAdding: .month, value: -14, to: .now) ?? .now,
            coldRent: 850, utilityAdvance: 180, deposit: 2_550, depositReceived: true,
            occupantCount: 2
        )
        tenancy1.unit = unit1
        tenancy1.tenant = tenant1
        context.insert(tenancy1)

        let tenant2 = Tenant(firstName: "Thomas", lastName: "Beispiel", email: "thomas@example.com", phone: "0160 98765432")
        context.insert(tenant2)

        let tenancy2 = Tenancy(
            startDate: calendar.date(byAdding: .month, value: -8, to: .now) ?? .now,
            coldRent: 680, utilityAdvance: 140, deposit: 2_040, depositReceived: true,
            occupantCount: 1
        )
        tenancy2.unit = unit2
        tenancy2.tenant = tenant2
        context.insert(tenancy2)

        // MARK: Zahlungen – letzte 6 Monate, der aktuelle Monat jeweils noch offen

        for tenancy in [tenancy1, tenancy2] {
            for monthsAgo in stride(from: 5, through: 0, by: -1) {
                guard let due = calendar.date(byAdding: .month, value: -monthsAgo, to: calendar.startOfDay(for: .now)) else { continue }
                let payment = RentPayment(dueDate: due, coldRentDue: tenancy.coldRent, utilityAdvanceDue: tenancy.utilityAdvance)
                if monthsAgo > 0 {
                    payment.markPaid(date: due)
                }
                payment.tenancy = tenancy
                context.insert(payment)
            }
        }

        // MARK: Ausgaben (alle Kategorien/steuerlichen Behandlungen)

        let maintenance = Expense(date: calendar.date(byAdding: .month, value: -1, to: .now) ?? .now, amount: 240, category: .maintenance, title: "Heizung gewartet", taxTreatment: .maintenanceExpense)
        maintenance.property = property
        maintenance.unit = unit1
        context.insert(maintenance)

        let insurance = Expense(date: calendar.date(byAdding: .month, value: -3, to: .now) ?? .now, amount: 380, category: .insurance, title: "Hausversicherung", taxTreatment: .otherDeductible)
        insurance.property = property
        context.insert(insurance)

        let tax = Expense(date: calendar.date(byAdding: .month, value: -4, to: .now) ?? .now, amount: 310, category: .tax, title: "Grundsteuer", taxTreatment: .otherDeductible)
        tax.property = property
        context.insert(tax)

        let financing = Expense(date: calendar.date(byAdding: .month, value: -2, to: .now) ?? .now, amount: 40, category: .financing, title: "Kontoführungsgebühren", taxTreatment: .otherDeductible)
        financing.property = property
        context.insert(financing)

        let other = Expense(date: calendar.date(byAdding: .month, value: -5, to: .now) ?? .now, amount: 150, category: .other, title: "Steuerberater", taxTreatment: .otherDeductible)
        other.property = property
        context.insert(other)

        // MARK: Möblierung/AfA

        let kitchen = DepreciableAsset(name: "Einbauküche", category: .furniture, cost: 6_500, usefulLifeYears: 10, placedInServiceDate: calendar.date(byAdding: .year, value: -1, to: .now) ?? .now)
        kitchen.property = property
        kitchen.unit = unit1
        context.insert(kitchen)

        let washer = DepreciableAsset(name: "Waschmaschine", category: .furniture, cost: 650, usefulLifeYears: 10, placedInServiceDate: calendar.date(byAdding: .month, value: -6, to: .now) ?? .now)
        washer.property = property
        washer.unit = unit2
        context.insert(washer)

        let facade = DepreciableAsset(name: "Fassadendämmung", category: .improvement, cost: 18_000, usefulLifeYears: 50, placedInServiceDate: calendar.date(byAdding: .year, value: -1, to: .now) ?? .now, notes: "Modernisierung, über die Gebäude-Nutzungsdauer abzuschreiben.")
        facade.property = property
        context.insert(facade)

        // MARK: Nebenkostenabrechnung – Umlageschlüssel nach Miteigentumsanteilen (MEA)

        // Zeitraum deckungsgleich mit den oben erzeugten Zahlungen (letzte 6 Monate), damit die
        // geleisteten Vorauszahlungen in der Abrechnung tatsächlich auftauchen.
        let statementPeriodStart = calendar.date(byAdding: .month, value: -5, to: calendar.startOfDay(for: .now)) ?? .now
        let statement = UtilityStatement(
            year: calendar.component(.year, from: .now),
            propertyTaxAmount: 310,
            notes: "Von der Hausverwaltung erhalten.",
            allocationMethod: .coOwnershipShare
        )
        statement.periodStart = statementPeriodStart
        statement.periodEnd = .now
        statement.property = property
        context.insert(statement)

        let heating = UtilityCostLineItem(costType: "Heizung", amount: 1_450, isApportionable: true)
        heating.statement = statement
        context.insert(heating)
        let water = UtilityCostLineItem(costType: "Wasser/Abwasser", amount: 620, isApportionable: true)
        water.statement = statement
        context.insert(water)
        let caretaker = UtilityCostLineItem(costType: "Hausmeister", amount: 480, isApportionable: true)
        caretaker.statement = statement
        context.insert(caretaker)
        let management = UtilityCostLineItem(costType: "Verwaltergebühr", amount: 240, isApportionable: false)
        management.statement = statement
        context.insert(management)

        // MARK: Beispieldokument

        let noteText = "Beispiel-Dokument, erzeugt durch die Beispieldaten-Befüllung."
        let document = Document(
            title: "Hausordnung",
            fileName: "Hausordnung.txt",
            fileExtension: "txt",
            data: Data(noteText.utf8),
            receiptDate: .now
        )
        document.property = property
        context.insert(document)

        try? context.save()
    }

    /// Erweitert die Beispiel-Immobilie nachträglich auf 9 Einheiten / 8 Mieter, mit gezielt
    /// konstruierten Fällen für die in der Nebenkostenabrechnung geprüften Grenzfälle:
    /// Teilzahlung (Michael Berger), überschneidende Mietverhältnisse derselben Einheit (Laura
    /// Fischer / Jonas Keller), ein unterjährig beendetes Mietverhältnis mit Leerstand zum
    /// Abrechnungsstichtag (Paul Richter) und eine höhere Personenzahl (Hannah Schulz). Läuft
    /// unabhängig von `seedIfNeeded` und ergänzt eine bereits bestehende Datenbank, statt sie zu
    /// ersetzen – idempotent über die Einheiten-Anzahl der Immobilie.
    static func expandIfNeeded(context: ModelContext) {
        guard let property = (try? context.fetch(FetchDescriptor<Property>()))?.first else { return }
        guard (property.units ?? []).count < 9 else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func addOccupiedUnit(
            name: String, size: Double, rooms: Double, mea: Double,
            firstName: String, lastName: String, email: String, phone: String,
            coldRent: Double, utilityAdvance: Double, occupantCount: Int,
            startMonthsAgo: Int, endDate: Date? = nil,
            partialPaymentMonthsAgo: Int? = nil, partialPaymentAmount: Double? = nil,
            paymentMonthsAgo: ClosedRange<Int> = 0...5
        ) {
            let unit = Unit(name: name, sizeSquareMeters: size, rooms: rooms, coOwnershipShare: mea)
            unit.property = property
            context.insert(unit)

            let tenant = Tenant(firstName: firstName, lastName: lastName, email: email, phone: phone)
            context.insert(tenant)

            let tenancy = Tenancy(
                startDate: calendar.date(byAdding: .month, value: -startMonthsAgo, to: today) ?? today,
                endDate: endDate,
                coldRent: coldRent, utilityAdvance: utilityAdvance,
                deposit: coldRent * 3, depositReceived: true,
                occupantCount: occupantCount
            )
            tenancy.unit = unit
            tenancy.tenant = tenant
            context.insert(tenancy)

            for monthsAgo in stride(from: paymentMonthsAgo.upperBound, through: paymentMonthsAgo.lowerBound, by: -1) {
                guard let due = calendar.date(byAdding: .month, value: -monthsAgo, to: today) else { continue }
                if let endDate, due > endDate { continue }
                let payment = RentPayment(dueDate: due, coldRentDue: coldRent, utilityAdvanceDue: utilityAdvance)
                if monthsAgo > 0 || endDate != nil {
                    if monthsAgo == partialPaymentMonthsAgo, let partialPaymentAmount {
                        payment.markPaid(amount: partialPaymentAmount, date: due)
                    } else {
                        payment.markPaid(date: due)
                    }
                }
                payment.tenancy = tenancy
                context.insert(payment)
            }
        }

        // Einheit 3 – normal durchgehend vermietet, volle Zahlungen.
        addOccupiedUnit(
            name: "EG links", size: 50, rooms: 2, mea: 480,
            firstName: "Sabine", lastName: "Winter", email: "sabine.winter@example.com", phone: "0151 11122233",
            coldRent: 625, utilityAdvance: 130, occupantCount: 1,
            startMonthsAgo: 18
        )

        // Einheit 4 – ein Monat davon nur teilweise bezahlt (prüft die anteilige Vorauszahlungs-
        // Berechnung bei Teilzahlung statt „ganz oder gar nicht“).
        addOccupiedUnit(
            name: "EG rechts", size: 58, rooms: 3, mea: 560,
            firstName: "Michael", lastName: "Berger", email: "michael.berger@example.com", phone: "0151 22233344",
            coldRent: 725, utilityAdvance: 150, occupantCount: 2,
            startMonthsAgo: 20,
            partialPaymentMonthsAgo: 2, partialPaymentAmount: 500
        )

        // Einheit 5 – zwei Mietverhältnisse mit absichtlicher Überschneidung (Übergabe): Laura
        // zieht erst in 10 Tagen aus, Jonas ist bereits vor 5 Tagen eingezogen.
        let unit5 = Unit(name: "1. OG links", sizeSquareMeters: 56, rooms: 2, coOwnershipShare: 540)
        unit5.property = property
        context.insert(unit5)

        let laura = Tenant(firstName: "Laura", lastName: "Fischer", email: "laura.fischer@example.com", phone: "0151 33344455")
        context.insert(laura)
        let lauraTenancy = Tenancy(
            startDate: calendar.date(byAdding: .month, value: -20, to: today) ?? today,
            endDate: calendar.date(byAdding: .day, value: 10, to: today),
            coldRent: 680, utilityAdvance: 140, deposit: 2_040, depositReceived: true,
            occupantCount: 1
        )
        lauraTenancy.unit = unit5
        lauraTenancy.tenant = laura
        context.insert(lauraTenancy)

        let jonas = Tenant(firstName: "Jonas", lastName: "Keller", email: "jonas.keller@example.com", phone: "0151 44455566")
        context.insert(jonas)
        let jonasTenancy = Tenancy(
            startDate: calendar.date(byAdding: .day, value: -5, to: today) ?? today,
            coldRent: 720, utilityAdvance: 150, deposit: 2_160, depositReceived: false,
            occupantCount: 1
        )
        jonasTenancy.unit = unit5
        jonasTenancy.tenant = jonas
        context.insert(jonasTenancy)

        // Einheit 6 – Mietverhältnis vor 2 Monaten beendet (innerhalb des Abrechnungszeitraums),
        // Einheit aktuell leer: prüft die Stichtags-Schwäche beim Umlageschlüssel „Personenzahl“
        // (zum Abrechnungsende nicht mehr bewohnt, war aber über weite Teile des Zeitraums belegt)
        // sowie die „entgangene Miete“-Berechnung für Leerstand mit Vormieter.
        addOccupiedUnit(
            name: "2. OG rechts", size: 52, rooms: 2, mea: 450,
            firstName: "Paul", lastName: "Richter", email: "paul.richter@example.com", phone: "0151 55566677",
            coldRent: 650, utilityAdvance: 135, occupantCount: 2,
            startMonthsAgo: 14, endDate: calendar.date(byAdding: .month, value: -2, to: today),
            paymentMonthsAgo: 2...5
        )

        // Einheit 7 – höhere Personenzahl, für die Verteilung nach Personenzahl relevant.
        addOccupiedUnit(
            name: "3. OG links", size: 62, rooms: 4, mea: 600,
            firstName: "Hannah", lastName: "Schulz", email: "hannah.schulz@example.com", phone: "0151 66677788",
            coldRent: 775, utilityAdvance: 160, occupantCount: 4,
            startMonthsAgo: 12
        )

        // Einheit 8 – nie vermietet (Leerstand ohne Vormieter, andere „entgangene Miete“-Variante
        // als Einheit 6, die einen Vormieter hat).
        let unit8 = Unit(name: "3. OG rechts", sizeSquareMeters: 54, rooms: 2, coOwnershipShare: 480)
        unit8.property = property
        context.insert(unit8)

        // Einheit 9 – ebenfalls dauerhaft leer (kleine Dachgeschosswohnung).
        let unit9 = Unit(name: "Dachgeschoss", sizeSquareMeters: 40, rooms: 1, coOwnershipShare: 350)
        unit9.property = property
        context.insert(unit9)

        try? context.save()
    }

    /// Ergänzt Anrede, frühere Anschrift und Kontodaten bei den Beispiel-Mietern, sofern dort noch
    /// nichts hinterlegt ist – unabhängig von `seedIfNeeded`/`expandIfNeeded`, damit das auch für
    /// eine bereits bestehende Datenbank nachgeholt wird, ohne vorhandene Eingaben zu überschreiben.
    static func enrichTenantContactDataIfNeeded(context: ModelContext) {
        guard let tenants = try? context.fetch(FetchDescriptor<Tenant>()) else { return }

        struct ContactInfo {
            let salutation: Salutation
            let previousAddress: String
            let bankAccountHolder: String
            let iban: String
            let bic: String
        }

        let contactInfoByName: [String: ContactInfo] = [
            "Erika Musterfrau": ContactInfo(salutation: .female, previousAddress: "Alte Gasse 12, 10115 Berlin", bankAccountHolder: "Erika Musterfrau", iban: "DE12 5001 0517 0648 4898 90", bic: "INGDDEFFXXX"),
            "Thomas Beispiel": ContactInfo(salutation: .male, previousAddress: "Ringstraße 7, 80331 München", bankAccountHolder: "Thomas Beispiel", iban: "DE27 1007 7777 0209 2994 00", bic: "COBADEFFXXX"),
            "Sabine Winter": ContactInfo(salutation: .female, previousAddress: "Berger Straße 4, 60316 Frankfurt am Main", bankAccountHolder: "Sabine Winter", iban: "DE55 5004 0000 0312 1300 00", bic: "COBADEFFXXX"),
            "Michael Berger": ContactInfo(salutation: .male, previousAddress: "Schillerstraße 20, 70173 Stuttgart", bankAccountHolder: "Michael Berger", iban: "DE89 6005 0101 0001 2345 67", bic: "SOLADEST600"),
            "Laura Fischer": ContactInfo(salutation: .female, previousAddress: "Gartenweg 9, 04109 Leipzig", bankAccountHolder: "Laura Fischer", iban: "DE44 8605 5592 0290 1890 90", bic: "WELADE8LXXX"),
            "Jonas Keller": ContactInfo(salutation: .male, previousAddress: "Bahnhofsallee 3, 40212 Düsseldorf", bankAccountHolder: "Jonas Keller", iban: "DE21 3005 0000 0001 2345 00", bic: "DUSSDEDDXXX"),
            "Paul Richter": ContactInfo(salutation: .male, previousAddress: "Hafenstraße 15, 20359 Hamburg", bankAccountHolder: "Paul Richter", iban: "DE09 2005 0550 1234 5678 90", bic: "HASPDEHHXXX"),
            "Hannah Schulz": ContactInfo(salutation: .female, previousAddress: "Lindenallee 22, 50667 Köln", bankAccountHolder: "Hannah Schulz", iban: "DE76 3705 0198 0012 3456 78", bic: "COLSDE33XXX"),
        ]

        for tenant in tenants {
            guard let info = contactInfoByName["\(tenant.firstName) \(tenant.lastName)"] else { continue }
            guard tenant.salutation == .unspecified, tenant.previousAddress.isEmpty, tenant.iban.isEmpty else { continue }
            tenant.salutation = info.salutation
            tenant.previousAddress = info.previousAddress
            tenant.bankAccountHolder = info.bankAccountHolder
            tenant.iban = info.iban
            tenant.bic = info.bic
        }

        try? context.save()
    }
}
