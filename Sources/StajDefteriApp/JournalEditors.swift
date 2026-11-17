import PhotosUI
import StajDefteriCore
import SwiftUI
import UIKit

@MainActor
struct InternshipEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var internship: Internship
    @State private var isSaving = false
    @State private var showsDiscard = false
    @State private var failure: String?
    private let original: Internship
    private let isNew: Bool
    private let save: (Internship) async throws -> Void

    init(internship: Internship, isNew: Bool, save: @escaping (Internship) async throws -> Void) {
        _internship = State(initialValue: internship)
        original = internship
        self.isNew = isNew
        self.save = save
    }

    private var hasChanges: Bool { internship != original }
    private var canSave: Bool {
        !internship.studentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !internship.workplace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && internship.startDate <= internship.endDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad soyad", text: $internship.studentName)
                        .textContentType(.name)
                    TextField("Okul", text: $internship.school)
                    TextField("Bölüm", text: $internship.department)
                    TextField("Öğrenci numarası", text: $internship.studentNumber)
                } header: {
                    Text("Öğrenci bilgileri")
                } footer: {
                    Text("Ad soyad ve staj yeri zorunludur.")
                }
                Section {
                    TextField("Staj yeri", text: $internship.workplace)
                        .textContentType(.organizationName)
                    DatePicker("Başlangıç", selection: $internship.startDate.dateValue, displayedComponents: .date)
                    DatePicker("Bitiş", selection: $internship.endDate.dateValue, displayedComponents: .date)
                } header: {
                    Text("Staj bilgileri")
                } footer: {
                    if internship.startDate > internship.endDate {
                        Text("Bitiş tarihi başlangıç tarihinden önce olamaz.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle(isNew ? "Yeni staj" : "Stajı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        if hasChanges { showsDiscard = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: saveInternship)
                        .disabled(isSaving || !canSave)
                }
            }
            .alert(error: $failure)
            .discardChanges(isPresented: $showsDiscard) { dismiss() }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
    }

    private func saveInternship() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                var details = internship
                details.studentName = details.studentName.trimmingCharacters(in: .whitespacesAndNewlines)
                details.workplace = details.workplace.trimmingCharacters(in: .whitespacesAndNewlines)
                try await save(details)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

@MainActor
struct EntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var entry: JournalEntry
    @State private var importedPhotos: [UUID: Data] = [:]
    @State private var selection: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var requestsCamera = false
    @State private var showsCameraSettings = false
    @State private var isImporting = false
    @State private var isSaving = false
    @State private var showsDiscard = false
    @State private var failure: String?
    private let original: JournalEntry
    private let isNew: Bool
    private let loadPhoto: (UUID) async throws -> Data
    private let save: (JournalEntry, [UUID: Data]) async throws -> Void

    init(
        entry: JournalEntry,
        isNew: Bool,
        loadPhoto: @escaping (UUID) async throws -> Data,
        save: @escaping (JournalEntry, [UUID: Data]) async throws -> Void
    ) {
        _entry = State(initialValue: entry)
        original = entry
        self.isNew = isNew
        self.loadPhoto = loadPhoto
        self.save = save
    }

    private var isBusy: Bool { isSaving || isImporting || requestsCamera }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Tarih", selection: $entry.date.dateValue, displayedComponents: .date)
                EntryField("Ne yaptım", text: $entry.work)
                EntryField("Nasıl yaptım", text: $entry.method)
                EntryField("Sonuç", text: $entry.result)
                EntryField("Öğrendiklerim", text: $entry.learning)
                Section("Fotoğraflar") {
                    ForEach($entry.photos) { $photo in
                        let id = photo.id
                        PhotoEditor(photo: $photo, load: {
                            if let data = importedPhotos[id] { return data }
                            return try await loadPhoto(id)
                        }) {
                            entry.photos.removeAll { $0.id == id }
                            importedPhotos[id] = nil
                        }
                    }
                    PhotosPicker(selection: $selection, selectionBehavior: .ordered, matching: .images) {
                        Label("Fotoğraf seç", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isBusy)
                    Button("Fotoğraf çek", systemImage: "camera", action: openCamera)
                        .disabled(isBusy)
                    if isImporting {
                        ProgressView("Fotoğraflar hazırlanıyor")
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle(isNew ? "Yeni günlük kayıt" : "Günlüğü düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        if entry != original { showsDiscard = true } else { dismiss() }
                    }
                    .disabled(isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: saveEntry)
                        .disabled(isBusy)
                }
            }
            .onChange(of: selection) { _, items in
                guard !items.isEmpty else { return }
                isImporting = true
                Task { await importSelection(items) }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in
                    showsCamera = false
                    guard let image else { return }
                    if let data = PhotoCodec.jpeg(from: image) {
                        appendPhoto(data)
                    } else {
                        failure = "Çekilen fotoğraf hazırlanamadı."
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Kamera izni gerekli", isPresented: $showsCameraSettings) {
                Button("Ayarları aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Fotoğraf çekmek için Ayarlar’dan Staj Defteri’nin kamera erişimine izin verin.")
            }
            .alert(error: $failure)
            .discardChanges(isPresented: $showsDiscard) { dismiss() }
        }
        .interactiveDismissDisabled(entry != original || isBusy)
    }

    private func saveEntry() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await save(entry, importedPhotos)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func openCamera() {
        requestsCamera = true
        Task {
            defer { requestsCamera = false }
            switch await CameraPicker.access() {
            case .ready:
                showsCamera = true
            case .denied:
                showsCameraSettings = true
            case .unavailable:
                failure = "Bu cihazda kamera kullanılamıyor."
            case .restricted:
                failure = "Cihazdaki kısıtlamalar kamera erişimini engelliyor."
            }
        }
    }

    private func importSelection(_ items: [PhotosPickerItem]) async {
        defer {
            selection = []
            isImporting = false
        }
        var skipped = 0
        for item in items {
            do {
                appendPhoto(try await PhotoCodec.load(item))
            } catch {
                skipped += 1
            }
        }
        if skipped > 0 {
            failure = "\(skipped) fotoğraf yüklenemedi. Kaynağından erişilebildiğini kontrol edip tekrar seçin."
        }
    }

    private func appendPhoto(_ data: Data) {
        let photo = JournalPhoto()
        importedPhotos[photo.id] = data
        entry.photos.append(photo)
    }
}

private struct EntryField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        Section(title) {
            TextEditor(text: $text)
                .accessibilityLabel(Text(title))
                .frame(minHeight: 88)
        }
    }
}

@MainActor
private struct PhotoEditor: View {
    @Binding var photo: JournalPhoto
    let load: () async throws -> Data
    let remove: () -> Void
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityHidden(true)
            } else if failed {
                Label("Fotoğraf açılamadı", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView("Fotoğraf yükleniyor")
            }
            TextField("Fotoğraf açıklaması", text: $photo.caption, axis: .vertical)
            Button("Fotoğrafı kaldır", systemImage: "trash", role: .destructive, action: remove)
        }
        .padding(.vertical, 4)
        .task(id: photo.id) {
            do {
                image = UIImage(data: try await load())
                failed = image == nil
            } catch {
                failed = true
            }
        }
    }
}

private extension Binding where Value == LocalDate {
    var dateValue: Binding<Date> {
        Binding(get: { wrappedValue.date }, set: { wrappedValue = LocalDate($0) })
    }
}

private extension View {
    func discardChanges(isPresented: Binding<Bool>, confirm: @escaping () -> Void) -> some View {
        confirmationDialog(
            "Kaydedilmemiş değişiklikler silinsin mi?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Değişiklikleri sil", role: .destructive, action: confirm)
            Button("Düzenlemeye dön", role: .cancel) {}
        }
    }
}
