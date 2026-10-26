import XCTest
@testable import Mietverwaltung

/// Tests für den CSV-Import von Betriebskosten-Positionen (`CSVImporter.parseLineItems`),
/// insbesondere die deutsche Zahlenformat-Erkennung (Komma als Dezimaltrennzeichen, Punkt als
/// Tausendertrenner) – bisher ohne jede Testabdeckung, obwohl Beträge aus einer vom Nutzer
/// hochgeladenen Datei stammen und bei falscher Interpretation unbemerkt einen falschen
/// Euro-Betrag in die Nebenkostenabrechnung übernehmen würden.
final class CSVImporterTests: XCTestCase {

    func testParsesGermanDecimalCommaAmount() {
        let items = CSVImporter.parseLineItems(from: "Heizung;1234,56")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.costType, "Heizung")
        XCTAssertEqual(items.first?.amountText, "1234,56")
    }

    func testParsesGermanThousandsSeparatorWithDecimalComma() {
        let items = CSVImporter.parseLineItems(from: "Versicherung;1.234,56")
        XCTAssertEqual(items.first?.amountText, "1234,56")
    }

    /// Ohne Komma, aber mit einem Punkt mit genau drei Nachkommastellen: das ist für einen
    /// Geldbetrag kein Dezimaltrennzeichen (Cent-Beträge haben höchstens zwei Nachkommastellen),
    /// sondern ein deutscher Tausendertrenner ohne angegebene Cent-Stellen. Vor dem Fix wäre
    /// "1.234" als 1,234 € statt als 1.234 € eingelesen worden – ein Fehler um den Faktor 1000.
    func testParsesGermanThousandsSeparatorWithoutDecimals() {
        let items = CSVImporter.parseLineItems(from: "Hausmeister;1.234")
        XCTAssertEqual(items.first?.amountText, "1234,00")
    }

    func testPlainIntegerAmountIsNotMisreadAsThousands() {
        // Ein normaler Betrag ohne Trennzeichen (z.B. "500") darf nicht fälschlich als
        // Tausendertrenner-Fall behandelt werden.
        let items = CSVImporter.parseLineItems(from: "Müllabfuhr;500")
        XCTAssertEqual(items.first?.amountText, "500,00")
    }

    func testSkipsHeaderRowWhenSecondColumnIsNotAnAmount() {
        let items = CSVImporter.parseLineItems(from: """
        Kostenart;Betrag
        Wasser;120,00
        """)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.costType, "Wasser")
    }

    func testApportionableFlagDefaultsToTrueAndRecognizesGermanNo() {
        let items = CSVImporter.parseLineItems(from: """
        Heizung;100,00;Ja
        Verwaltergebühr;50,00;Nein
        Grundsteuer;80,00
        """)
        XCTAssertEqual(items[0].isApportionable, true)
        XCTAssertEqual(items[1].isApportionable, false)
        XCTAssertEqual(items[2].isApportionable, true, "Ohne dritte Spalte gilt der Standard: umlagefähig.")
    }

    func testCommaSeparatedFileIsDetectedWhenFirstRowHasNoSemicolon() {
        let items = CSVImporter.parseLineItems(from: "Heizung,100,00")
        XCTAssertEqual(items.first?.costType, "Heizung")
        XCTAssertEqual(items.first?.amountText, "100,00")
    }

    func testRowWithoutParsableAmountIsSkippedNotCrashing() {
        let items = CSVImporter.parseLineItems(from: """
        Heizung;100,00
        Ohne Betrag;abc
        Wasser;50,00
        """)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.costType), ["Heizung", "Wasser"])
    }
}
