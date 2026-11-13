import Foundation
import UserNotifications

/// Dünner Wrapper um `UNUserNotificationCenter`: fordert bei Bedarf die Berechtigung an und
/// gleicht lokale Push-Benachrichtigungen mit den aktuellen `ReminderItem`s ab. Jeder Abgleich
/// entfernt zunächst alle zuvor von dieser App geplanten Benachrichtigungen und plant die
/// aktuellen neu (anhand ihrer stabilen `id`) – einfacher und genauso korrekt wie ein
/// selektives Diffing, da ohnehin bei jedem App-Start/Dashboard-Aufruf neu abgeglichen wird.
enum NotificationScheduler {
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Plant für jede Erinnerung mit `dueDate` eine Benachrichtigung am Vortag um 9 Uhr – ist
    /// der Vortag bereits erreicht/überschritten, wird stattdessen in Kürze benachrichtigt.
    /// Erinnerungen ohne `dueDate` (reine Dashboard-Hinweise ohne festen Termin) werden nicht
    /// als Push-Mitteilung geplant.
    static func sync(_ items: [ReminderItem]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        requests(for: items).forEach { center.add($0) }
    }

    /// Die zu planenden Benachrichtigungen – ohne Zugriff auf das System, daher testbar.
    static func requests(for items: [ReminderItem], now: Date = .now) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        return items.compactMap { item in
            guard let dueDate = item.dueDate else { return nil }
            let triggerDate = calendar.date(byAdding: .day, value: -1, to: dueDate) ?? dueDate

            let content = UNMutableNotificationContent()
            // Bewusst ohne Mieternamen, Einheit oder Beträge: Mitteilungen erscheinen je nach
            // Geräteeinstellung im Sperrbildschirm und auf der Apple Watch.
            content.title = item.title
            content.body = "Details in der Mietverwaltung ansehen."
            content.sound = .default

            let trigger: UNNotificationTrigger
            if triggerDate <= now {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            } else {
                var components = calendar.dateComponents([.year, .month, .day], from: triggerDate)
                components.hour = 9
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
            return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
        }
    }
}
