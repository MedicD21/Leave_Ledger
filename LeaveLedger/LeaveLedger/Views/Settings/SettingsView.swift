import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showExportSheet = false
    @State private var showCSVShare = false
    @State private var csvURL: URL?
    @State private var showPDFShare = false
    @State private var pdfURL: URL?

    // Editable fields
    @State private var anchorDate: Date
    @State private var sickStart: String
    @State private var vacStart: String
    @State private var compStart: String
    @State private var sickRate: String
    @State private var vacRate: String

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let profile = viewModel.profile!
        _anchorDate = State(initialValue: profile.anchorPayday)
        _sickStart = State(initialValue: "\(NSDecimalNumber(decimal: profile.sickStartBalance).doubleValue)")
        _vacStart = State(initialValue: "\(NSDecimalNumber(decimal: profile.vacStartBalance).doubleValue)")
        _compStart = State(initialValue: "\(NSDecimalNumber(decimal: profile.compStartBalance).doubleValue)")
        _sickRate = State(initialValue: "\(NSDecimalNumber(decimal: profile.sickAccrualRate).doubleValue)")
        _vacRate = State(initialValue: "\(NSDecimalNumber(decimal: profile.vacAccrualRate).doubleValue)")
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
                DecimalField(label: "Sick Hours", text: $sickStart)
                DecimalField(label: "Vacation Hours", text: $vacStart)
                DecimalField(label: "Comp Hours", text: $compStart)

                Button("Apply Starting Balances") {
                    let comp = Decimal(string: compStart) ?? 0
                    let vac = Decimal(string: vacStart) ?? 0
                    let sick = Decimal(string: sickStart) ?? 0
                    viewModel.updateStartingBalances(comp: comp, vac: vac, sick: sick)
                }
            }

            Section("Accrual Rates (per Payday)") {
                DecimalField(label: "Sick Accrual", text: $sickRate)
                DecimalField(label: "Vacation Accrual", text: $vacRate)

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
        .sheet(isPresented: $showCSVShare) {
            if let url = csvURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showPDFShare) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportCSV() {
        let service = ExportService()
        if let url = service.exportCSV(entries: viewModel.entries) {
            csvURL = url
            showCSVShare = true
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
            pdfURL = url
            showPDFShare = true
        }
    }
}

struct DecimalField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
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
