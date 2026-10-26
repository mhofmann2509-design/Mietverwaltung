import Foundation

/// Aus einer eingescannten Teilungserklärung (oder einem ähnlichen Dokument, z.B. Kaufvertrag)
/// heuristisch erkannte Angaben – zur Kontrolle und Vervollständigung durch den Nutzer gedacht,
/// siehe `PropertyDocumentScanReviewView`.
struct PropertyScanResult: Identifiable {
    let id = UUID()
    var totalAreaSquareMeters: Double?
    var location: String?
    var coOwnershipShare: Double?
    var purchasePrice: Double?
    var furnitureLabel: String?
    var furniturePrice: Double?
}

/// Erkennt typische Angaben aus einer eingescannten Teilungserklärung per Texterkennung:
/// Wohn-/Gesamtfläche, Lage/Bezeichnung der Einheit, Miteigentumsanteil (MEA), Kaufpreis und –
/// falls im Dokument genannt – den Preis mitverkaufter Möblierung (z.B. Einbauküche).
/// Läuft vollständig lokal auf dem Gerät (Vision-Framework über `OCRTextRecognizer`).
enum PropertyDocumentOCR {
    static func recognize(from data: Data) -> PropertyScanResult {
        let rows = OCRTextRecognizer.recognizeRows(from: data)
        var result = PropertyScanResult()

        for row in rows {
            let lower = row.lowercased()

            if result.totalAreaSquareMeters == nil,
               lower.contains("wohnfläche") || lower.contains("gesamtfläche") || lower.contains("wohn- und nutzfläche") {
                result.totalAreaSquareMeters = firstNumber(in: row)
            }

            if result.coOwnershipShare == nil,
               lower.contains("miteigentumsanteil") || lower.contains("mea") {
                result.coOwnershipShare = firstNumber(in: row)
            }

            if result.purchasePrice == nil,
               lower.contains("kaufpreis") || lower.contains("kaufsumme") {
                result.purchasePrice = firstNumber(in: row)
            }

            if result.furniturePrice == nil,
               lower.contains("küche") || lower.contains("einbauküche") || lower.contains("möbliert") || lower.contains("möbel") {
                if let price = firstNumber(in: row) {
                    result.furniturePrice = price
                    result.furnitureLabel = lower.contains("küche") ? "Einbauküche" : "Möblierung"
                }
            }

            if result.location == nil,
               lower.contains("lage") || lower.contains("obergeschoss") || lower.contains("erdgeschoss") || lower.contains("wohnung nr") {
                let cleaned = stripLeadingLabel(row).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { result.location = cleaned }
            }
        }

        return result
    }

    /// Entfernt ein vorangestelltes Feld-Label samt Doppelpunkt, z.B. „Lage: “ in „Lage: 2. OG links“.
    private static func stripLeadingLabel(_ text: String) -> String {
        guard let colonIndex = text.firstIndex(of: ":") else { return text }
        return String(text[text.index(after: colonIndex)...])
    }

    /// Erste Zahl in einem Text, deutsches Format („68,00“, „100.000,00“) oder einfache Ganzzahl.
    static func firstNumber(in text: String) -> Double? {
        let pattern = #"[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{1,2}|[0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        let raw = nsText.substring(with: match.range)
        let normalized = raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    /// Erstes Datum im Format TT.MM.JJJJ (auch mit ein-/zweistelligem Tag/Monat) in einem Text.
    static func firstDate(in text: String) -> Date? {
        let pattern = #"([0-3]?[0-9])\.([0-1]?[0-9])\.([0-9]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)), match.numberOfRanges == 4 else { return nil }
        guard let day = Int(nsText.substring(with: match.range(at: 1))),
              let month = Int(nsText.substring(with: match.range(at: 2))),
              let year = Int(nsText.substring(with: match.range(at: 3))) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// Aus einem eingescannten Kaufvertrag heuristisch erkannte Angaben – eigenständig von
/// `PropertyScanResult` (Teilungserklärung), da andere Felder relevant sind. Dient wie dort nur
/// zur Kontrolle und Vervollständigung durch den Nutzer, siehe `PropertyPurchaseContractScanReviewView`.
struct PurchaseContractScanResult: Identifiable {
    let id = UUID()
    var purchaseDate: Date?
    var economicTransferDate: Date?
    var purchasePrice: Double?
    /// Nur gesetzt, wenn der Vertrag die Aufteilung explizit beziffert (selten) – die App
    /// übernimmt nie eine erfundene Aufteilung.
    var landValue: Double?

    var isEmpty: Bool {
        purchaseDate == nil && economicTransferDate == nil && purchasePrice == nil && landValue == nil
    }
}

/// Erkennt typische Angaben aus einem eingescannten Kaufvertrag: Beurkundungsdatum, Übergang von
/// Besitz/Nutzen/Lasten, Kaufpreis und – falls explizit beziffert – die Aufteilung auf Grund und
/// Boden. Läuft wie `PropertyDocumentOCR.recognize` vollständig lokal auf dem Gerät.
enum PurchaseContractOCR {
    static func recognize(from data: Data) -> PurchaseContractScanResult {
        let rows = OCRTextRecognizer.recognizeRows(from: data)
        var result = PurchaseContractScanResult()

        for row in rows {
            let lower = row.lowercased()

            if result.purchaseDate == nil,
               lower.contains("beurkundet") || lower.contains("kaufvertrag vom") || lower.contains("vertrag vom") {
                result.purchaseDate = PropertyDocumentOCR.firstDate(in: row)
            }

            if result.economicTransferDate == nil,
               lower.contains("besitz") && (lower.contains("nutzen") || lower.contains("lasten") || lower.contains("übergang")) {
                result.economicTransferDate = PropertyDocumentOCR.firstDate(in: row)
            }

            if result.purchasePrice == nil,
               lower.contains("kaufpreis") || lower.contains("kaufsumme") {
                result.purchasePrice = PropertyDocumentOCR.firstNumber(in: row)
            }

            if result.landValue == nil,
               lower.contains("grund und boden") || lower.contains("bodenwert") || lower.contains("grundstücksanteil") {
                result.landValue = PropertyDocumentOCR.firstNumber(in: row)
            }
        }

        return result
    }
}
