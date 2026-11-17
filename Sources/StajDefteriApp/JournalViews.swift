import StajDefteriCore
import SwiftUI

@MainActor
struct InternshipList: View {
    let journal: JournalModel
    @State private var editor: Internship?
    @State private var pendingDeletion: Internship?
    @State private var showsPrivacy = false
    @State private var isDeleting = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if journal.isLoading {
                    ProgressView("Staj defteri açılıyor")
                } else if let error = journal.loadError {
                    ContentUnavailableView {
                        Label("Staj defteri açılamadı", systemImage: "exclamationmark.circle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Yeniden dene") { Task { await journal.open() } }
                    }
                } else if journal.internships.isEmpty {
                    ContentUnavailableView {
                        Label("Henüz staj yok", systemImage: "book.closed")
                    } description: {
                        Text("Staj bilgilerinizi ekleyip günlük kayıtlarınızı tutmaya başlayın.")
                    } actions: {
                        Button("Staj ekle") { editor = Internship() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section("Stajlarım") {
                            ForEach(journal.internships) { internship in
                                NavigationLink(value: internship.id) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(internship.workplace).font(.headline)
                                        Text(internship.dateRange)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions(allowsFullSwipe: false) {
                                    Button("Sil", role: .destructive) { pendingDeletion = internship }
                                }
                                .accessibilityAction(named: Text("Sil")) { pendingDeletion = internship }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Staj Defteri")
            .navigationDestination(for: UUID.self) { id in
                if let internship = journal.internships.first(where: { $0.id == id }) {
                    InternshipDetail(journal: journal, internship: internship)
                } else {
                    ContentUnavailableView("Staj bulunamadı", systemImage: "book.closed")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Gizlilik", systemImage: "hand.raised") { showsPrivacy = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Staj ekle", systemImage: "plus") { editor = Internship() }
                        .disabled(journal.isLoading || journal.loadError != nil || isDeleting)
                }
            }
            .disabled(isDeleting)
            .sheet(item: $editor) { internship in
                InternshipEditor(internship: internship, isNew: true, save: journal.save)
            }
            .sheet(isPresented: $showsPrivacy) { PrivacyView() }
            .alert(error: $failure)
            .confirmationDialog(
                "Staj silinsin mi?",
                isPresented: $pendingDeletion.isPresent,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { internship in
                Button("Stajı sil", role: .destructive) {
                    isDeleting = true
                    Task {
                        defer { isDeleting = false }
                        do { try await journal.deleteInternship(internship.id) }
                        catch { failure = error.localizedDescription }
                    }
                }
            } message: { internship in
                Text("“\(internship.workplace)” stajı, günlük kayıtları ve fotoğraflarıyla birlikte silinecek.")
            }
        }
        .task { await journal.open() }
    }
}

@MainActor
private struct InternshipDetail: View {
    let journal: JournalModel
    let internship: Internship
    @State private var stajEditor: Internship?
    @State private var entryEditor: JournalEntry?
    @State private var pendingDeletion: JournalEntry?
    @State private var showsExport = false
    @State private var isDeleting = false
    @State private var failure: String?

    var body: some View {
        List {
            Section("Staj bilgileri") {
                LabeledContent("Öğrenci", value: internship.studentName)
                if !internship.school.isEmpty {
                    LabeledContent("Okul", value: internship.school)
                }
                if !internship.department.isEmpty {
                    LabeledContent("Bölüm", value: internship.department)
                }
                if !internship.studentNumber.isEmpty {
                    LabeledContent("Öğrenci numarası", value: internship.studentNumber)
                }
                LabeledContent("Staj dönemi", value: internship.dateRange)
                Button("Staj bilgilerini düzenle", systemImage: "pencil") {
                    stajEditor = internship
                }
                Button("Word belgesi oluştur", systemImage: "square.and.arrow.up") {
                    showsExport = true
                }
            }

            Section("Günlük kayıtları") {
                Button("Günlük kayıt ekle", systemImage: "plus.circle") {
                    entryEditor = JournalEntry()
                }
                if internship.entries.isEmpty {
                    Text("Bu staja henüz günlük kayıt eklenmedi.")
                        .foregroundStyle(.secondary)
                }
                ForEach(internship.entries.sorted { $0.date > $1.date }) { entry in
                    Button {
                        entryEditor = entry
                    } label: {
                        EntryRow(entry: entry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Sil", role: .destructive) { pendingDeletion = entry }
                    }
                    .accessibilityAction(named: Text("Sil")) { pendingDeletion = entry }
                }
            }
        }
        .navigationTitle(internship.workplace)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isDeleting)
        .sheet(item: $stajEditor) { internship in
            InternshipEditor(internship: internship, isNew: false, save: journal.save)
        }
        .sheet(item: $entryEditor) { entry in
            EntryEditor(
                entry: entry,
                isNew: !internship.entries.contains { $0.id == entry.id },
                loadPhoto: journal.photoData,
                save: { entry, photos in
                    try await journal.save(entry, in: internship.id, photos: photos)
                }
            )
        }
        .sheet(isPresented: $showsExport) {
            ExportView { try await journal.export(internship.id) }
        }
        .alert(error: $failure)
        .confirmationDialog(
            "Günlük kayıt silinsin mi?",
            isPresented: $pendingDeletion.isPresent,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entry in
            Button("Günlük kaydı sil", role: .destructive) {
                isDeleting = true
                Task {
                    defer { isDeleting = false }
                    do { try await journal.deleteEntry(entry.id, in: internship.id) }
                    catch { failure = error.localizedDescription }
                }
            }
        } message: { entry in
            Text("\(entry.date.displayText) tarihli kayıt, fotoğraflarıyla birlikte silinecek.")
        }
    }
}

private struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.date.displayText).font(.headline)
            if let excerpt = [entry.work, entry.method, entry.result, entry.learning]
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                Text(excerpt)
                    .lineLimit(2)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.photos.isEmpty {
                Label("\(entry.photos.count) fotoğraf", systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Cihazdaki kayıtlar") {
                    Text("Staj bilgileriniz, günlükleriniz ve eklediğiniz fotoğraflar cihazdaki özel uygulama alanında saklanır. Uygulama bu klasörü iOS yedeklemelerinden hariç tutulması için işaretler.")
                }
                Section("Fotoğraf ve kamera") {
                    Text("Fotoğraf seçici yalnızca sizin seçtiğiniz görselleri verir. Kamera izni, günlük için fotoğraf çekmek istediğinizde istenir.")
                }
                Section("Word belgeleri ve silme") {
                    Text("Word belgesi cihazda hazırlanır. Dosyayı kaydedeceğiniz yeri veya alıcıyı paylaşım ekranında siz seçersiniz. Dışa aktardığınız kopyaları, kaydettiğiniz konumdan silebilirsiniz.")
                }
                if let policy = releaseLink("StajPrivacyPolicyURL") {
                    Link("Gizlilik politikası", destination: policy)
                }
                if let support = releaseLink("StajSupportURL") {
                    Link("Destek", destination: support)
                }
            }
            .navigationTitle("Gizlilik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
        }
    }

    private func releaseLink(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

private extension Internship {
    var dateRange: String { "\(startDate.displayText) – \(endDate.displayText)" }
}

extension Optional {
    var isPresent: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}

extension View {
    func alert(error: Binding<String?>) -> some View {
        alert("İşlem tamamlanamadı", isPresented: error.isPresent, presenting: error.wrappedValue) { _ in
            Button("Tamam", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}
