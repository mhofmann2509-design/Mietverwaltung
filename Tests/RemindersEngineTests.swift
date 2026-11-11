import XCTest
import SwiftData
@testable import Mietverwaltung

private typealias Unit = Mietverwaltung.Unit

@MainActor
final class RemindersEngineTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11))!

    override func setUpWithError() throws {
        let schema = AppSchema.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func days(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: now)!
    }

    private func reminders(properties: [Property] = [], tenancies: [Tenancy] = [], landlord: Landlord? = nil, statuses: [TaxFilingStatus] = [], meetings: [OwnersMeetingEvent] = []) -> [ReminderItem] {
        RemindersEngine.reminders(properties: properties, tenancies: tenancies, landlord: landlord, taxFilingStatuses: statuses, ownersMeetings: meetings, now: now)
    }

    private func items(_ prefix: String, in list: [ReminderItem]) -> [ReminderItem] {
        list.filter { $0.id.hasPrefix(prefix) }
    }

    private func propertyWithUnit(purchaseDate: Date? = nil) -> Property {
        let property = Property(name: "Haus", purchaseDate: purchaseDate)
        context.insert(property)
        let unit = Unit(name: "EG")
        unit.property = property
        context.insert(unit)
        return property
    }

    // MARK: - Mietende

    func testTenancyEndingSeverityDependsOnDistance() {
        let soon = Tenancy(startDate: date(2020, 1, 1), endDate: days(20))
        let later = Tenancy(startDate: date(2020, 1, 1), endDate: days(60))
        let far = Tenancy(startDate: date(2020, 1, 1), endDate: days(120))
        [soon, later, far].forEach(context.insert)

        XCTAssertEqual(items("tenancy-ending", in: reminders(tenancies: [soon])).first?.severity, .warning)
        XCTAssertEqual(items("tenancy-ending", in: reminders(tenancies: [later])).first?.severity, .info)
        XCTAssertTrue(items("tenancy-ending", in: reminders(tenancies: [far])).isEmpty)
    }

    // MARK: - Kaution

    func testUnreturnedDepositEscalatesAfterSixMonthsAndExpiresAfterOneYear() {
        let recent = Tenancy(startDate: date(2020, 1, 1), endDate: days(-30), deposit: 1_500)
        let old = Tenancy(startDate: date(2020, 1, 1), endDate: days(-200), deposit: 1_500)
        let ancient = Tenancy(startDate: date(2020, 1, 1), endDate: days(-400), deposit: 1_500)
        let returned = Tenancy(startDate: date(2020, 1, 1), endDate: days(-200), deposit: 1_500)
        returned.depositReturnedAt = days(-100)
        [recent, old, ancient, returned].forEach(context.insert)

        XCTAssertEqual(items("deposit-unreturned", in: reminders(tenancies: [recent])).first?.severity, .info)
        XCTAssertEqual(items("deposit-unreturned", in: reminders(tenancies: [old])).first?.severity, .warning)
        XCTAssertTrue(items("deposit-unreturned", in: reminders(tenancies: [ancient])).isEmpty)
        XCTAssertTrue(items("deposit-unreturned", in: reminders(tenancies: [returned])).isEmpty)
    }

    // MARK: - Nebenkostenabrechnung (12 Monate nach Ende des Abrechnungszeitraums)

    func testMissingUtilityStatementsAreOverdueOrDue() {
        let property = propertyWithUnit()
        let list = reminders(properties: [property])

        XCTAssertEqual(items("utility-statement-overdue", in: list).count, 1, "2024 – Frist 31.12.2025 abgelaufen")
        XCTAssertEqual(items("utility-statement-due", in: list).count, 1, "2025 – Frist 31.12.2026 in 50 Tagen")
    }

    func testExistingStatementSuppressesReminderForThatYear() {
        let property = propertyWithUnit()
        let statement = UtilityStatement()
        statement.periodStart = date(2025, 1, 1)
        statement.periodEnd = date(2025, 12, 31)
        statement.property = property
        context.insert(statement)
        let list = reminders(properties: [property])

        XCTAssertTrue(items("utility-statement-due", in: list).isEmpty)
        XCTAssertEqual(items("utility-statement-overdue", in: list).count, 1)
    }

    func testPropertyWithoutUnitsGetsNoUtilityReminder() {
        let property = Property(name: "Grundstück")
        context.insert(property)
        XCTAssertTrue(items("utility-statement", in: reminders(properties: [property])).isEmpty)
    }

    // MARK: - Grunderwerbsteuer (bewusst ohne Fälligkeitsdatum)

    func testTransferTaxCheckWindow() {
        let inWindow = propertyWithUnit(purchaseDate: date(2026, 5, 1))
        let tooEarly = propertyWithUnit(purchaseDate: date(2026, 10, 1))
        let paid = propertyWithUnit(purchaseDate: date(2026, 5, 1))
        paid.purchaseTransferTaxPaid = true

        let reminder = items("transfer-tax-check", in: reminders(properties: [inWindow])).first
        XCTAssertNotNil(reminder)
        XCTAssertNil(reminder?.dueDate)
        XCTAssertTrue(items("transfer-tax-check", in: reminders(properties: [tooEarly])).isEmpty)
        XCTAssertTrue(items("transfer-tax-check", in: reminders(properties: [paid])).isEmpty)
    }

    // MARK: - Wirtschaftsplan

    func testMissingWirtschaftsplanAfterAprilFirst() {
        let missing = propertyWithUnit()
        let present = propertyWithUnit()
        let plan = WirtschaftsplanStatement(year: 2026)
        plan.property = present
        context.insert(plan)

        XCTAssertEqual(items("wirtschaftsplan-missing", in: reminders(properties: [missing])).count, 1)
        XCTAssertTrue(items("wirtschaftsplan-missing", in: reminders(properties: [present])).isEmpty)
    }

    // MARK: - Steuererklärung

    func testTaxFilingSeverityByDeadline() {
        func status(deadlineIn offset: Int, submitted: Bool = false) -> TaxFilingStatus {
            let status = TaxFilingStatus(taxYear: 2025, submittedAt: submitted ? days(-1) : nil, deadlineOverride: days(offset))
            context.insert(status)
            return status
        }

        XCTAssertEqual(items("tax-filing", in: reminders(statuses: [status(deadlineIn: -5)])).first?.severity, .overdue)
        XCTAssertEqual(items("tax-filing", in: reminders(statuses: [status(deadlineIn: 20)])).first?.severity, .warning)
        XCTAssertEqual(items("tax-filing", in: reminders(statuses: [status(deadlineIn: 60)])).first?.severity, .info)
        XCTAssertTrue(items("tax-filing", in: reminders(statuses: [status(deadlineIn: 120)])).isEmpty)
        XCTAssertTrue(items("tax-filing", in: reminders(statuses: [status(deadlineIn: -5, submitted: true)])).isEmpty)
    }

    // MARK: - Eigentümerversammlung

    func testOwnersMeetingWindow() {
        func meeting(in offset: Int) -> OwnersMeetingEvent {
            let meeting = OwnersMeetingEvent(date: days(offset))
            context.insert(meeting)
            return meeting
        }

        XCTAssertEqual(items("owners-meeting", in: reminders(meetings: [meeting(in: 2)])).first?.severity, .warning)
        XCTAssertEqual(items("owners-meeting", in: reminders(meetings: [meeting(in: 10)])).first?.severity, .info)
        XCTAssertTrue(items("owners-meeting", in: reminders(meetings: [meeting(in: 20)])).isEmpty)
        XCTAssertTrue(items("owners-meeting", in: reminders(meetings: [meeting(in: -1)])).isEmpty)
    }

    // MARK: - Modernisierungsmieterhöhung (§ 559b Abs. 2 BGB)

    func testModernizationIncreaseBecomingEffectiveSoon() {
        let tenancy = Tenancy(startDate: date(2020, 1, 1))
        tenancy.modernizationIncreaseDeclaredAt = date(2026, 9, 10)
        context.insert(tenancy)

        let reminder = items("modernization-increase", in: reminders(tenancies: [tenancy])).first
        XCTAssertEqual(reminder?.title, "Modernisierungsmieterhöhung bald wirksam")
        XCTAssertEqual(reminder?.dueDate, date(2026, 12, 1))
    }

    // MARK: - Sortierung

    func testOverdueItemsComeFirst() {
        let property = propertyWithUnit()
        let list = reminders(properties: [property])
        XCTAssertEqual(list.first?.severity, .overdue)
        XCTAssertEqual(list.map(\.severity), list.map(\.severity).sorted())
    }
}
