import Foundation

enum LineItemFileImportError: LocalizedError {
    case undecodableText

    var errorDescription: String? {
        "Die Datei konnte nicht gelesen werden."
    }
}

/// Entscheidet anhand der Dateiendung zwischen `XLSXImporter` (echte .xlsx-Datei) und
/// `CSVImporter` (alles andere, als Text interpretiert) – gemeinsam genutzt von
/// `UtilityStatementEditView` und `WirtschaftsplanEditView`, die beide denselben
/// Kostenarten-Dateiimport anbieten.
enum LineItemFileImporter {
    static func parse(from url: URL, data: Data) throws -> LineItemRowParser.Result {
        if url.pathExtension.lowercased() == "xlsx" {
            return try XLSXImporter.parse(from: data)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw LineItemFileImportError.undecodableText
        }
        return CSVImporter.parse(from: text)
    }
}
