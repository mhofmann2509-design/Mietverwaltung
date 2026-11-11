import Foundation

/// Aus einem eingescannten Kassenbon oder einer Rechnung heuristisch erkannte Angaben – zur
/// Kontrolle und Vervollständigung durch den Nutzer gedacht, siehe `ReceiptScanReviewView`.
/// Läuft wie `PropertyDocumentOCR` vollständig lokal auf dem Gerät.
struct ReceiptScanResult: Identifiable {
    let id = UUID()
    var date: Date?
    var amount: Double?
    /// Vorschlag für die Bezeichnung, meist die erste erkannte Zeile (häufig Händler-/Firmenname).
    var vendor: String?
}

enum ReceiptOCR {
    static func recognize(from data: Data) -> ReceiptScanResult {
        let rows = OCRTextRecognizer.recognizeRows(from: data)
        var result = ReceiptScanResult()

        if let firstRow = rows.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            result.vendor = firstRow.trimmingCharacters(in: .whitespaces)
        }

        for row in rows {
            let lower = row.lowercased()

            if result.date == nil, let date = PropertyDocumentOCR.firstDate(in: row) {
                result.date = date
            }

            if lower.contains("summe") || lower.contains("gesamt") || lower.contains("betrag") || lower.contains("total") || lower.contains("zu zahlen") {
                // Spätere Treffer überschreiben frühere bewusst: bei mehreren "Summe"-Zeilen
                // (z.B. Zwischensumme, dann Gesamtsumme) steht der tatsächliche Endbetrag meist
                // weiter unten im Beleg.
                if let amount = PropertyDocumentOCR.firstNumber(in: row) {
                    result.amount = amount
                }
            }
        }

        if result.amount == nil {
            result.amount = rows.compactMap { PropertyDocumentOCR.firstNumber(in: $0) }.max()
        }

        return result
    }

    /// Erkennt Kostenarten-Zeilen aus einem eingescannten WEG-Beleg (Wirtschaftsplan oder
    /// Jahresabrechnung): je Zeile mit einem glaubwürdigen Geldbetrag am Zeilenende wird die
    /// vorangestellte Bezeichnung als Kostenart übernommen. Zusammenfassungs-/Kopfzeilen
    /// (Summe, Seite, Objekt, …) werden ausgeklammert. Zur Kontrolle/Vervollständigung durch den
    /// Nutzer gedacht, siehe `LineItemImportReviewView` – keine Zeile wird automatisch übernommen.
    static func recognizeLineItems(from data: Data) -> [LineItemDraft] {
        let rows = OCRTextRecognizer.recognizeRows(from: data)
        let skipKeywords = ["summe", "gesamt", "zwischensumme", "seite", "objekt", "abrechnung", "wirtschaftsplan", "hausgeld", "zeitraum", "insgesamt", "saldo"]

        var drafts: [LineItemDraft] = []
        for row in rows {
            let lower = row.lowercased()
            guard !skipKeywords.contains(where: lower.contains) else { continue }
            guard let amount = lastMonetaryAmount(in: row), amount > 0 else { continue }
            let costType = strippingTrailingAmount(from: row).trimmingCharacters(in: .whitespaces)
            guard !costType.isEmpty else { continue }

            drafts.append(LineItemDraft(
                costType: costType,
                amountText: String(format: "%.2f", amount).replacingOccurrences(of: ".", with: ","),
                isApportionable: true,
                allocationKeyLabel: nil
            ))
        }
        return drafts
    }

    /// Letzter glaubwürdiger Geldbetrag (mit Komma-Nachkommastellen) in einer Zeile – bewusst der
    /// letzte statt der erste Treffer, da Kostenarten-Zeilen typischerweise mit dem Betrag enden
    /// (z.B. „Heizung 1.450,00“), während eine vierstellige Jahreszahl am Zeilenanfang sonst
    /// fälschlich als Betrag erkannt würde.
    private static func lastMonetaryAmount(in text: String) -> Double? {
        let pattern = #"[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard let last = matches.last else { return nil }
        let raw = nsText.substring(with: last.range)
        return raw.parsedDecimal
    }

    private static func strippingTrailingAmount(from text: String) -> String {
        let pattern = #"[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2}\s*€?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, range: range) else { return text }
        return nsText.replacingCharacters(in: match.range, with: "")
    }
}
