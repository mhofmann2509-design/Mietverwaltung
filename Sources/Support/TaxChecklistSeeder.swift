import Foundation
import SwiftData

/// Legt beim ersten Öffnen des Steuermoduls für eine Immobilie (bzw. ein Steuerjahr) die
/// Checklisten-Vorlagen aus `TaxChecklistTemplate` an – idempotent über `templateKey`, überschreibt
/// nie den Status eines bereits vorhandenen Eintrags.
@MainActor
enum TaxChecklistSeeder {
    static func ensureSeeded(for property: Property, taxYear: Int, context: ModelContext) {
        let existingKeys = Set((property.taxChecklistItems ?? []).map { "\($0.templateKey)|\($0.taxYear.map(String.init) ?? "")" })

        for entry in TaxChecklistTemplate.initialSetupEntries {
            let key = "\(entry.key)|"
            guard !existingKeys.contains(key) else { continue }
            let item = TaxChecklistItem(title: entry.title, itemDescription: entry.description, mode: .initialSetup, taxYear: nil, templateKey: entry.key)
            item.property = property
            context.insert(item)
        }

        for entry in TaxChecklistTemplate.ongoingEntries {
            let key = "\(entry.key)|\(taxYear)"
            guard !existingKeys.contains(key) else { continue }
            let item = TaxChecklistItem(title: entry.title, itemDescription: entry.description, mode: .ongoing, taxYear: taxYear, templateKey: entry.key)
            item.property = property
            context.insert(item)
        }
    }
}
