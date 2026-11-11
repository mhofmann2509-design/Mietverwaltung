import Foundation

/// Wandelt eine bereits in Spalten zerlegte Tabelle (Zeile = `[String]`-Spalten) in
/// `LineItemDraft`s um – gemeinsame Logik von `CSVImporter` und `XLSXImporter`, die sich nur in
/// der Art unterscheiden, wie sie aus ihrer jeweiligen Datei überhaupt erst eine solche
/// Spalten-Tabelle gewinnen.
///
/// Erwartete Spalten: Kostenart;Betrag;Umlagefähig;Umlageschlüssel – Spalte 3 und 4 sind optional
/// (Standard: umlagefähig, kein Umlageschlüssel). Eine Kopfzeile wird automatisch erkannt und
/// übersprungen.
enum LineItemRowParser {
    struct Result {
        var items: [LineItemDraft] = []
        /// 1-basierte Zeilennummern (inkl. Kopfzeile), die nicht gelesen werden konnten.
        var skippedRowNumbers: [Int] = []
    }

    static func lineItems(fromRows rows: [[String]]) -> [LineItemDraft] {
        parse(rows: rows).items
    }

    static func parse(rows: [[String]]) -> Result {
        var numbered = rows.enumerated()
            .map { (number: $0.offset + 1, cols: $0.element) }
            .filter { row in row.cols.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !numbered.isEmpty else { return Result() }

        // Kopfzeile erkennen: Wenn die zweite Spalte der ersten Zeile sich nicht als Betrag
        // lesen lässt, ist es vermutlich eine Überschriftenzeile und wird übersprungen.
        if let first = numbered.first?.cols, first.count > 1, parseAmount(first[1]) == nil {
            numbered.removeFirst()
        }

        var result = Result()
        for row in numbered {
            if let item = lineItem(from: row.cols) {
                result.items.append(item)
            } else {
                result.skippedRowNumbers.append(row.number)
            }
        }
        return result
    }

    private static func lineItem(from cols: [String]) -> LineItemDraft? {
            guard cols.count >= 2 else { return nil }
            let costType = cols[0].trimmingCharacters(in: .whitespaces)
            guard let amount = parseAmount(cols[1]), !costType.isEmpty else { return nil }

            var isApportionable = true
            if cols.count >= 3 {
                let flag = cols[2].lowercased()
                isApportionable = !["nein", "false", "0", "no"].contains(flag)
            }

            var allocationKey: String?
            if cols.count >= 4 {
                let value = cols[3].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { allocationKey = value }
            }

            return LineItemDraft(
                costType: costType,
                amountText: String(format: "%.2f", amount).replacingOccurrences(of: ".", with: ","),
                isApportionable: isApportionable,
                allocationKeyLabel: allocationKey
            )
    }

    static func parseAmount(_ raw: String) -> Double? {
        DecimalInputParser.parse(raw)
    }
}
