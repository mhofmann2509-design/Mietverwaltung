import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// Ablage für Dateien, die nur zum Teilen/Anzeigen erzeugt werden (PDF-/Excel-Exporte, Vorschauen).
/// Exporte enthalten Mieter-, Adress- und Steuerdaten – deshalb liegen sie in einem eigenen
/// Unterordner, der beim App-Start vollständig und bei jedem neuen Export von Dateien älter als
/// eine Stunde bereinigt wird, statt sich unbegrenzt im temporären Verzeichnis anzusammeln.
enum ExportFileStore {
    static let maximumAge: TimeInterval = 60 * 60

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exporte", isDirectory: true)
    }

    static func write(_ data: Data, fileName: String) throws -> URL {
        purge(olderThan: maximumAge)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = fileName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent(safeName.isEmpty ? "Export" : safeName)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Entfernt Export-Dateien, die frühere App-Versionen direkt ins temporäre Verzeichnis
    /// geschrieben und nie gelöscht haben. Unterordner (z.B. vom System) bleiben unberührt.
    static func purgeLegacyExports() {
        let fileManager = FileManager.default
        let legacyExtensions: Set<String> = ["pdf", "xlsx", "jpg", "jpeg", "png", "heic"]
        guard let files = try? fileManager.contentsOfDirectory(at: fileManager.temporaryDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for file in files where legacyExtensions.contains(file.pathExtension.lowercased()) {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    /// Entfernt Exporte, die älter als `age` sind – mit `age = 0` alle.
    static func purge(olderThan age: TimeInterval = 0) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date.now.addingTimeInterval(-age)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if age == 0 || modified < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

/// Ein Export für `ShareLink`, dessen Datei erst erzeugt wird, wenn tatsächlich geteilt wird –
/// statt bei jedem Neuzeichnen der View (z.B. bei jedem Tastendruck in der Suche) ein PDF zu
/// rendern und auf die Platte zu schreiben. So ist der geteilte Inhalt zudem immer aktuell.
struct ExportFile: Transferable {
    enum ExportError: LocalizedError {
        case notCreated
        var errorDescription: String? { "Die Exportdatei konnte nicht erstellt werden." }
    }

    let title: String
    let contentType: UTType
    let makeURL: @MainActor () -> URL?

    static let xlsx = UTType(filenameExtension: "xlsx") ?? .data

    static func pdf(_ title: String, _ makeURL: @escaping @MainActor () -> URL?) -> ExportFile {
        ExportFile(title: title, contentType: .pdf, makeURL: makeURL)
    }

    static func spreadsheet(_ title: String, _ makeURL: @escaping @MainActor () -> URL?) -> ExportFile {
        ExportFile(title: title, contentType: xlsx, makeURL: makeURL)
    }

    /// Ein gespeichertes Dokument (PDF, Foto, beliebige Datei) – Typ aus der Dateiendung.
    static func document(_ document: Document) -> ExportFile {
        let type = UTType(filenameExtension: document.fileExtension) ?? .data
        return ExportFile(title: document.title.isEmpty ? document.fileName : document.title, contentType: type) { document.temporaryFileURL }
    }

    var preview: SharePreview<Never, Never> { SharePreview(title) }

    private static let specificTypes: [UTType] = [.pdf, xlsx, .jpeg, .png, .heic]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf, exporting: export)
            .exportingCondition { $0.contentType == .pdf }
        FileRepresentation(exportedContentType: xlsx, exporting: export)
            .exportingCondition { $0.contentType == xlsx }
        FileRepresentation(exportedContentType: .jpeg, exporting: export)
            .exportingCondition { $0.contentType == .jpeg }
        FileRepresentation(exportedContentType: .png, exporting: export)
            .exportingCondition { $0.contentType == .png }
        FileRepresentation(exportedContentType: .heic, exporting: export)
            .exportingCondition { $0.contentType == .heic }
        FileRepresentation(exportedContentType: .data, exporting: export)
            .exportingCondition { !specificTypes.contains($0.contentType) }
    }

    @Sendable private static func export(_ file: ExportFile) async throws -> SentTransferredFile {
        guard let url = await MainActor.run(body: { file.makeURL() }) else { throw ExportError.notCreated }
        return SentTransferredFile(url)
    }
}

/// `ShareLink` für einen `ExportFile`, z.B. `ExportShareLink("Als PDF teilen", pdf: reportURL)`.
struct ExportShareLink: View {
    private let title: String
    private let file: ExportFile

    init(_ title: String, pdf makeURL: @escaping @MainActor () -> URL?) {
        self.title = title
        self.file = .pdf(title, makeURL)
    }

    init(_ title: String, spreadsheet makeURL: @escaping @MainActor () -> URL?) {
        self.title = title
        self.file = .spreadsheet(title, makeURL)
    }

    var body: some View {
        #if os(iOS)
        Button {
            if let url = file.makeURL() { SharePresenter.present([url]) }
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
        }
        #else
        ShareLink(title, item: file, preview: file.preview)
        #endif
    }
}

#if os(iOS)
/// Öffnet das iOS-Teilen-Menü selbst, verankert an der obersten sichtbaren Ansicht. Nötig für
/// Teilen-Aktionen in Menüs und Wisch-Aktionen: Ein `ShareLink` dort verankert seinen Dialog am
/// Menüeintrag, der beim Öffnen schon verschwunden ist – iOS bricht dann mit „UIPopover-
/// PresentationController … should have a non-nil sourceView“ ab.
enum SharePresenter {
    @MainActor
    static func present(_ items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.keyWindow,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
#endif
