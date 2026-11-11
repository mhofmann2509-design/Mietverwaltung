import XCTest
@testable import Mietverwaltung

/// Tests für `XLSXImporter` gegen eine echte, mit openpyxl erzeugte .xlsx-Datei (als Base64
/// eingebettet, damit kein zusätzliches Testressourcen-Bundle benötigt wird) – drei Spalten
/// (Kostenart, Betrag, Umlagefähig), eine Kopfzeile, zwei Datenzeilen. Stellt sicher, dass das
/// echte OOXML-Zellformat (hier von openpyxl standardmäßig als `inlineStr` statt über
/// `sharedStrings.xml` geschrieben) korrekt gelesen wird, nicht nur eine synthetische Row-Matrix.
final class XLSXImporterTests: XCTestCase {
    /// „Kostenart;Betrag;Umlagefähig“-Kopfzeile, dann „Heizung“/450,50/„Ja“ und
    /// „Hausmeister“/120/„Nein“ – erzeugt mit `openpyxl` (siehe Kommentar oben).
    private static let sampleWorkbookBase64 = "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"

    private func loadSampleWorkbookData() throws -> Data {
        try XCTUnwrap(Data(base64Encoded: Self.sampleWorkbookBase64))
    }

    func testParsesRealWorkbookSkippingHeaderRow() throws {
        let drafts = try XLSXImporter.parseLineItems(from: loadSampleWorkbookData())
        XCTAssertEqual(drafts.count, 2)
    }

    func testFirstDataRowValuesAndApportionableFlag() throws {
        let drafts = try XLSXImporter.parseLineItems(from: loadSampleWorkbookData())
        let heizung = try XCTUnwrap(drafts.first)
        let heizungAmount = try XCTUnwrap(Double(heizung.amountText.replacingOccurrences(of: ",", with: ".")))
        XCTAssertEqual(heizung.costType, "Heizung")
        XCTAssertEqual(heizungAmount, 450.5, accuracy: 0.001)
        XCTAssertTrue(heizung.isApportionable)
    }

    func testSecondDataRowMarksNonApportionable() throws {
        let drafts = try XLSXImporter.parseLineItems(from: loadSampleWorkbookData())
        let hausmeister = try XCTUnwrap(drafts.last)
        let hausmeisterAmount = try XCTUnwrap(Double(hausmeister.amountText.replacingOccurrences(of: ",", with: ".")))
        XCTAssertEqual(hausmeister.costType, "Hausmeister")
        XCTAssertEqual(hausmeisterAmount, 120.0, accuracy: 0.001)
        XCTAssertFalse(hausmeister.isApportionable)
    }

    func testThrowsForNonZipData() {
        let garbage = Data("not a zip file".utf8)
        XCTAssertThrowsError(try XLSXImporter.parseLineItems(from: garbage))
    }

    func testRejectsEntriesAboveSizeLimit() throws {
        let data = try loadSampleWorkbookData()
        XCTAssertThrowsError(try XLSXImporter.rows(from: data, maximumUncompressedSize: 100)) { error in
            XCTAssertEqual(error as? XLSXImportError, .tooLarge)
        }
        XCTAssertNoThrow(try XLSXImporter.rows(from: data))
    }

    /// Mit Python erzeugtes Archiv, dessen sheet1.xml eine DOCTYPE-/Entity-Deklaration enthält.
    func testRejectsDoctypeDeclarations() throws {
        let data = try XCTUnwrap(Data(base64Encoded: "UEsDBBQAAAAIAHxJa100xMDYwwAAAAIBAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sTY4/b8JADMW/ynEDI046MBTHCApDlxaJLKjqcEqv5MT9ie6sUPXT49Cq6vJk/6z3/HD9FbwabS4uxUbXi0qvCWe716f2dNgrn/y3esPZ/qV9bk/TqrSIpnfCa8qX0lvLSiJiaXTPPDwClK63wZRFGmyUy2fKwbCs+QxlyNZ83E3Bw0NVLSEYFzXhne0MG8KcripLFaHdNGxqrbjRLnoX7ZGzcFcImebSZIXAhDAB6H4N28k6Uo0w/lCQSNF/P+CvPN0AUEsBAhQDFAAAAAgAfElrXTTEwNjDAAAAAgEAABgAAAAAAAAAAAAAAIABAAAAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLBQYAAAAAAQABAEYAAAD5AAAAAAA="))
        XCTAssertThrowsError(try XLSXImporter.parseLineItems(from: data)) { error in
            XCTAssertEqual(error as? XLSXImportError, .unsupportedContent)
        }
    }
}
