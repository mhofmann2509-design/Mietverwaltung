import Foundation
import ZIPFoundation

enum XLSXImportError: LocalizedError {
    case notAZipArchive
    case noWorksheetFound
    case tooLarge
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .notAZipArchive: return "Die Datei ist keine gültige .xlsx-Datei."
        case .noWorksheetFound: return "In der .xlsx-Datei wurde kein Tabellenblatt gefunden."
        case .tooLarge: return "Die .xlsx-Datei ist für eine Kostenarten-Liste ungewöhnlich groß und wurde nicht eingelesen."
        case .unsupportedContent: return "Die .xlsx-Datei enthält nicht unterstützte Inhalte und wurde nicht eingelesen."
        }
    }
}

/// Liest eine Kostenarten-Liste direkt aus einer echten .xlsx-Datei ein, ohne vorherigen
/// CSV-Export – siehe `CSVImporter` für den Dateityp, von dem diese Funktion übernommen wurde,
/// und `LineItemRowParser` für die beiden gemeinsame Spaltenauswertung.
///
/// Liest bewusst nur das erste Tabellenblatt, keine Formeln (nur deren zuletzt berechneter Wert,
/// falls Excel ihn mitgespeichert hat) und keine Zellformatierung – entspricht damit demselben
/// Umfang wie der bisherige CSV-Import, nur ohne den Zwischenschritt über eine Export-Datei.
/// Eine .xlsx-Datei ist technisch ein ZIP-Archiv aus XML-Dateien (OOXML); `ZIPFoundation`
/// entpackt es, `XMLParser` (Foundation, keine Zusatzbibliothek) liest die enthaltenen
/// `sheet1.xml`/`sharedStrings.xml`.
enum XLSXImporter {
    static func parseLineItems(from data: Data) throws -> [LineItemDraft] {
        try parse(from: data).items
    }

    static func parse(from data: Data) throws -> LineItemRowParser.Result {
        LineItemRowParser.parse(rows: try rows(from: data))
    }

    static func rows(from data: Data, maximumUncompressedSize: UInt64 = maximumUncompressedSize) throws -> [[String]] {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw XLSXImportError.notAZipArchive
        }

        let sharedStrings: [String]
        do {
            sharedStrings = try self.sharedStrings(in: archive, limit: maximumUncompressedSize)
        } catch let error as XLSXImportError {
            throw error
        } catch {
            sharedStrings = []
        }

        guard let sheetEntry = firstWorksheetEntry(in: archive) else {
            throw XLSXImportError.noWorksheetFound
        }

        let sheetXML = try extractXML(sheetEntry, from: archive, limit: maximumUncompressedSize)

        let delegate = SheetXMLParserDelegate(sharedStrings: sharedStrings)
        let parser = XMLParser(data: sheetXML)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    /// Das erste Tabellenblatt – vereinfachend `xl/worksheets/sheet1.xml`, falls vorhanden
    /// (der Fall bei praktisch jeder exportierten Datei), sonst das alphabetisch erste
    /// `sheetN.xml` im Archiv. Löst die Reihenfolge nicht über `xl/workbook.xml` auf, da dafür
    /// in aller Regel kein Unterschied besteht.
    /// Obergrenze für eine entpackte XML-Datei – eine Kostenarten-Liste ist wenige KB groß; die
    /// Grenze schützt vor präparierten Archiven, die beim Entpacken den Speicher sprengen.
    static let maximumUncompressedSize: UInt64 = 20 * 1024 * 1024

    /// Entpackt einen XML-Eintrag mit Größenbegrenzung (auch während des Entpackens, falls die
    /// Größenangabe im Archiv gefälscht ist) und lehnt DOCTYPE-Deklarationen ab – OOXML verwendet
    /// keine, sie wären nur für Entity-Expansion („Billion Laughs“) nötig.
    private static func extractXML(_ entry: Entry, from archive: Archive, limit: UInt64) throws -> Data {
        guard UInt64(entry.uncompressedSize) <= limit else { throw XLSXImportError.tooLarge }
        var xml = Data()
        var exceeded = false
        _ = try archive.extract(entry) { chunk in
            guard !exceeded else { return }
            if UInt64(xml.count + chunk.count) > limit {
                exceeded = true
            } else {
                xml.append(chunk)
            }
        }
        if exceeded { throw XLSXImportError.tooLarge }
        if xml.range(of: Data("<!DOCTYPE".utf8)) != nil { throw XLSXImportError.unsupportedContent }
        return xml
    }

    private static func firstWorksheetEntry(in archive: Archive) -> Entry? {
        if let entry = archive["xl/worksheets/sheet1.xml"] { return entry }
        return archive
            .filter { $0.path.hasPrefix("xl/worksheets/sheet") && $0.path.hasSuffix(".xml") }
            .sorted { $0.path < $1.path }
            .first
    }

    private static func sharedStrings(in archive: Archive, limit: UInt64) throws -> [String] {
        guard let entry = archive["xl/sharedStrings.xml"] else { return [] }
        let xml = try extractXML(entry, from: archive, limit: limit)
        let delegate = SharedStringsXMLParserDelegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }
}

/// Liest `xl/sharedStrings.xml`: eine `<si>` je Zeichenkette, ggf. aus mehreren `<r><t>…</t></r>`-
/// Formatierungsläufen zusammengesetzt (z.B. bei teilweise fett gedrucktem Text).
private final class SharedStringsXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var strings: [String] = []
    private var currentString = ""
    private var isInText = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "si": currentString = ""
        case "t": isInText = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInText { currentString += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "t": isInText = false
        case "si": strings.append(currentString)
        default: break
        }
    }
}

/// Liest ein `sheetN.xml`: Zeilen (`<row>`) aus Zellen (`<c>`), anhand der Zellreferenz (z.B.
/// „C5") an der richtigen Spaltenposition eingefügt, damit leere Zwischenzellen (in OOXML meist
/// gar nicht erst vorhanden) die Spaltenausrichtung nicht verschieben.
private final class SheetXMLParserDelegate: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private(set) var rows: [[String]] = []

    private var currentRow: [String] = []
    private var currentCellType: String?
    private var currentCellColumnIndex = 0
    private var currentValueText = ""
    private var isCapturingText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            currentRow = []
        case "c":
            currentCellType = attributeDict["t"]
            currentCellColumnIndex = attributeDict["r"].map(Self.columnIndex) ?? currentRow.count
        case "v", "t":
            isCapturingText = true
            currentValueText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCapturingText { currentValueText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v", "t":
            isCapturingText = false
        case "c":
            while currentRow.count < currentCellColumnIndex { currentRow.append("") }
            currentRow.append(resolveCellValue())
            currentCellType = nil
            currentValueText = ""
        case "row":
            rows.append(currentRow)
        default:
            break
        }
    }

    private func resolveCellValue() -> String {
        switch currentCellType {
        case "s":
            guard let index = Int(currentValueText), sharedStrings.indices.contains(index) else { return "" }
            return sharedStrings[index]
        case "str", "inlineStr", "b", "e":
            return currentValueText
        default:
            // Keine Typangabe oder "n": numerischer Zellwert, von OOXML kulturunabhängig immer
            // mit Punkt als Dezimaltrennzeichen gespeichert (auch wenn Excel ihn mit deutschem
            // Komma anzeigt) – in deutsches Komma-Format umgewandelt, damit `LineItemRowParser`
            // ihn genauso wie einen CSV-Wert auswertet, statt die bereits eindeutige Punkt-Zahl
            // erneut heuristisch zu interpretieren.
            guard let number = Double(currentValueText) else { return currentValueText }
            return String(format: "%.4f", number).replacingOccurrences(of: ".", with: ",")
        }
    }

    private static func columnIndex(fromCellReference ref: String) -> Int {
        var index = 0
        for scalar in ref.unicodeScalars {
            guard scalar.value >= 65 && scalar.value <= 90 else { break }
            index = index * 26 + Int(scalar.value - 64)
        }
        return max(0, index - 1)
    }
}
