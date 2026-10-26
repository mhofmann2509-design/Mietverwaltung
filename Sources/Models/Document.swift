import Foundation
import SwiftData

@Model
final class Document {
    var title: String = ""
    var fileName: String = ""
    var fileExtension: String = ""
    @Attribute(.externalStorage) var data: Data = Data()
    var addedAt: Date = Date.now
    var receiptDate: Date = Date.now    // Belegdatum (Datum auf dem Beleg, für die Steuererklärung)

    var property: Property?
    var unit: Unit?
    var tenant: Tenant?
    var tenancy: Tenancy?
    var expense: Expense?
    var utilityStatement: UtilityStatement?
    var depreciableAsset: DepreciableAsset?

    init(title: String = "", fileName: String = "", fileExtension: String = "", data: Data = Data(), receiptDate: Date = .now) {
        self.title = title
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.data = data
        self.addedAt = .now
        self.receiptDate = receiptDate
    }

    /// Die Immobilie, der dieses Dokument zuzuordnen ist – direkt verknüpft oder abgeleitet über
    /// Einheit, Mietverhältnis, Ausgabe oder Nebenkostenabrechnung. Für die objektbezogene
    /// Gruppierung in der Dokumentenliste.
    var resolvedProperty: Property? {
        property
            ?? unit?.property
            ?? tenancy?.unit?.property
            ?? expense?.property
            ?? expense?.unit?.property
            ?? utilityStatement?.property
            ?? depreciableAsset?.property
    }

    /// Die Einheit (Wohnung), der dieses Dokument zuzuordnen ist – direkt verknüpft oder
    /// abgeleitet über Mietverhältnis oder Ausgabe. Für die wohnungsbezogene Gruppierung in der
    /// Dokumentenablage; `nil`, wenn das Dokument nur der Immobilie insgesamt zuzuordnen ist
    /// (z.B. eine Nebenkostenabrechnung oder ein objektweites Dokument).
    var resolvedUnit: Unit? {
        unit
            ?? tenancy?.unit
            ?? expense?.unit
    }

    /// Writes the document's data to a temporary file (named like the original) so it can be
    /// shared via `ShareLink`, which needs a `URL` rather than raw `Data`.
    var temporaryFileURL: URL? {
        let safeName = fileName.isEmpty ? "Dokument.\(fileExtension.isEmpty ? "dat" : fileExtension)" : fileName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// A human readable description of what this document is attached to.
    var linkedToDescription: String {
        if let tenancy, let unit = tenancy.unit {
            return "Mietvertrag · \(unit.name)"
        }
        if let unit {
            return "Einheit · \(unit.name)"
        }
        if let property {
            return "Immobilie · \(property.name)"
        }
        if let tenant {
            return "Mieter · \(tenant.fullName)"
        }
        if let expense {
            return "Ausgabe · \(expense.title)"
        }
        if let depreciableAsset {
            return "Wirtschaftsgut · \(depreciableAsset.name)"
        }
        if let utilityStatement {
            return "Nebenkostenabrechnung · \(utilityStatement.year)"
        }
        return "Nicht verknüpft"
    }
}
