import Foundation

/// Erkennt Test-Läufe, damit die App dabei nie die echte (iCloud-)Datenbank öffnet.
enum LaunchEnvironment {
    /// Die App läuft als Host für die Unit-Tests (XCTest setzt diese Umgebungsvariable).
    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Die App wurde von den UI-Tests mit `-uiTesting` gestartet.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    static var usesInMemoryStore: Bool { isUnitTesting || isUITesting }
}
