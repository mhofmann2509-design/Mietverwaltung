import Foundation

/// Liest eine Kostenarten-Liste aus einer CSV-Datei ein (z.B. aus Excel, Numbers oder Google
/// Sheets exportiert über „Datei > Exportieren/Speichern unter > CSV“). Eine echte .xlsx-Datei
/// kann ohne Zusatzbibliothek nicht gelesen werden – in diesem Fall bitte zuerst als CSV
/// exportieren; die App weist im Import-Dialog darauf hin.
///
/// Erwartete Spalten (Semikolon oder Komma getrennt): Kostenart;Betrag;Umlagefähig;Umlageschlüssel
/// Spalte 3 und 4 sind optional (Standard: umlagefähig, kein Umlageschlüssel). Eine Kopfzeile
/// wird automatisch erkannt und übersprungen.
enum CSVImporter {
    static func parseLineItems(from text: String) -> [LineItemDraft] {
        var rows = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rows.isEmpty else { return [] }

        let delimiter: Character = rows[0].contains(";") ? ";" : ","

        func columns(_ row: String) -> [String] {
            row.split(separator: delimiter, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        }

        // Kopfzeile erkennen: Wenn die zweite Spalte der ersten Zeile sich nicht als Betrag
        // lesen lässt, ist es vermutlich eine Überschriftenzeile und wird übersprungen.
        if let firstColumns = rows.first.map(columns), firstColumns.count > 1, parseAmount(firstColumns[1]) == nil {
            rows.removeFirst()
        }

        return rows.compactMap { row -> LineItemDraft? in
            let cols = columns(row)
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
    }

    private static func parseAmount(_ raw: String) -> Double? {
        var value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.contains(",") {
            // Deutsches Format: "." ist Tausendertrenner, "," ist Dezimaltrennzeichen.
            value = value.replacingOccurrences(of: ".", with: "")
            value = value.replacingOccurrences(of: ",", with: ".")
        } else if let lastDot = value.lastIndex(of: "."), value.distance(from: lastDot, to: value.endIndex) == 4 {
            // Kein Komma, aber ein Punkt mit genau drei Nachkommastellen: für einen Geldbetrag kein
            // Dezimaltrennzeichen (Cent-Beträge haben höchstens zwei Nachkommastellen), sondern ein
            // deutscher Tausendertrenner ohne angegebene Cent-Stellen (z.B. "1.234" = 1.234 €, nicht
            // 1,234 €) – sonst würde ein solcher Betrag um den Faktor 1000 zu klein eingelesen.
            value = value.replacingOccurrences(of: ".", with: "")
        }
        return Double(value)
    }
}
