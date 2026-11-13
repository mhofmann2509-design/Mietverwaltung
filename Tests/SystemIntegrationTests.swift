import XCTest
import SwiftData
import UserNotifications
import EventKit
import CoreText
@testable import Mietverwaltung

/// Die Teile der Systemfunktionen, die ohne echtes Gerät, Apple-ID oder Berechtigung prüfbar sind:
/// was geplant bzw. eingetragen wird, die Texterkennung an einem erzeugten Beleg und die
/// iCloud-Tauglichkeit des Datenmodells. Ob iCloud tatsächlich synchronisiert oder eine
/// Mitteilung erscheint, bleibt ein Test auf dem Gerät.
final class NotificationAndCalendarTests: ModelTestCase {
    private func item(_ id: String, title: String = "Frist", due: Date?) -> ReminderItem {
        ReminderItem(id: id, title: title, subtitle: "Mieter Max Mustermann · 1.000 €", severity: .warning, systemImage: "bell", dueDate: due)
    }

    func testRequestsAreScheduledTheDayBeforeAtNine() throws {
        let now = date(2026, 11, 13, hour: 10)
        let requests = NotificationScheduler.requests(for: [
            item("future", due: date(2026, 12, 1)),
            item("tomorrow", due: date(2026, 11, 14)),
            item("no-date", due: nil),
        ], now: now)

        XCTAssertEqual(requests.map(\.identifier), ["future", "tomorrow"], "Hinweise ohne Termin werden nicht geplant")
        let future = try XCTUnwrap(requests[0].trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(future.dateComponents.day, 30)
        XCTAssertEqual(future.dateComponents.month, 11)
        XCTAssertEqual(future.dateComponents.hour, 9)
        XCTAssertFalse(future.repeats)
        XCTAssertTrue(requests[1].trigger is UNTimeIntervalNotificationTrigger, "Vortag schon erreicht → sofort")
    }

    /// Mitteilungen erscheinen im Sperrbildschirm – sie dürfen keine Namen oder Beträge enthalten.
    func testNotificationContentContainsNoPersonalData() throws {
        let property = makeProperty("Musterweg 5")
        let tenant = Tenant(firstName: "Max", lastName: "Mustermann")
        context.insert(tenant)
        let tenancy = makeTenancy(makeUnit(property), start: date(2020, 1, 1), end: Calendar.current.date(byAdding: .day, value: 20, to: .now), coldRent: 1_234, tenant: tenant)
        let reminders = RemindersEngine.reminders(properties: [property], tenancies: [tenancy], landlord: nil, taxFilingStatuses: [], ownersMeetings: [])
        let requests = NotificationScheduler.requests(for: reminders)

        XCTAssertFalse(requests.isEmpty)
        for request in requests {
            let text = request.content.title + " " + request.content.body
            XCTAssertFalse(text.contains("Mustermann"), text)
            XCTAssertFalse(text.contains("1.234") || text.contains("1234"), text)
            XCTAssertEqual(request.content.body, "Details in der Mietverwaltung ansehen.")
        }
    }

    func testCalendarEventHasTwoHoursAndAlarmThreeDaysBefore() throws {
        let event = EKEvent(eventStore: EKEventStore())
        let start = date(2026, 5, 20, hour: 18)
        CalendarEventManager.configure(event, title: "Eigentümerversammlung", date: start, location: "Gemeindesaal", notes: "TOP 1")
        XCTAssertEqual(event.title, "Eigentümerversammlung")
        XCTAssertEqual(event.startDate, start)
        XCTAssertEqual(event.endDate.timeIntervalSince(start), 2 * 3600)
        XCTAssertEqual(event.location, "Gemeindesaal")
        XCTAssertEqual(try XCTUnwrap(event.alarms?.first).relativeOffset, -3 * 24 * 3600)
    }
}

final class OCRRecognitionTests: XCTestCase {
    /// Erzeugt einen einseitigen PDF-Beleg mit den Zeilen in großer Schrift.
    private func receiptPDF(_ lines: [String]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 420, height: 60 + CGFloat(lines.count) * 40)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        pdf.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 22, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            pdf.textPosition = CGPoint(x: 24, y: box.height - 50 - CGFloat(index) * 40)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), pdf)
        }
        pdf.endPDFPage()
        pdf.closePDF()
        return data as Data
    }

    func testReceiptIsRecognizedFromRenderedPDF() throws {
        let data = receiptPDF(["Baumarkt Schmidt", "Datum 05.03.2025", "Farbe 49,90", "Summe 123,45"])
        let rows = OCRTextRecognizer.recognizeRows(from: data)
        try XCTSkipIf(rows.isEmpty, "Texterkennung auf diesem System nicht verfügbar")

        let result = ReceiptOCR.recognize(from: data)
        XCTAssertEqual(result.vendor, "Baumarkt Schmidt")
        XCTAssertEqual(try XCTUnwrap(result.amount), 123.45, accuracy: 0.001)
        XCTAssertEqual(result.date, Calendar.current.date(from: DateComponents(year: 2025, month: 3, day: 5)))
    }

    func testLineItemsAreRecognizedAndTotalsSkipped() throws {
        let data = receiptPDF(["Wirtschaftsplan 2026", "Hausmeister 1.200,00", "Gebäudeversicherung 840,50", "Summe 2.040,50"])
        try XCTSkipIf(OCRTextRecognizer.recognizeRows(from: data).isEmpty, "Texterkennung auf diesem System nicht verfügbar")

        let items = ReceiptOCR.recognizeLineItems(from: data)
        XCTAssertEqual(items.count, 2, "\(items.map(\.costType))")
        XCTAssertEqual(DecimalInputParser.parse(items.first?.amountText ?? "") ?? 0, 1_200, accuracy: 0.01)
    }

    func testInvalidDataGivesEmptyResult() {
        XCTAssertTrue(OCRTextRecognizer.recognizeRows(from: Data("kein Bild".utf8)).isEmpty)
        XCTAssertNil(ReceiptOCR.recognize(from: Data()).amount)
    }
}

/// iCloud (CloudKit) verlangt: keine eindeutigen Attribute, alle Beziehungen optional. Ein Verstoß
/// würde erst auf dem Gerät beim Start mit iCloud auffallen – hier schon beim Testlauf.
final class CloudKitCompatibilityTests: XCTestCase {
    func testSchemaMeetsCloudKitRules() {
        let schema = AppSchema.schema
        XCTAssertFalse(schema.entities.isEmpty)
        for entity in schema.entities {
            for attribute in entity.attributes {
                XCTAssertFalse(attribute.isUnique, "\(entity.name).\(attribute.name) ist eindeutig – mit CloudKit nicht erlaubt")
            }
            for relationship in entity.relationships {
                XCTAssertTrue(relationship.isOptional, "\(entity.name).\(relationship.name) muss optional sein")
                XCTAssertNotEqual(relationship.deleteRule, .deny, "\(entity.name).\(relationship.name): Deny wird von CloudKit nicht unterstützt")
            }
        }
    }

    func testTestRunsNeverUseTheRealDatabase() {
        XCTAssertTrue(LaunchEnvironment.isUnitTesting)
        XCTAssertTrue(LaunchEnvironment.usesInMemoryStore)
    }
}
