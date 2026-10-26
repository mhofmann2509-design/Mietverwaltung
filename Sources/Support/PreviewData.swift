import Foundation
import SwiftData

/// An in-memory model container pre-filled with sample data, used only by SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema([
            Property.self, Unit.self, Tenant.self, Tenancy.self, RentPayment.self, Expense.self, Document.self,
            DepreciableAsset.self, UtilityStatement.self, UtilityCostLineItem.self, Landlord.self,
            RemainingUsefulLifeAppraisal.self, WirtschaftsplanStatement.self, WirtschaftsplanLineItem.self,
            TrackedYear.self, TaxChecklistItem.self, ThreeYearThresholdCase.self, ThresholdExpenseAssessment.self,
            TravelExpense.self, HomeOfficeEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let property = Property(
            name: "Musterstraße 1", street: "Musterstraße 1", zipCode: "12345", city: "Berlin",
            purchasePrice: 310_000, purchaseAncillaryCosts: 28_000,
            purchaseDate: Calendar.current.date(byAdding: .year, value: -2, to: .now),
            landValue: 70_000, constructionYear: 1998
        )
        property.loanAmount = 220_000
        property.interestRatePercent = 3.5
        property.initialRepaymentRatePercent = 2.0
        property.loanStartDate = property.purchaseDate
        context.insert(property)

        let unit = Unit(name: "1. OG rechts", sizeSquareMeters: 68, rooms: 3)
        unit.property = property
        unit.features = [.balcony, .fittedKitchen, .cellar]
        context.insert(unit)

        let tenant = Tenant(firstName: "Erika", lastName: "Musterfrau", email: "erika@example.com", phone: "0151 23456789")
        context.insert(tenant)

        let tenancy = Tenancy(startDate: Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now, coldRent: 850, utilityAdvance: 180, deposit: 2550, depositReceived: true)
        tenancy.unit = unit
        tenancy.tenant = tenant
        context.insert(tenancy)

        let expense = Expense(date: .now, amount: 240, category: .maintenance, title: "Heizung gewartet", taxTreatment: .maintenanceExpense)
        expense.property = property
        expense.unit = unit
        context.insert(expense)

        let insurance = Expense(date: Calendar.current.date(byAdding: .month, value: -2, to: .now) ?? .now, amount: 380, category: .insurance, title: "Hausversicherung", taxTreatment: .otherDeductible)
        insurance.property = property
        context.insert(insurance)

        // Möblierung der Einheit (Küche), mit eigener AfA.
        let kitchen = DepreciableAsset(name: "Einbauküche", category: .furniture, cost: 6_500, usefulLifeYears: 10, placedInServiceDate: Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now)
        kitchen.property = property
        kitchen.unit = unit
        context.insert(kitchen)

        let statement = UtilityStatement(year: Calendar.current.component(.year, from: .now) - 1, propertyTaxAmount: 310, notes: "Von der Hausverwaltung erhalten")
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

        let landlord = Landlord(name: "Max Mustermann", street: "Beispielweg 3", zipCode: "10115", city: "Berlin", bankAccountHolder: "Max Mustermann", iban: "DE02 1203 0000 0012 3456 78", bic: "BYLADEM1001", marginalTaxRatePercent: 42)
        context.insert(landlord)

        return container
    }()
}
