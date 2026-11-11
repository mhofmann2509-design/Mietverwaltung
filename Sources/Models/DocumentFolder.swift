import Foundation
import SwiftData

/// Die drei Reiter der neu gegliederten Dokumentenablage je Immobilie – siehe `ContentView`s
/// Seitenleiste und `DocumentCategoryView`. `rawValue` ist eine stabile, persistierte Kennung;
/// die angezeigte Bezeichnung steht in `label`, damit eine spätere Umbenennung keine
/// gespeicherten Daten bricht.
enum DocumentCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case propertyDocuments
    case invoicesReceipts
    case utilityStatements

    var id: String { rawValue }

    var label: String {
        switch self {
        case .propertyDocuments: return "Immobiliendokumente"
        case .invoicesReceipts: return "Rechnungen & Belege"
        case .utilityStatements: return "Nebenkostenabrechnungen"
        }
    }

    var systemImage: String {
        switch self {
        case .propertyDocuments: return "building.columns"
        case .invoicesReceipts: return "receipt"
        case .utilityStatements: return "doc.text"
        }
    }
}

/// Ein vom Nutzer frei angelegter, umbenennbarer Unterordner innerhalb eines `DocumentCategory`-
/// Reiters einer Immobilie (z.B. „2024“ oder „Handwerker Müller“ unter Rechnungen & Belege). Rein
/// organisatorisch – hat keinen Einfluss auf Berechnungen oder Verknüpfungen der enthaltenen
/// `Document`s.
@Model
final class DocumentFolder {
    var name: String = ""
    var categoryRaw: String = DocumentCategory.propertyDocuments.rawValue
    var createdAt: Date = Date.now

    var property: Property?

    @Relationship(deleteRule: .nullify, inverse: \Document.folder)
    var documents: [Document]? = []

    init(name: String = "", category: DocumentCategory = .propertyDocuments) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.createdAt = .now
    }

    var category: DocumentCategory {
        get { DocumentCategory(rawValue: categoryRaw) ?? .propertyDocuments }
        set { categoryRaw = newValue.rawValue }
    }
}
