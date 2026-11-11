import SwiftUI

enum BackgroundWork {
    /// Führt reine Rechenarbeit ohne SwiftData-Zugriff (z.B. Texterkennung) abseits des
    /// Hauptthreads aus, damit die Oberfläche währenddessen reagiert.
    static func run<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }
}

extension View {
    /// Blendet eine Fortschrittsanzeige über die View und sperrt Eingaben, solange `message` gesetzt ist.
    func busyOverlay(_ message: String?) -> some View {
        overlay {
            if let message {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView(message)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
