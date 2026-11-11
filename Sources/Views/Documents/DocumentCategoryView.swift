import SwiftUI
import SwiftData

/// Ordnerübersicht eines einzelnen Reiters (Immobiliendokumente / Rechnungen & Belege /
/// Nebenkostenabrechnungen) einer Immobilie – zeigt die vom Nutzer angelegten Ordner (erstell-
/// und umbenennbar) sowie einen Einstieg in die nicht einsortierten Dokumente dieses Reiters.
struct DocumentCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allFolders: [DocumentFolder]
    @Query private var allDocuments: [Document]

    let property: Property
    let category: DocumentCategory

    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var folderToRename: DocumentFolder?
    @State private var renameText = ""
    @State private var folderToDelete: DocumentFolder?

    private var folders: [DocumentFolder] {
        allFolders
            .filter { $0.property == property && $0.category == category }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var unfiledCount: Int {
        allDocuments.filter { $0.resolvedProperty == property && $0.category == category && $0.folder == nil }.count
    }

    var body: some View {
        List {
            Section {
                ForEach(folders) { folder in
                    NavigationLink(value: folder) {
                        HStack {
                            Label(folder.name, systemImage: "folder")
                            Spacer()
                            let count = folder.documents?.count ?? 0
                            if count > 0 {
                                Text(String(count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            renameText = folder.name
                            folderToRename = folder
                        } label: {
                            Label("Umbenennen", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            folderToDelete = folder
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { modelContext.delete(folders[index]) }
                }
                Button {
                    newFolderName = ""
                    showingNewFolderAlert = true
                } label: {
                    Label("Ordner erstellen", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("Ordner")
            } footer: {
                Text("Ordner rein organisatorisch – ohne Einfluss auf Verknüpfungen oder Berechnungen. Umbenennen/Löschen über Rechtsklick bzw. Wischen.")
            }

            Section {
                NavigationLink {
                    DocumentListView(property: property, category: category)
                } label: {
                    HStack {
                        Label("Nicht einsortiert", systemImage: "doc")
                        Spacer()
                        if unfiledCount > 0 {
                            Text(String(unfiledCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle(category.label)
        .alert("Neuer Ordner", isPresented: $showingNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button("Abbrechen", role: .cancel) {}
            Button("Erstellen") { createFolder() }
        }
        .alert("Ordner umbenennen", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") { renameFolder() }
        }
        .alert("Ordner löschen?", isPresented: Binding(
            get: { folderToDelete != nil },
            set: { if !$0 { folderToDelete = nil } }
        )) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                if let folderToDelete { modelContext.delete(folderToDelete) }
            }
        } message: {
            Text("Die enthaltenen Dokumente bleiben erhalten und werden als nicht einsortiert angezeigt.")
        }
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = DocumentFolder(name: trimmed, category: category)
        folder.property = property
        modelContext.insert(folder)
    }

    private func renameFolder() {
        guard let folderToRename else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folderToRename.name = trimmed
    }
}

#Preview {
    NavigationStack {
        DocumentCategoryView(property: Property(name: "Musterstraße 1"), category: .invoicesReceipts)
    }
    .modelContainer(PreviewData.container)
}
