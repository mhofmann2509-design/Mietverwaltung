import Foundation

/// Einheitliches Einlesen von Zahlen aus Freitext (Formularfelder, CSV/XLSX, OCR).
///
/// Regeln: Kommen "," und "." beide vor, ist das weiter rechts stehende Zeichen das
/// Dezimaltrennzeichen und das andere ein Tausendertrenner ("1.234,56" und "1,234.56" ergeben
/// beide 1234,56). Ein einzelnes Komma ist immer Dezimalkomma ("3,125" = 3,125). Ein einzelner
/// Punkt gilt nur dann als Tausendertrenner, wenn genau drei Ziffern folgen ("1.234" = 1234),
/// sonst als Dezimalpunkt ("12.5"). Mehrfach vorkommende Trenner sind immer Tausendertrenner.
enum DecimalInputParser {
    static func parse(_ raw: String) -> Double? {
        let ignored = CharacterSet(charactersIn: "€%").union(.whitespacesAndNewlines)
        var value = String(raw.unicodeScalars.filter { !ignored.contains($0) })
        guard !value.isEmpty else { return nil }

        let lastComma = value.lastIndex(of: ",")
        let lastDot = value.lastIndex(of: ".")

        if let lastComma, let lastDot {
            let decimal: Character = lastComma > lastDot ? "," : "."
            let grouping: Character = decimal == "," ? "." : ","
            value.removeAll { $0 == grouping }
            guard value.filter({ $0 == decimal }).count == 1 else { return nil }
            value = value.replacingOccurrences(of: String(decimal), with: ".")
        } else if let separatorIndex = lastComma ?? lastDot {
            let separator = value[separatorIndex]
            let occurrences = value.filter { $0 == separator }.count
            let digitsAfter = value.distance(from: separatorIndex, to: value.endIndex) - 1
            if occurrences > 1 || (separator == "." && digitsAfter == 3) {
                value.removeAll { $0 == separator }
            } else {
                value = value.replacingOccurrences(of: String(separator), with: ".")
            }
        }

        guard let result = Double(value), result.isFinite else { return nil }
        return result
    }

    /// `true`, wenn das Feld etwas enthält, das sich nicht als Zahl lesen lässt – leere Felder
    /// gelten als gültig (optional), damit Formulare zwischen „leer“ und „unlesbar“ unterscheiden.
    static func isUnparsable(_ raw: String) -> Bool {
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parse(raw) == nil
    }
}

extension String {
    /// Siehe `DecimalInputParser.parse(_:)`.
    var parsedDecimal: Double? { DecimalInputParser.parse(self) }
}
