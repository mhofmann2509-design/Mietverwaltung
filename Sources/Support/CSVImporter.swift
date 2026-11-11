import Foundation

/// Liest eine Kostenarten-Liste aus einer CSV-Datei ein (z.B. aus Excel, Numbers oder Google
/// Sheets exportiert über „Datei > Exportieren/Speichern unter > CSV"). Für eine echte .xlsx-Datei
/// siehe `XLSXImporter`.
///
/// Erwartete Spalten (Semikolon oder Komma getrennt): Kostenart;Betrag;Umlagefähig;Umlageschlüssel
/// Spalte 3 und 4 sind optional (Standard: umlagefähig, kein Umlageschlüssel). Eine Kopfzeile
/// wird automatisch erkannt und übersprungen (siehe `LineItemRowParser`, gemeinsam mit `XLSXImporter`).
enum CSVImporter {
    static func parseLineItems(from text: String) -> [LineItemDraft] {
        parse(from: text).items
    }

    static func parse(from text: String) -> LineItemRowParser.Result {
        let rows = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rows.isEmpty else { return LineItemRowParser.Result() }

        let delimiter: Character = rows[0].contains(";") ? ";" : ","

        func columns(_ row: String) -> [String] {
            row.split(separator: delimiter, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        }

        return LineItemRowParser.parse(rows: rows.map(columns))
    }
}
