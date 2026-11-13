import XCTest
import SwiftData
@testable import Mietverwaltung

/// WEG-Modul (Version 2): Hausgeld-Vorschlag aus dem Wirtschaftsplan, Hausgeldkonto,
/// Abrechnungsspitze, Sonderumlagen mit Ausgabenbuchung, Fristen und Lösch-Regeln.
final class WEGHausgeldTests: ModelTestCase {
    private var property: Property!
    private var unitA: Mietverwaltung.Unit!
    private var unitB: Mietverwaltung.Unit!

    override func setUpWithError() throws {
        try super.setUpWithError()
        property = makeProperty("WEG-Haus")
        unitA = makeUnit(property, "WE 1", size: 70)
        unitA.coOwnershipShare = 120
        unitB = makeUnit(property, "WE 2", size: 50)
        unitB.coOwnershipShare = 80
    }

    private func wirtschaftsplan(year: Int = 2026) -> WirtschaftsplanStatement {
        let plan = WirtschaftsplanStatement(year: year, propertyTaxAmount: 500)
        plan.property = property
        context.insert(plan)
        for (type, amount, apportionable) in [("Hausmeister", 1_200.0, true), ("Verwaltervergütung", 600.0, false), ("Zuführung Erhaltungsrücklage", 1_800.0, false)] {
            let item = WirtschaftsplanLineItem(costType: type, amount: amount, isApportionable: apportionable)
            item.statement = plan
            context.insert(item)
        }
        return plan
    }

    @discardableResult
    private func hausgeld(_ unit: Mietverwaltung.Unit, from start: Date, monthly: Double) -> HausgeldPlan {
        let plan = HausgeldPlan(validFrom: start, monthlyAmount: monthly)
        plan.unit = unit
        context.insert(plan)
        return plan
    }

    // MARK: - Vorschlag aus dem Wirtschaftsplan

    func testProposalUsesCoOwnershipShareAndSplitsReserveFund() {
        let proposal = HausgeldCalculator.proposal(from: wirtschaftsplan(), for: unitA)
        XCTAssertEqual(proposal.unitShare, 0.6, accuracy: 0.0001)
        XCTAssertEqual(proposal.shareBasis, "MEA")
        XCTAssertEqual(proposal.monthlyAmount, 180, accuracy: 0.001, "3.600 € × 60 % ÷ 12, ohne Grundsteuer")
        XCTAssertEqual(proposal.apportionableMonthly, 60, accuracy: 0.001)
        XCTAssertEqual(proposal.reserveFundMonthly, 90, accuracy: 0.001)

        let other = HausgeldCalculator.proposal(from: wirtschaftsplan(), for: unitB)
        XCTAssertEqual(proposal.monthlyAmount + other.monthlyAmount, 300, accuracy: 0.001, "beide Einheiten zusammen = Wirtschaftsplan")
    }

    func testShareFallsBackToAreaThenEqualParts() {
        unitA.coOwnershipShare = 0
        XCTAssertEqual(HausgeldCalculator.share(of: unitA).value, 70.0 / 120, accuracy: 0.0001)
        XCTAssertEqual(HausgeldCalculator.share(of: unitA).basis, "Wohnfläche")
        unitA.sizeSquareMeters = 0
        XCTAssertEqual(HausgeldCalculator.share(of: unitA).value, 0.5, accuracy: 0.0001)
        XCTAssertEqual(HausgeldCalculator.share(of: unitA).basis, "gleiche Teile")
    }

    func testSavingProposalTracksManualAdjustment() {
        let proposal = HausgeldCalculator.proposal(from: wirtschaftsplan(), for: unitA)
        let unchanged = HausgeldPlanSaving.save(unit: unitA, existing: nil, proposal: proposal, sourceYear: 2026, validFrom: date(2026, 1, 1), monthly: 180, apportionable: 60, reserve: 90, notes: "", context: context)
        XCTAssertEqual(unchanged.sourcePlanYear, 2026)
        XCTAssertFalse(unchanged.isManuallyAdjusted)

        let adjusted = HausgeldPlanSaving.save(unit: unitB, existing: nil, proposal: proposal, sourceYear: 2026, validFrom: date(2026, 1, 1), monthly: 125, apportionable: 40, reserve: 60, notes: "lt. Einzelwirtschaftsplan", context: context)
        XCTAssertTrue(adjusted.isManuallyAdjusted)

        HausgeldPlanSaving.save(unit: unitA, existing: unchanged, proposal: nil, sourceYear: 2026, validFrom: date(2026, 1, 1), monthly: 185, apportionable: 60, reserve: 90, notes: "", context: context)
        XCTAssertTrue(unchanged.isManuallyAdjusted, "spätere Änderung am übernommenen Plan")
        XCTAssertEqual(unchanged.nonApportionableMonthly, 35, accuracy: 0.001)

        let manual = HausgeldPlanSaving.save(unit: unitA, existing: nil, proposal: nil, sourceYear: nil, validFrom: date(2027, 1, 1), monthly: 200, apportionable: 0, reserve: 0, notes: "", context: context)
        XCTAssertNil(manual.sourcePlanYear)
        XCTAssertFalse(manual.isManuallyAdjusted)
    }

    // MARK: - Hausgeldkonto

    func testValidPlanAndMonthlyDue() {
        hausgeld(unitA, from: date(2025, 1, 1), monthly: 170)
        hausgeld(unitA, from: date(2026, 3, 15), monthly: 190)
        XCTAssertEqual(HausgeldCalculator.plan(for: unitA, on: date(2026, 3, 14))?.monthlyAmount, 170)
        XCTAssertEqual(HausgeldCalculator.plan(for: unitA, on: date(2026, 3, 15))?.monthlyAmount, 190)
        XCTAssertEqual(HausgeldCalculator.monthlyDue(for: unitA, inMonthOf: date(2026, 3, 1)), 190, "Plan ab Monatsmitte gilt für den Monat")
        XCTAssertEqual(HausgeldCalculator.monthlyDue(for: unitA, inMonthOf: date(2024, 12, 1)), 0, "vor dem ersten Plan kein Soll")
    }

    func testAccountWithPartialPaymentAndMarkPaid() throws {
        hausgeld(unitA, from: date(2026, 1, 1), monthly: 300)
        HausgeldCalculator.markPaid(unit: unitA, month: date(2026, 1, 1), on: date(2026, 1, 3), context: context)
        HausgeldCalculator.markPaid(unit: unitA, month: date(2026, 2, 10), on: date(2026, 2, 3), context: context)
        HausgeldCalculator.markPaid(unit: unitA, month: date(2026, 3, 1), on: date(2026, 3, 3), amount: 100, context: context)
        HausgeldCalculator.markPaid(unit: unitA, month: date(2026, 3, 1), on: date(2026, 3, 20), amount: 300, context: context)
        XCTAssertEqual(try count(HausgeldPayment.self), 3, "kein doppelter Eintrag je Monat")

        let march = HausgeldCalculator.account(for: unitA, year: 2026, upTo: date(2026, 4, 30))
        XCTAssertEqual(march.due, 1_200, accuracy: 0.01)
        XCTAssertEqual(march.paid, 900, accuracy: 0.01)
        XCTAssertEqual(march.openMonths, 1, "April offen")
        XCTAssertEqual(march.balance, 300, accuracy: 0.01)

        let payment = try XCTUnwrap(HausgeldCalculator.payment(for: unitA, inMonthOf: date(2026, 1, 1)))
        XCTAssertEqual(payment.amountDue, 300)
        payment.markUnpaid()
        XCTAssertEqual(HausgeldCalculator.account(for: unitA, year: 2026, upTo: date(2026, 4, 30)).paid, 600, accuracy: 0.01)
    }

    func testRecordedDueStaysWhenPlanChangesLater() {
        let plan = hausgeld(unitA, from: date(2026, 1, 1), monthly: 300)
        HausgeldCalculator.markPaid(unit: unitA, month: date(2026, 1, 1), context: context)
        plan.monthlyAmount = 350
        let account = HausgeldCalculator.account(for: unitA, year: 2026, upTo: date(2026, 2, 28))
        XCTAssertEqual(account.due, 300 + 350, accuracy: 0.01, "erfasster Monat behält sein Soll")
    }

    func testSettlementAgainstAnnualStatement() {
        hausgeld(unitA, from: date(2025, 1, 1), monthly: 180)
        for month in 1...12 { HausgeldCalculator.markPaid(unit: unitA, month: date(2025, month, 1), context: context) }
        let statement = UtilityStatement(propertyTaxAmount: 500)
        statement.periodStart = date(2025, 1, 1)
        statement.periodEnd = date(2025, 12, 31)
        statement.property = property
        context.insert(statement)
        let line = UtilityCostLineItem(costType: "Gesamtkosten", amount: 4_000)
        line.statement = statement
        context.insert(line)

        let settlement = HausgeldCalculator.settlement(for: unitA, statement: statement)
        XCTAssertEqual(settlement.actualCosts, 2_400, accuracy: 0.01, "4.000 € × 60 %, ohne Grundsteuer")
        XCTAssertEqual(settlement.advancesPaid, 2_160, accuracy: 0.01)
        XCTAssertEqual(settlement.balance, 240, accuracy: 0.01, "Nachzahlung")
    }

    /// Hausgeld wird steuerlich nicht zusätzlich angesetzt – sonst doppelt mit der Jahresabrechnung.
    func testHausgeldDoesNotChangeTaxOrCashflow() {
        let before = (property.werbungskosten(forYear: 2026), property.freeCashFlow(forYear: 2026))
        hausgeld(unitA, from: date(2026, 1, 1), monthly: 300)
        HausgeldCalculator.markPaid(unit: unitA, month: date(2026, 1, 1), context: context)
        XCTAssertEqual(property.werbungskosten(forYear: 2026), before.0, accuracy: 0.01)
        XCTAssertEqual(property.freeCashFlow(forYear: 2026), before.1, accuracy: 0.01)
    }

    // MARK: - Sonderumlagen

    func testPaidLevyBooksExpenseWithChosenTreatment() throws {
        let levy = SpecialLevy(title: "Dach", amount: 5_000, dueDate: date(2026, 4, 1), taxTreatment: .maintenanceExpense)
        levy.property = property
        levy.unit = unitA
        context.insert(levy)
        levy.syncExpense(context: context)
        XCTAssertNil(levy.expense, "unbezahlt keine Ausgabe")

        levy.paidDate = date(2026, 4, 2)
        levy.deductibleAmountOverride = 4_200
        levy.syncExpense(context: context)
        let expense = try XCTUnwrap(levy.expense)
        XCTAssertEqual(expense.amount, 4_200, "steuerlicher Betrag laut Abrechnung")
        XCTAssertEqual(expense.taxTreatment, .maintenanceExpense)
        XCTAssertEqual(expense.date, date(2026, 4, 2))
        XCTAssertEqual(expense.unit, unitA)
        XCTAssertEqual(property.maintenanceExpenses(forYear: 2026), 4_200, accuracy: 0.01)

        levy.taxTreatment = .capitalized
        levy.deductibleAmountOverride = nil
        levy.syncExpense(context: context)
        XCTAssertEqual(try count(Expense.self), 1, "dieselbe Ausgabe wird aktualisiert")
        XCTAssertEqual(property.capitalizedExpenses(forYear: 2026), 5_000, accuracy: 0.01)
        XCTAssertEqual(property.maintenanceExpenses(forYear: 2026), 0)

        levy.paidDate = nil
        levy.syncExpense(context: context)
        try context.save()
        XCTAssertEqual(try count(Expense.self), 0, "zurück auf offen entfernt die Buchung")
    }

    func testDeletingLevyRemovesBookedExpenseAndMeetingKeepsLevy() throws {
        let meeting = OwnersMeetingEvent(date: date(2026, 2, 1))
        meeting.property = property
        context.insert(meeting)
        let levy = SpecialLevy(title: "Fassade", amount: 3_000)
        levy.property = property
        levy.ownersMeeting = meeting
        levy.paidDate = date(2026, 3, 1)
        context.insert(levy)
        levy.syncExpense(context: context)
        try context.save()

        context.delete(meeting)
        try context.save()
        XCTAssertNil(levy.ownersMeeting)
        XCTAssertEqual(try count(SpecialLevy.self), 1)

        context.delete(levy)
        try context.save()
        XCTAssertEqual(try count(Expense.self), 0)
    }

    func testDeletingUnitRemovesHausgeldButKeepsPropertyLevy() throws {
        hausgeld(unitA, from: date(2026, 1, 1), monthly: 300)
        HausgeldCalculator.markPaid(unit: unitA, month: date(2026, 1, 1), context: context)
        let levy = SpecialLevy(title: "Aufzug", amount: 1_000)
        levy.property = property
        levy.unit = unitA
        context.insert(levy)
        try context.save()

        context.delete(unitA)
        try context.save()
        XCTAssertEqual(try count(HausgeldPlan.self), 0)
        XCTAssertEqual(try count(HausgeldPayment.self), 0)
        XCTAssertEqual(try count(SpecialLevy.self), 1)
        XCTAssertNil(levy.unit)
    }

    // MARK: - Fristen

    func testRemindersForLeviesAndOpenHausgeld() {
        let now = date(2026, 5, 13)
        let overdue = SpecialLevy(title: "Dach", amount: 2_000, dueDate: date(2026, 5, 1))
        let soon = SpecialLevy(title: "Heizung", amount: 800, dueDate: date(2026, 5, 23))
        let later = SpecialLevy(title: "Fenster", amount: 900, dueDate: date(2026, 9, 1))
        let paid = SpecialLevy(title: "Aufzug", amount: 500, dueDate: date(2026, 5, 1))
        paid.paidDate = date(2026, 4, 30)
        for levy in [overdue, soon, later, paid] { levy.property = property; context.insert(levy) }
        hausgeld(unitA, from: date(2026, 1, 1), monthly: 300)
        for month in 1...3 { HausgeldCalculator.markPaid(unit: unitA, month: date(2026, month, 1), context: context) }

        let items = RemindersEngine.reminders(properties: [property], tenancies: [], landlord: nil, now: now)
        let levyItems = items.filter { $0.id.hasPrefix("special-levy") }
        XCTAssertEqual(levyItems.count, 2)
        XCTAssertEqual(levyItems.first { $0.title == "Sonderumlage überfällig" }?.severity, .overdue)
        XCTAssertEqual(levyItems.first { $0.title == "Sonderumlage fällig" }?.severity, .info)

        let hausgeldItem = items.first { $0.id.hasPrefix("hausgeld-open") }
        XCTAssertNotNil(hausgeldItem, "April offen")
        XCTAssertTrue(hausgeldItem?.subtitle.contains("1 Monat") == true)
    }
}
