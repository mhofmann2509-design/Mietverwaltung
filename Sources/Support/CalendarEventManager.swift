import Foundation
import EventKit

/// Dünner Wrapper um `EKEventStore`: fordert bei Bedarf die Kalenderberechtigung an und legt für
/// eine `OwnersMeetingEvent` einen Kalendereintrag mit Erinnerung 3 Tage vorher an – das System
/// zeigt dafür über den `EKAlarm` automatisch eine Benachrichtigung, eine zusätzliche, separat
/// geplante Push-Mitteilung für denselben Termin wäre redundant.
enum CalendarEventManager {
    private static let store = EKEventStore()

    static func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Legt einen Kalendereintrag für die Eigentümerversammlung an oder aktualisiert ihn, falls
    /// `existingIdentifier` noch einen gültigen Eintrag referenziert, und liefert dessen
    /// `eventIdentifier` zum Speichern in `OwnersMeetingEvent.calendarEventIdentifier`.
    static func upsertEvent(title: String, date: Date, location: String, notes: String, existingIdentifier: String?) -> String? {
        let event: EKEvent
        if let existingIdentifier, let existing = store.event(withIdentifier: existingIdentifier) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first
        }

        configure(event, title: title, date: date, location: location, notes: notes)

        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// Termin von 2 Stunden mit Erinnerung 3 Tage vorher – ohne Kalenderzugriff testbar.
    static func configure(_ event: EKEvent, title: String, date: Date, location: String, notes: String) {
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(2 * 3600)
        event.location = location
        event.notes = notes
        event.alarms = [EKAlarm(relativeOffset: -3 * 24 * 3600)]
    }

    static func removeEvent(identifier: String) {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent)
    }
}
