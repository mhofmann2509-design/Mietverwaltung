import XCTest
import SwiftData
@testable import Mietverwaltung

/// Dashboard-Kennzahlen (`DashboardMetrics`), Zahlungsübersicht (`RentLedger`) und Tilgungsplan –
/// früher als `private` in den Views verbaut und deshalb ungetestet.
final class DashboardMetricsTests: ModelTestCase {
    private func metrics(_ property: Property, period: DashboardPeriod = .month, now: Date) -> DashboardMetrics {
        DashboardMetrics(
            properties: [property],
            units: property.units ?? [],
            tenancies: (property.units ?? []).flatMap { $0.tenancies ?? [] },
            expenses: try! context.fetch(FetchDescriptor<Expense>()),
            range: period.range(containing: now),
            now: now
        )
    }

    func testPeriodRanges() {
        let now = date(2026, 11, 13, hour: 15)
        XCTAssertTrue(DashboardPeriod.month.range(containing: now) == (date(2026, 11, 1), date(2026, 11, 30)))
        XCTAssertTrue(DashboardPeriod.quarter.range(containing: now) == (date(2026, 10, 1), date(2026, 12, 31)))
        XCTAssertTrue(DashboardPeriod.year.range(containing: now) == (date(2026, 1, 1), date(2026, 12, 31)))
        XCTAssertTrue(DashboardPeriod.quarter.range(containing: date(2024, 2, 29)) == (date(2024, 1, 1), date(2024, 3, 31)))
        XCTAssertEqual(DashboardPeriod.quarter.rangeLabel(containing: now), "Q4 2026")
        XCTAssertEqual(DashboardPeriod.year.rangeLabel(containing: now), "2026")
    }

    func testColdRentPerPeriodMatchesAnnualValue() {
        let property = makeProperty()
        makeTenancy(makeUnit(property), start: date(2026, 3, 16), coldRent: 1_000)
        let year = metrics(property, period: .year, now: date(2026, 6, 1))
        XCTAssertEqual(year.coldRent, property.annualColdRent(forYear: 2026), accuracy: 0.01)
        XCTAssertEqual(metrics(property, now: date(2026, 3, 20)).coldRent, 1_000 * 16 / 31, accuracy: 0.01)
        XCTAssertEqual(metrics(property, period: .quarter, now: date(2026, 2, 1)).coldRent, 1_000 * 16 / 31, accuracy: 0.01)
    }

    /// Regression: Das Zeitraumende ist der letzte Tag um 0:00 Uhr. Eine am letzten Tag um 14 Uhr
    /// erfasste Zahlung oder Ausgabe fiel bisher aus der Monatskennzahl heraus.
    func testPaymentsAndExpensesOnLastDayOfPeriodCount() {
        let property = makeProperty()
        let tenancy = makeTenancy(makeUnit(property), start: date(2026, 1, 1), coldRent: 800, utility: 200)
        let payment = RentPayment(dueDate: date(2026, 11, 1), coldRentDue: 800, utilityAdvanceDue: 200)
        payment.markPaid(date: date(2026, 11, 30, hour: 14))
        payment.tenancy = tenancy
        context.insert(payment)
        makeExpense(property, on: date(2026, 11, 30, hour: 14), amount: 150)
        makeExpense(property, on: date(2026, 12, 1), amount: 999)

        let november = metrics(property, now: date(2026, 11, 13))
        XCTAssertEqual(november.paymentsReceived, 1_000, accuracy: 0.01)
        XCTAssertEqual(november.expensesInRange, 150, accuracy: 0.01)
        XCTAssertEqual(metrics(property, now: date(2026, 12, 5)).paymentsReceived, 0)
    }

    func testPartialPaymentCountsPaidAmount() {
        let property = makeProperty()
        let tenancy = makeTenancy(makeUnit(property), start: date(2026, 1, 1), coldRent: 1_000)
        let payment = RentPayment(dueDate: date(2026, 11, 1), coldRentDue: 1_000)
        payment.markPaid(amount: 400, date: date(2026, 11, 3))
        payment.tenancy = tenancy
        context.insert(payment)
        XCTAssertEqual(metrics(property, now: date(2026, 11, 13)).paymentsReceived, 400, accuracy: 0.01)
    }

    func testOpenArrearsSumsWholeBalanceOfTenantsWithOpenMonth() {
        let property = makeProperty()
        let unit = makeUnit(property)
        let late = makeTenancy(unit, start: date(2026, 9, 1), coldRent: 500)
        let punctual = makeTenancy(makeUnit(property, "OG"), start: date(2026, 11, 1), coldRent: 700)
        let paid = RentPayment(dueDate: date(2026, 11, 1), coldRentDue: 700)
        paid.markPaid(date: date(2026, 11, 2))
        paid.tenancy = punctual
        context.insert(paid)

        let november = metrics(property, now: date(2026, 11, 13))
        XCTAssertTrue(november.hasOpenPosition(late))
        XCTAssertFalse(november.hasOpenPosition(punctual))
        XCTAssertEqual(november.openArrears, 1_500, accuracy: 0.01, "September bis November offen")
    }

    func testVacancyRateAndLoss() {
        let property = makeProperty(price: 200_000)
        let rented = makeUnit(property, "EG")
        makeTenancy(rented, start: date(2025, 1, 1), coldRent: 900)
        let vacant = makeUnit(property, "OG")
        makeTenancy(vacant, start: date(2020, 1, 1), end: date(2023, 12, 31), coldRent: 500)
        makeTenancy(vacant, start: date(2024, 1, 1), end: date(2026, 9, 30), coldRent: 650)
        makeUnit(property, "DG")

        let now = metrics(property, now: date(2026, 11, 13))
        XCTAssertEqual(now.vacantUnits.count, 2)
        XCTAssertEqual(try XCTUnwrap(now.vacancyRatePercent), 200.0 / 3, accuracy: 0.001)
        XCTAssertEqual(now.estimatedMonthlyVacancyLoss, 650, accuracy: 0.01, "letzte Miete der zuletzt beendeten Vermietung")
        XCTAssertEqual(now.totalInvestment, 200_000)
    }

    func testEmptyScope() {
        let metrics = DashboardMetrics(properties: [], units: [], tenancies: [], expenses: [], range: DashboardPeriod.month.range(containing: date(2026, 1, 1)), now: date(2026, 1, 1))
        XCTAssertNil(metrics.vacancyRatePercent)
        XCTAssertNil(metrics.grossYieldPercent)
        XCTAssertEqual(metrics.coldRent, 0)
        XCTAssertEqual(metrics.openArrears, 0)
    }

    func testPaymentStatus() {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2026, 1, 1))
        XCTAssertEqual(DashboardPaymentStatus(tenancy: tenancy, on: date(2026, 11, 13)), .open, "ohne Zahlungseintrag offen")
        let payment = RentPayment(dueDate: date(2026, 11, 1), coldRentDue: 1_000)
        payment.tenancy = tenancy
        context.insert(payment)
        payment.markPaid(date: date(2026, 11, 2))
        XCTAssertEqual(DashboardPaymentStatus(tenancy: tenancy, on: date(2026, 11, 13)), .paid)
    }
}

final class RentLedgerTests: ModelTestCase {
    func testRunningBalanceCarriesOverFromPreviousYear() throws {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2025, 11, 1), end: date(2026, 2, 28), coldRent: 800, utility: 200)
        let december = RentPayment(dueDate: date(2025, 12, 1), coldRentDue: 800, utilityAdvanceDue: 200)
        december.markPaid(date: date(2025, 12, 3))
        december.tenancy = tenancy
        context.insert(december)

        let rows = RentLedger.rows(for: tenancy, year: 2026)
        XCTAssertEqual(rows.count, 2, "Januar und Februar")
        XCTAssertEqual(rows[0].runningBalance, 2_000, accuracy: 0.01, "1.000 € aus November 2025 + Januar")
        XCTAssertEqual(rows[1].runningBalance, 3_000, accuracy: 0.01)
        XCTAssertTrue(RentLedger.isRelevant(tenancy, inYear: 2026))
        XCTAssertFalse(RentLedger.isRelevant(tenancy, inYear: 2027))
    }

    func testMarkPaidCreatesPaymentWithSollAndCanBeUndone() throws {
        let tenancy = makeTenancy(makeUnit(makeProperty()), start: date(2026, 1, 1), coldRent: 750, utility: 150)
        let march = date(2026, 3, 1)

        RentLedger.markPaid(tenancy: tenancy, month: march, on: date(2026, 3, 4), context: context)
        let payment = try XCTUnwrap(tenancy.payment(forMonthContaining: march))
        XCTAssertTrue(payment.isPaid)
        XCTAssertEqual(payment.totalDue, 900, accuracy: 0.01)
        XCTAssertEqual(RentLedger.rows(for: tenancy, year: 2026)[2].paid, 900, accuracy: 0.01)

        RentLedger.markPaid(tenancy: tenancy, month: march, context: context)
        XCTAssertEqual(try count(RentPayment.self), 1, "kein zweiter Eintrag für denselben Monat")

        RentLedger.markUnpaid(tenancy: tenancy, month: march)
        XCTAssertFalse(payment.isPaid)
        XCTAssertEqual(RentLedger.rows(for: tenancy, year: 2026)[2].paid, 0)
    }

    func testAvailableYearsAndCurrentArrears() {
        let unit = makeUnit(makeProperty())
        let old = makeTenancy(unit, start: date(2022, 5, 1), end: date(2023, 4, 30))
        let running = makeTenancy(makeUnit(unit.property!, "OG"), start: date(2026, 10, 1), coldRent: 600)
        XCTAssertEqual(RentLedger.availableYears(for: [old, running], now: date(2026, 11, 13)), [2026, 2023, 2022])

        let arrears = RentLedger.currentArrears([old, running], upTo: date(2026, 11, 13))
        XCTAssertEqual(arrears.first?.tenancy, old, "12 offene Monate à 1.000 €")
        XCTAssertEqual(arrears.first?.balance ?? 0, 12_000, accuracy: 0.01)
        XCTAssertEqual(arrears.last?.balance ?? 0, 1_200, accuracy: 0.01)
    }
}

final class AmortizationScheduleTests: ModelTestCase {
    private func loanProperty() -> Property {
        let property = makeProperty()
        property.loanAmount = 100_000
        property.interestRatePercent = 3
        property.initialRepaymentRatePercent = 2
        property.loanStartDate = date(2025, 7, 1)
        return property
    }

    func testYearlyScheduleRunsToFullRepayment() throws {
        let schedule = loanProperty().amortizationSchedule()
        XCTAssertEqual(schedule.first?.year, 2025)
        XCTAssertEqual(try XCTUnwrap(schedule.last).remaining, 0, accuracy: 0.5)
        XCTAssertEqual(schedule.reduce(0) { $0 + $1.principal }, 100_000, accuracy: 1)
        XCTAssertEqual(Array(schedule.map(\.year)), Array(2025...(2025 + schedule.count - 1)), "lückenlose Jahre")
        XCTAssertEqual(schedule[0].interest, 1_500, accuracy: 0.01, "Startjahr: 6 von 12 Monaten")
    }

    func testMonthlyScheduleEndsOnYearlyBalance() throws {
        let property = loanProperty()
        let rows = property.monthlyAmortizationSchedule(forYear: 2026)
        let year = try XCTUnwrap(property.loanBreakdown(forYear: 2026))
        XCTAssertEqual(rows.count, 12)
        XCTAssertEqual(try XCTUnwrap(rows.last).remainingBalance, year.remainingBalance, accuracy: 0.001)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.interest }, year.interest, accuracy: 0.01)
        XCTAssertTrue(zip(rows, rows.dropFirst()).allSatisfy { $0.remainingBalance >= $1.remainingBalance })
    }

    func testNoScheduleWithoutLoan() {
        let property = makeProperty()
        XCTAssertTrue(property.amortizationSchedule().isEmpty)
        XCTAssertTrue(property.monthlyAmortizationSchedule(forYear: 2026).isEmpty)
        XCTAssertTrue(loanProperty().monthlyAmortizationSchedule(forYear: 2024).isEmpty, "vor Darlehensbeginn")
    }
}

/// Prüfregeln der Bearbeiten-Formulare.
final class FormValidationTests: XCTestCase {
    func testNumberRules() {
        XCTAssertNil(FormValidation.number("", "Miete"))
        XCTAssertEqual(FormValidation.number(" ", "Miete", required: true), "„Miete“ fehlt.")
        XCTAssertEqual(FormValidation.number("abc", "Miete"), "„Miete“ ist keine gültige Zahl.")
        XCTAssertNil(FormValidation.number("1.234,50 €", "Miete"))
        XCTAssertNotNil(FormValidation.number("-1", "Miete"))
        XCTAssertNil(FormValidation.number("0", "Miete"))
        XCTAssertNotNil(FormValidation.number("0", "Miete", .positive))
        XCTAssertNil(FormValidation.number("100", "Satz", .percent))
        XCTAssertNotNil(FormValidation.number("100,1", "Satz", .percent))
        XCTAssertNil(FormValidation.number("5", "Wert", .range(1...10)))
        XCTAssertNotNil(FormValidation.number("11", "Wert", .range(1...10)))
    }

    func testIntegerRequiredAndDateOrder() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 18))!
        XCTAssertNil(FormValidation.integer("1998", "Baujahr", 1800...2100))
        XCTAssertNotNil(FormValidation.integer("1998,5", "Baujahr", 1800...2100))
        XCTAssertNotNil(FormValidation.integer("1700", "Baujahr", 1800...2100))
        XCTAssertNotNil(FormValidation.integer("", "Baujahr", 1800...2100, required: true))
        XCTAssertNotNil(FormValidation.required("  ", "Name"))
        XCTAssertNil(FormValidation.required("Haus", "Name"))
        XCTAssertNil(FormValidation.dateOrder(start: start, end: nil))
        XCTAssertNil(FormValidation.dateOrder(start: start, end: calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))), "gleicher Tag ist erlaubt")
        XCTAssertNotNil(FormValidation.dateOrder(start: start, end: calendar.date(from: DateComponents(year: 2026, month: 5, day: 9))))
    }
}

/// Excel-Export: Rundreise Export → eigener Importer, plus Sonderzeichen und Spaltenbuchstaben.
final class XLSXExporterTests: XCTestCase {
    func testRoundTripThroughImporter() throws {
        let sheet = XLSXExporter.Sheet(name: "Kosten", headers: ["Kostenart", "Betrag", "Umlagefähig"], rows: [
            [.string("Müllabfuhr & Straßenreinigung <Stadt>"), .currency(1_234.56), .string("ja")],
            [.string("Verwaltergebühr \"Fa. X\""), .number(300), .string("nein")],
        ])
        let data = try XCTUnwrap(XLSXExporter.data(sheets: [sheet]))
        let rows = try XLSXImporter.rows(from: data)
        XCTAssertEqual(rows.first, ["Kostenart", "Betrag", "Umlagefähig"])
        XCTAssertEqual(rows[1][0], "Müllabfuhr & Straßenreinigung <Stadt>")
        XCTAssertEqual(DecimalInputParser.parse(rows[1][1]) ?? 0, 1_234.56, accuracy: 0.001, "Importer liefert Zahlen mit deutschem Komma")
        XCTAssertEqual(rows[2][0], "Verwaltergebühr \"Fa. X\"")

        let drafts = try XLSXImporter.parseLineItems(from: data)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.map(\.isApportionable), [true, false])
    }

    func testManyColumnsUseLetterPairs() throws {
        let headers = (1...28).map { "S\($0)" }
        let data = try XCTUnwrap(XLSXExporter.data(sheets: [XLSXExporter.Sheet(name: "Breit", headers: headers, rows: [])]))
        XCTAssertEqual(try XLSXImporter.rows(from: data).first, headers, "Spalten AA und AB werden korrekt gelesen")
    }

    func testNoSheetsGivesNoFile() {
        XCTAssertNil(XLSXExporter.data(sheets: []))
    }
}
