import XCTest
@testable import Mietverwaltung

final class DecimalInputParserTests: XCTestCase {
    func testGermanThousandsAndDecimal() {
        XCTAssertEqual(DecimalInputParser.parse("1.234,56"), 1234.56)
        XCTAssertEqual(DecimalInputParser.parse("1.234.567,89"), 1_234_567.89)
    }

    func testEnglishThousandsAndDecimal() {
        XCTAssertEqual(DecimalInputParser.parse("1,234.56"), 1234.56)
        XCTAssertEqual(DecimalInputParser.parse("1,234,567.89"), 1_234_567.89)
    }

    func testSingleCommaIsAlwaysDecimal() {
        XCTAssertEqual(DecimalInputParser.parse("12,5"), 12.5)
        XCTAssertEqual(DecimalInputParser.parse("3,125"), 3.125)
    }

    func testSingleDotWithThreeDigitsIsGermanThousands() {
        XCTAssertEqual(DecimalInputParser.parse("1.234"), 1234)
        XCTAssertEqual(DecimalInputParser.parse("250.000"), 250_000)
    }

    func testSingleDotOtherwiseIsDecimal() {
        XCTAssertEqual(DecimalInputParser.parse("12.5"), 12.5)
        XCTAssertEqual(DecimalInputParser.parse("12.50"), 12.5)
    }

    func testStripsCurrencyPercentAndSpacesIncludingOwnFormatterOutput() {
        XCTAssertEqual(DecimalInputParser.parse("150,00€"), 150)
        XCTAssertEqual(DecimalInputParser.parse(" 150,00 € "), 150)
        XCTAssertEqual(DecimalInputParser.parse("19 %"), 19)
        XCTAssertEqual(DecimalInputParser.parse((1234.56).asCurrency), 1234.56)
        XCTAssertEqual(DecimalInputParser.parse("1 234,56"), 1234.56)
    }

    func testNegativeAndPlainIntegers() {
        XCTAssertEqual(DecimalInputParser.parse("-12,5"), -12.5)
        XCTAssertEqual(DecimalInputParser.parse("850"), 850)
    }

    func testRejectsGarbage() {
        XCTAssertNil(DecimalInputParser.parse(""))
        XCTAssertNil(DecimalInputParser.parse("   "))
        XCTAssertNil(DecimalInputParser.parse("zwölf"))
        XCTAssertNil(DecimalInputParser.parse("1,2,3.4,5"))
        XCTAssertNil(DecimalInputParser.parse("inf"))
    }

    func testIsUnparsableDistinguishesEmptyFromGarbage() {
        XCTAssertFalse(DecimalInputParser.isUnparsable(""))
        XCTAssertFalse(DecimalInputParser.isUnparsable("12,5"))
        XCTAssertTrue(DecimalInputParser.isUnparsable("abc"))
    }

    func testLineItemImportNowReadsEnglishFormattedAmounts() {
        XCTAssertEqual(LineItemRowParser.parseAmount("1,234.56"), 1234.56)
        XCTAssertEqual(LineItemRowParser.parseAmount("1.234,56 €"), 1234.56)
    }
}
