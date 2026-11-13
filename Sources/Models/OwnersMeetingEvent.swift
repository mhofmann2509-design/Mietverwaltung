import Foundation
import SwiftData

/// Eine Eigentümerversammlung (WEG) für eine Immobilie: Die Einladung wird als Dokument
/// abgelegt (siehe `DocumentFolder`), zusätzlich wird ein Kalendereintrag mit Erinnerung
/// angelegt (siehe `CalendarEventManager`) – dessen Identifier steht in
/// `calendarEventIdentifier`.
@Model
final class OwnersMeetingEvent {
    var title: String = "Eigentümerversammlung"
    var date: Date = Date.now
    var location: String = ""
    var notes: String = ""
    var calendarEventIdentifier: String?

    var property: Property?
    var invitationDocument: Document?

    /// Version 2: in dieser Versammlung beschlossene Sonderumlagen.
    @Relationship(deleteRule: .nullify, inverse: \SpecialLevy.ownersMeeting)
    var specialLevies: [SpecialLevy]? = []

    init(title: String = "Eigentümerversammlung", date: Date = .now, location: String = "", notes: String = "") {
        self.title = title
        self.date = date
        self.location = location
        self.notes = notes
    }
}
