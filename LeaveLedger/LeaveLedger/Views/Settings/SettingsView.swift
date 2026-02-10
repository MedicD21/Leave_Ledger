import SwiftUI
import UniformTypeIdentifiers

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showExportSheet = false
    @State private var csvURL: IdentifiableURL?
    @State private var pdfURL: IdentifiableURL?
    @State private var backupURL: IdentifiableURL?
    @State private var showImportPicker = false
    @State private var showImportConfirmation = false
    @State private var importResult: String?
    @State private var showImportResult = false
    @State private var showResetConfirmation = false
    @FocusState private var focusedField: Bool

    // Editable fields
    @State private var anchorDate: Date
    @State private var sickStart: String
    @State private var vacStart: String
    @State private var compStart: String
    @State private var sickRate: String
    @State private var vacRate: String

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let profile = viewModel.profile ?? UserProfile(id: KeychainService.getUserId())
        _anchorDate = State(initialValue: profile.anchorPayday)
        _sickStart = State(initialValue: String(format: "%.2f", NSDecimalNumber(decimal: profile.sickStartBalance).doubleValue))
        _vacStart = State(initialValue: String(format: "%.2f", NSDecimalNumber(decimal: profile.vacStartBalance).doubleValue))
        _compStart = State(initialValue: String(format: "%.2f", NSDecimalNumber(decimal: profile.compStartBalance).doubleValue))
        _sickRate = State(initialValue: String(format: "%.2f", NSDecimalNumber(decimal: profile.sickAccrualRate).doubleValue))
        _vacRate = State(initialValue: String(format: "%.2f", NSDecimalNumber(decimal: profile.vacAccrualRate).doubleValue))
    }

    var body: some View {
        Form {
            Section("Pay Period Configuration") {
                DatePicker("Anchor Payday", selection: $anchorDate, displayedComponents: .date)
                    .onChange(of: anchorDate) { _, newVal in
                        viewModel.updateAnchorPayday(newVal)
                    }

                HStack {
                    Text("Pay Period Length")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("14 days (biweekly)")
                        .font(.subheadline)
                }
            }

            Section("Starting Balances (at Anchor Payday)") {
                if viewModel.profile.sickEnabled {
                    DecimalField(label: "Sick Hours", text: $sickStart, focused: $focusedField)
                }
                if viewModel.profile.vacationEnabled {
                    DecimalField(label: "Vacation Hours", text: $vacStart, focused: $focusedField)
                }
                if viewModel.profile.compEnabled {
                    DecimalField(label: "Comp Hours", text: $compStart, focused: $focusedField)
                }

                Button("Apply Starting Balances") {
                    let comp = Decimal(string: compStart) ?? 0
                    let vac = Decimal(string: vacStart) ?? 0
                    let sick = Decimal(string: sickStart) ?? 0
                    viewModel.updateStartingBalances(comp: comp, vac: vac, sick: sick)
                }
            }

            Section("Accrual Rates (per Payday)") {
                if viewModel.profile.sickEnabled {
                    DecimalField(label: "Sick Accrual", text: $sickRate, focused: $focusedField)
                }
                if viewModel.profile.vacationEnabled {
                    DecimalField(label: "Vacation Accrual", text: $vacRate, focused: $focusedField)
                }

                Button("Apply Accrual Rates") {
                    let vac = Decimal(string: vacRate) ?? 0
                    let sick = Decimal(string: sickRate) ?? 0
                    viewModel.updateAccrualRates(vac: vac, sick: sick)
                }
            }

            Section("Rounding") {
                Toggle("Enforce 0.25h Increments",
                       isOn: Binding(
                        get: { viewModel.profile.enforceQuarterIncrements },
                        set: { _ in viewModel.toggleQuarterIncrements() }
                       ))
            }

            Section("iCal Calendar Feed") {
                let baseURL = SupabaseConfig.url.isEmpty ? "https://your-project.supabase.co" : SupabaseConfig.url
                let feedURL = "\(baseURL)/functions/v1/leave-ics?token=\(viewModel.profile.icalToken)"

                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscribe in Apple Calendar:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(feedURL)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Button {
                    UIPasteboard.general.string = feedURL
                } label: {
                    Label("Copy Feed URL", systemImage: "doc.on.doc")
                }

                Button {
                    viewModel.regenerateICalToken()
                } label: {
                    Label("Regenerate Token", systemImage: "arrow.triangle.2.circlepath")
                }
                .foregroundStyle(.orange)
            }

            Section("Data & Backup") {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Complete Backup", systemImage: "doc.badge.arrow.up")
                }

                Button {
                    showImportConfirmation = true
                } label: {
                    Label("Import Backup", systemImage: "doc.badge.arrow.down")
                }
                .foregroundStyle(.orange)

                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }

                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF Summary", systemImage: "doc.richtext")
                }

                Button {
                    viewModel.syncWithSupabase()
                } label: {
                    Label("Sync with Supabase", systemImage: "arrow.triangle.2.circlepath")
                }

                if viewModel.supabaseService.isSyncing {
                    HStack {
                        ProgressView()
                        Text("Syncing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = viewModel.supabaseService.syncError {
                    Text("Sync error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let lastSync = viewModel.supabaseService.lastSyncAt {
                    Text("Last sync: \(DateUtils.shortDate(lastSync))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Account Management") {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Profile & Start Over", systemImage: "arrow.counterclockwise.circle")
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("User ID")
                    Spacer()
                    Text(KeychainService.getUserId().uuidString.prefix(8) + "...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = false
                }
            }
        }
        .sheet(item: $csvURL) { identifiableURL in
            ShareSheet(items: [identifiableURL.url])
        }
        .sheet(item: $pdfURL) { identifiableURL in
            ShareSheet(items: [identifiableURL.url])
        }
        .sheet(item: $backupURL) { identifiableURL in
            ShareSheet(items: [identifiableURL.url])
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPicker { url in
                performImport(from: url)
            }
        }
        .alert("Import Backup", isPresented: $showImportConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Import", role: .destructive) {
                showImportPicker = true
            }
        } message: {
            Text("This will replace ALL existing data with the backup. This action cannot be undone. Make sure you have exported your current data first.")
        }
        .alert("Import Result", isPresented: $showImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            if let result = importResult {
                Text(result)
            }
        }
        .alert("Reset Account", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Sign Out", role: .destructive) {
                performReset()
            }
        } message: {
            Text("This will delete all your local data, remote data, and return you to the setup screen. This action cannot be undone.")
        }
    }

    private func exportCSV() {
        let service = ExportService()
        if let url = service.exportCSV(entries: viewModel.entries) {
            csvURL = IdentifiableURL(url: url)
        }
    }

    private func exportPDF() {
        let service = ExportService()
        if let url = service.exportPDF(
            entries: viewModel.entries,
            officialBalance: viewModel.officialBalance,
            forecastBalance: viewModel.forecastBalance,
            month: viewModel.displayedMonth
        ) {
            pdfURL = IdentifiableURL(url: url)
        }
    }

    private func exportBackup() {
        guard let profile = viewModel.profile else { return }
        let service = ImportExportService()
        if let url = service.exportBackup(profile: profile, entries: viewModel.entries) {
            backupURL = IdentifiableURL(url: url)
        }
    }

    private func performImport(from url: URL) {
        let service = ImportExportService()
        let result = service.importBackup(from: url, into: viewModel.store)

        if result.success {
            importResult = "Successfully imported profile and \(result.entriesImported) entries."
            viewModel.refreshData()
            viewModel.syncWithSupabase()
        } else {
            importResult = result.error ?? "Import failed"
        }
        showImportResult = true
    }

    private func performReset() {
        // 1. Mark all entries as deleted
        let allEntries = viewModel.store.allEntries()
        for entry in allEntries {
            viewModel.store.softDelete(entry)
        }

        // 2. Sync deletions to Supabase
        viewModel.syncWithSupabase()

        // 3. Reset profile flags
        viewModel.store.updateProfile { profile in
            profile.isSetupComplete = false
            profile.appleUserId = nil
            profile.email = nil
        }

        // 4. Clear auth tokens (sign out)
        KeychainService.clearAuthTokens()

        // Note: The app will need to be relaunched or the auth state will need to be observed
        // to trigger navigation back to login/onboarding
    }
}

struct DecimalField: View {
    let label: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .focused(focused ?? FocusState<Bool>().projectedValue)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
