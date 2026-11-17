import CoreTransferable
import StajDefteriCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var failure: String?
    @State private var isExporting = true
    @State private var attempt = 0
    let export: () async throws -> URL

    var body: some View {
        NavigationStack {
            Group {
                if let file {
                    ContentUnavailableView {
                        Label("Word belgesi hazır", systemImage: "doc.text")
                    } description: {
                        Text("Dosyayı kaydedebilir veya başka bir uygulamaya gönderebilirsiniz.")
                    } actions: {
                        ShareLink(
                            item: WordDocument(url: file),
                            preview: SharePreview("Staj Defteri.docx", image: Image(systemName: "doc.text"))
                        ) {
                            Label("Paylaş veya kaydet", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if let failure {
                    ContentUnavailableView {
                        Label("Belge oluşturulamadı", systemImage: "exclamationmark.circle")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Yeniden dene") {
                            self.failure = nil
                            isExporting = true
                            attempt += 1
                        }
                    }
                } else {
                    ProgressView("Word belgesi hazırlanıyor")
                }
            }
            .navigationTitle("Word belgesi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }.disabled(isExporting)
                }
            }
        }
        .interactiveDismissDisabled(isExporting)
        .task(id: attempt) {
            defer { isExporting = false }
            do { file = try await export() }
            catch { failure = error.localizedDescription }
        }
    }
}

private struct WordDocument: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            exportedContentType: UTType(filenameExtension: "docx")
                ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
        ) { document in
            SentTransferredFile(document.url)
        }
    }
}

enum ExportLocation {
    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("StajDefteriExports", isDirectory: true)
    }

    static func write(internship: Internship, photos: [UUID: Data]) throws -> URL {
        let files = FileManager.default
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("Staj Defteri.docx")
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try DOCXExporter.export(internship: internship, photoData: photos, to: destination)
            return destination
        } catch {
            try? files.removeItem(at: directory)
            throw error
        }
    }
}
