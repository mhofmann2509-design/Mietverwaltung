import XCTest
import SwiftData
@testable import Mietverwaltung

/// Speicher-Logik der Bearbeiten-Formulare (`FormSaving`), wie sie „Sichern“ ausführt.
final class FormSavingTests: ModelTestCase {
    // MARK: - Mietvertrag

    func testNewTenancyWithNewTenant() throws {
        let unit = makeUnit(makeProperty())
        var values = FormSaving.TenancyFormValues(tenant: .new(firstName: "Erika", lastName: "Muster"), startDate: date(2026, 1, 1))
        values.coldRentText = "1.250,50"
        values.utilityAdvanceText = "200"
        values.depositText = "3000"
        values.depositReturnedAt = date(2026, 6, 1)

        let tenancy = try XCTUnwrap(FormSaving.saveTenancy(values, existing: nil, unit: unit, context: context))
        try context.save()

        XCTAssertEqual(try count(Tenancy.self), 1)
        XCTAssertEqual(try count(Tenant.self), 1)
        XCTAssertEqual(tenancy.tenant?.lastName, "Muster")
        XCTAssertEqual(tenancy.unit, unit)
        XCTAssertEqual(tenancy.coldRent, 1_250.5, accuracy: 0.001)
        XCTAssertEqual(tenancy.totalMonthlyAmount, 1_450.5, accuracy: 0.001)
        XCTAssertNil(tenancy.depositReturnedAt, "ohne Mietende keine Kautionsrückzahlung")
    }

    func testTenancyWithoutTenantIsNotSaved() throws {
        let values = FormSaving.TenancyFormValues(tenant: nil, startDate: date(2026, 1, 1))
        XCTAssertNil(FormSaving.saveTenancy(values, existing: nil, unit: makeUnit(makeProperty()), context: context))
        XCTAssertEqual(try count(Tenancy.self), 0)
    }

    func testEditingReplacesRentStepsAndDropsThemForStandardContract() throws {
        let unit = makeUnit(makeProperty())
        let tenant = Tenant(firstName: "A", lastName: "B")
        context.insert(tenant)
        var values = FormSaving.TenancyFormValues(tenant: .existing(tenant), startDate: date(2025, 1, 1))
        values.coldRentText = "800"
        values.contractType = .staffel
        values.rentSteps = [(date(2026, 1, 1), "850"), (date(2027, 1, 1), "900")]
        let tenancy = try XCTUnwrap(FormSaving.saveTenancy(values, existing: nil, unit: unit, context: context))
        try context.save()
        XCTAssertEqual(try count(RentStep.self), 2)
        XCTAssertEqual(tenancy.coldRent(forMonthContaining: date(2026, 3, 1)), 850)

        values.rentSteps = [(date(2026, 7, 1), "880")]
        FormSaving.saveTenancy(values, existing: tenancy, unit: unit, context: context)
        try context.save()
        XCTAssertEqual(try count(RentStep.self), 1, "alte Stufen werden ersetzt, nicht ergänzt")
        XCTAssertEqual(try count(Tenancy.self), 1, "Bearbeiten legt keinen zweiten Vertrag an")

        values.contractType = .standard
        values.endDate = date(2027, 12, 31)
        values.depositReturnedAt = date(2028, 2, 1)
        FormSaving.saveTenancy(values, existing: tenancy, unit: unit, context: context)
        try context.save()
        XCTAssertEqual(try count(RentStep.self), 0)
        XCTAssertEqual(tenancy.depositReturnedAt, date(2028, 2, 1))
        XCTAssertEqual(tenancy.coldRent(forMonthContaining: date(2027, 3, 1)), 800)
    }

    // MARK: - Mietzahlung

    func testPaymentFullPartialAndUnpaid() throws {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2026, 1, 1))
        let month = date(2026, 4, 1)
        var values = FormSaving.PaymentFormValues(coldRentDueText: "1000", utilityAdvanceDueText: "150", isPaid: true, paidDate: date(2026, 4, 3))

        let payment = FormSaving.savePayment(values, tenancy: tenancy, month: month, context: context)
        XCTAssertEqual(payment.paidAmount ?? 0, 1_150, accuracy: 0.01, "leerer Betrag = voller Sollbetrag")

        values.paidAmountText = "500"
        FormSaving.savePayment(values, tenancy: tenancy, month: date(2026, 4, 20), context: context)
        XCTAssertEqual(try count(RentPayment.self), 1, "derselbe Monat wird aktualisiert")
        XCTAssertEqual(payment.paidAmount ?? 0, 500, accuracy: 0.01)
        // Der Rückstand rechnet mit dem Vertrags-Soll (1.000 €), nicht mit dem im Formular
        // abweichend erfassten Soll: Jan–März offen + 500 € Rest im April.
        XCTAssertEqual(tenancy.arrearsBalance(upTo: date(2026, 4, 30)), 3_000 + 500, accuracy: 0.01)

        values.isPaid = false
        FormSaving.savePayment(values, tenancy: tenancy, month: month, context: context)
        XCTAssertFalse(payment.isPaid)
        XCTAssertNil(payment.paidAmount)
    }

    // MARK: - Ausgabe

    func testExpenseVatOnlyForMaintenance() throws {
        let property = makeProperty()
        var values = FormSaving.ExpenseFormValues(title: "Heizung", amountText: "1.190,00", category: .maintenance, taxTreatment: .maintenanceExpense, property: property, vatRateText: "19")
        let expense = FormSaving.saveExpense(values, existing: nil, context: context)
        XCTAssertEqual(expense.amount, 1_190, accuracy: 0.001)
        XCTAssertEqual(expense.netAmount ?? 0, 1_000, accuracy: 0.01)
        XCTAssertEqual(property.totalExpenses(forYear: Calendar.current.component(.year, from: .now)), 1_190, accuracy: 0.01)

        values.taxTreatment = .capitalized
        FormSaving.saveExpense(values, existing: expense, context: context)
        XCTAssertNil(expense.vatRatePercent)
        XCTAssertEqual(try count(Expense.self), 1)
    }

    // MARK: - Kostenpositionen (Nebenkostenabrechnung / Wirtschaftsplan)

    func testPersistableLineItemsDropEmptyAndZeroRows() {
        let drafts = [
            LineItemDraft(costType: "  Müllabfuhr ", amountText: "320,40"),
            LineItemDraft(costType: "", amountText: "100"),
            LineItemDraft(costType: "Wasser", amountText: "0"),
            LineItemDraft(costType: "Strom", amountText: "abc"),
            LineItemDraft(costType: "Verwalter", amountText: "300", isApportionable: false, allocationKeyLabel: "MEA"),
        ]
        let items = LineItemDraft.persistable(drafts)
        XCTAssertEqual(items.map(\.costType), ["Müllabfuhr", "Verwalter"])
        XCTAssertEqual(items[0].amount, 320.4, accuracy: 0.001)
        XCTAssertFalse(items[1].isApportionable)
        XCTAssertEqual(items[1].allocationKeyLabel, "MEA")
        XCTAssertEqual(items[0].allocationKeyLabel, "")
    }
}
