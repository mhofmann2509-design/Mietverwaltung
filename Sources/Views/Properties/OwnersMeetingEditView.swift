import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Anlegen/Bearbeiten einer Eigentümerversammlung: Die hochgeladene Einladung wird als
/// `Document` im Ordner „Eigentümerversammlungen“ der Immobilie abgelegt, zusätzlich wird ein
/// Kalendereintrag mit Erinnerung 3 Tage vorher angelegt (siehe `CalendarEventManager`).
struct OwnersMeetingEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let property: Property
    let meeting: OwnersMeetingEvent?

    @State private var title = "Eigentümerversammlung"
    @State private var date = Date.now
    @State private var location = ""
    @State private var notes = ""
    @State private var pickedFileURL: URL?
    @State private var showingFileImporter = false
    @State private var saveErrorMessage: String?

    private var isNew: Bool { meeting == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    TextField("Titel", text: $title)
                    DatePicker("Datum/Uhrzeit", selection: $date)
                    TextField("Ort", text: $location)
                }

                Section {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label(pickedFileURL?.lastPathComponent ?? meeting?.invitationDocument?.fileName ?? "Einladung (PDF) auswählen", systemImage: "paperclip")
                    }
                } header: {
                    Text("Einladung")
                } footer: {
                    Text("Wird nach dem Sichern automatisch im Ordner „Eigentümerversammlungen“ der Immobilie abgelegt und als Kalendereintrag mit Erinnerung 3 Tage vorher angelegt.")
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !isNew {
                    Section {
                        Button("Eigentümerversammlung löschen", role: .destructive) {
                            deleteMeeting()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Eigentümerversammlung anlegen" : "Eigentümerversammlung bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result { pickedFileURL = url }
            }
            .onAppear(perform: loadExistingValues)
            .alert("Einladung konnte nicht gelesen werden", isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 460, idealHeight: 600, maxHeight: 760)
            #endif
        }
    }

    private func loadExistingValues() {
        guard let meeting else { return }
        title = meeting.title
        date = meeting.date
        location = meeting.location
        notes = meeting.notes
    }

    private func save() {
        var invitationData: Data?
        if let pickedFileURL {
            let didStartAccessing = pickedFileURL.startAccessingSecurityScopedResource()
            defer { if didStartAccessing { pickedFileURL.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: pickedFileURL) else {
                saveErrorMessage = "Die Einladung „\(pickedFileURL.lastPathComponent)“ ist nicht mehr lesbar – z.B. weil das Laufwerk getrennt oder die iCloud-Datei noch nicht geladen wurde. Bitte die Datei erneut auswählen."
                return
            }
            invitationData = data
        }

        let resolvedMeeting: OwnersMeetingEvent
        if let meeting {
            meeting.title = title
            meeting.date = date
            meeting.location = location
            meeting.notes = notes
            resolvedMeeting = meeting
        } else {
            let newMeeting = OwnersMeetingEvent(title: title, date: date, location: location, notes: notes)
            newMeeting.property = property
            modelContext.insert(newMeeting)
            resolvedMeeting = newMeeting
        }

        if let pickedFileURL, let invitationData {
            fileInvitation(invitationData, fileURL: pickedFileURL, into: resolvedMeeting)
        }

        CalendarEventManager.requestAccessIfNeeded { granted in
            guard granted else { return }
            resolvedMeeting.calendarEventIdentifier = CalendarEventManager.upsertEvent(
                title: resolvedMeeting.title,
                date: resolvedMeeting.date,
                location: resolvedMeeting.location,
                notes: resolvedMeeting.notes,
                existingIdentifier: resolvedMeeting.calendarEventIdentifier
            )
        }

        dismiss()
    }

    /// Legt das Dokument im (bei Bedarf neu angelegten) Ordner „Eigentümerversammlungen“ der
    /// Immobilie ab – derselbe Ordner wird bei weiteren Einladungen wiederverwendet.
    private func fileInvitation(_ data: Data, fileURL url: URL, into meeting: OwnersMeetingEvent) {
        let folder = existingOrNewFolder()
        let document = Document(title: title, fileName: url.lastPathComponent, fileExtension: url.pathExtension, data: data, receiptDate: date)
        document.property = property
        document.folder = folder
        modelContext.insert(document)
        meeting.invitationDocument = document
    }

    private func existingOrNewFolder() -> DocumentFolder {
        if let existing = (property.documentFolders ?? []).first(where: { $0.name == Self.folderName && $0.category == .propertyDocuments }) {
            return existing
        }
        let folder = DocumentFolder(name: Self.folderName, category: .propertyDocuments)
        folder.property = property
        modelContext.insert(folder)
        return folder
    }

    private static let folderName = "Eigentümerversammlungen"

    private func deleteMeeting() {
        if let meeting {
            if let identifier = meeting.calendarEventIdentifier {
                CalendarEventManager.removeEvent(identifier: identifier)
            }
            modelContext.delete(meeting)
        }
        dismiss()
    }
}

#Preview {
    OwnersMeetingEditView(property: Property(name: "Musterstraße 1"), meeting: nil)
        .modelContainer(PreviewData.container)
}
