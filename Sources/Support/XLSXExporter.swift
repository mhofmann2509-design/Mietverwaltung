import Foundation

/// Erzeugt eine echte, in Excel direkt öffenbare `.xlsx`-Datei (Office Open XML), ganz ohne
/// Drittanbieter-Bibliothek: ein minimaler, unkomprimierter ZIP-Container (Methode „Store“) mit
/// den nötigen OOXML-Teilen (Workbook + ein Arbeitsblatt je `Sheet`). Bewusst ohne Komprimierung,
/// da die hier erzeugten Tabellen klein sind und Store deutlich einfacher und robuster ist als ein
/// eigener Deflate-Encoder.
enum XLSXExporter {
    enum CellValue {
        case string(String)
        case number(Double)
        /// Zahl mit Währungsformat (zeigt „€“, respektiert das Dezimaltrennzeichen von Excel/macOS).
        case currency(Double)
        case bold(String)
    }

    struct Sheet {
        let name: String
        /// Jede Zeile ist eine Liste von Zellwerten, in Spaltenreihenfolge.
        let rows: [[CellValue]]

        init(name: String, headers: [String], rows: [[CellValue]]) {
            self.name = name
            self.rows = [headers.map { .bold($0) }] + rows
        }
    }

    /// Baut die `.xlsx`-Datei aus einem oder mehreren Arbeitsblättern.
    static func data(sheets: [Sheet]) -> Data? {
        guard !sheets.isEmpty else { return nil }

        var entries: [(path: String, data: Data)] = []
        entries.append((path: "[Content_Types].xml", data: Data(contentTypesXML(sheetCount: sheets.count).utf8)))
        entries.append((path: "_rels/.rels", data: Data(rootRelsXML.utf8)))
        entries.append((path: "xl/workbook.xml", data: Data(workbookXML(sheets: sheets).utf8)))
        entries.append((path: "xl/_rels/workbook.xml.rels", data: Data(workbookRelsXML(sheetCount: sheets.count).utf8)))
        entries.append((path: "xl/styles.xml", data: Data(stylesXML.utf8)))
        for (index, sheet) in sheets.enumerated() {
            entries.append((path: "xl/worksheets/sheet\(index + 1).xml", data: Data(worksheetXML(sheet: sheet).utf8)))
        }

        return ZipArchiveWriter.data(entries: entries)
    }

    // MARK: - OOXML-Teile

    private static func contentTypesXML(sheetCount: Int) -> String {
        var overrides = ""
        for index in 1...sheetCount {
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        \(overrides)
        </Types>
        """
    }

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static func workbookXML(sheets: [Sheet]) -> String {
        var sheetEntries = ""
        for (index, sheet) in sheets.enumerated() {
            sheetEntries += "<sheet name=\"\(xmlEscape(sheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>\(sheetEntries)</sheets>
        </workbook>
        """
    }

    private static func workbookRelsXML(sheetCount: Int) -> String {
        var relEntries = ""
        for index in 1...sheetCount {
            relEntries += "<Relationship Id=\"rId\(index)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index).xml\"/>"
        }
        let stylesRelId = sheetCount + 1
        relEntries += "<Relationship Id=\"rId\(stylesRelId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(relEntries)
        </Relationships>
        """
    }

    /// Drei Formate: 0 = Standard, 1 = Fett (Überschriften), 2 = Währung (€, 2 Nachkommastellen).
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00&quot; €&quot;"/></numFmts>
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
    <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    </cellXfs>
    </styleSheet>
    """

    private static func worksheetXML(sheet: Sheet) -> String {
        var rowsXML = ""
        for (rowIndex, row) in sheet.rows.enumerated() {
            let rowNumber = rowIndex + 1
            var cellsXML = ""
            for (columnIndex, value) in row.enumerated() {
                let reference = "\(columnLetter(for: columnIndex))\(rowNumber)"
                switch value {
                case .string(let text):
                    cellsXML += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(text))</t></is></c>"
                case .bold(let text):
                    cellsXML += "<c r=\"\(reference)\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">\(xmlEscape(text))</t></is></c>"
                case .number(let number):
                    cellsXML += "<c r=\"\(reference)\"><v>\(number)</v></c>"
                case .currency(let number):
                    cellsXML += "<c r=\"\(reference)\" s=\"2\"><v>\(number)</v></c>"
                }
            }
            rowsXML += "<row r=\"\(rowNumber)\">\(cellsXML)</row>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(rowsXML)</sheetData>
        </worksheet>
        """
    }

    /// Spaltenbuchstabe für einen 0-basierten Spaltenindex (0 → A, 25 → Z, 26 → AA, …).
    private static func columnLetter(for index: Int) -> String {
        var result = ""
        var value = index
        repeat {
            let remainder = value % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            value = value / 26 - 1
        } while value >= 0
        return result
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Minimaler ZIP-Writer (nur Methode „Store“, also unkomprimiert) – ausreichend für die kleinen,
/// selbst erzeugten OOXML-Teile einer `.xlsx`-Datei.
private enum ZipArchiveWriter {
    static func data(entries: [(path: String, data: Data)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var localHeaderOffsets: [UInt32] = []

        for entry in entries {
            localHeaderOffsets.append(UInt32(archive.count))
            let nameData = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            archive.appendUInt32LE(0x04034b50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(crc)
            archive.appendUInt32LE(size)
            archive.appendUInt32LE(size)
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(entry.data)
        }

        for (index, entry) in entries.enumerated() {
            let nameData = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(size)
            centralDirectory.appendUInt32LE(size)
            centralDirectory.appendUInt16LE(UInt16(nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(localHeaderOffsets[index])
            centralDirectory.append(nameData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        archive.appendUInt32LE(0x06054b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt32LE(UInt32(centralDirectory.count))
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)

        return archive
    }

    private static let crcTable: [UInt32] = {
        (0...255).map { index -> UInt32 in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1 != 0) ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
            }
            return crc
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
