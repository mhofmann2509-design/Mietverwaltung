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

    /// Reiter der Dokumentenablage, dem dieses Dokument zugeordnet ist – `nil`, solange nicht
    /// explizit gesetzt, dann aus den Verknüpfungen abgeleitet (siehe `category`). Für Dokumente,
    /// die vor Einführung der Reiter-Gliederung angelegt wurden, ergibt sich dadurch automatisch
    /// eine sinnvolle Zuordnung, ohne eine Datenmigration zu benötigen.
    var categoryRaw: String?
    /// Vom Nutzer frei angelegter Unterordner innerhalb des Reiters – optional, unabhängig von
    /// `categoryRaw` (ein Dokument kann einem Ordner zugeordnet sein, dessen eigene Kategorie dann
    /// maßgeblich ist, siehe `category`).
    var folder: DocumentFolder?

    @Relationship(deleteRule: .nullify, inverse: \OwnersMeetingEvent.invitationDocument)
    var ownersMeetingInvitations: [OwnersMeetingEvent]? = []

    @Relationship(deleteRule: .nullify, inverse: \TaxChecklistItem.linkedDocument)
    var linkedChecklistItems: [TaxChecklistItem]? = []

    init(title: String = "", fileName: String = "", fileExtension: String = "", data: Data = Data(), receiptDate: Date = .now) {
        self.title = title
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.data = data
        self.addedAt = .now
        self.receiptDate = receiptDate
    }

    /// Reiter der Dokumentenablage: explizit gesetzter Wert, sonst der Ordner-Reiter (falls einem
    /// Ordner zugeordnet), sonst aus den Verknüpfungen abgeleitet (Nebenkostenabrechnung →
    /// Nebenkostenabrechnungen; Ausgabe/Wirtschaftsgut → Rechnungen & Belege; sonst
    /// Immobiliendokumente).
    var category: DocumentCategory {
        get {
            if let categoryRaw, let explicit = DocumentCategory(rawValue: categoryRaw) { return explicit }
            if let folder { return folder.category }
            if utilityStatement != nil { return .utilityStatements }
            if expense != nil || depreciableAsset != nil { return .invoicesReceipts }
            return .propertyDocuments
        }
        set { categoryRaw = newValue.rawValue }
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

    /// Writes the document's data to a temporary file (named like the original) so it can be
    /// shared via `ShareLink`, which needs a `URL` rather than raw `Data`.
    var temporaryFileURL: URL? {
        let safeName = fileName.isEmpty ? "Dokument.\(fileExtension.isEmpty ? "dat" : fileExtension)" : fileName
        return try? ExportFileStore.write(data, fileName: safeName)
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
