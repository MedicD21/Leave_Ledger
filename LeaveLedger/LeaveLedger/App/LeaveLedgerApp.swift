import SwiftUI
import SwiftData

@main
struct LeaveLedgerApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Handle leaveLedger://entry/<uuid>
        guard url.scheme == "leaveLedger" else { return }
        if url.host == "entry", let uuidStr = url.pathComponents.last,
           let _ = UUID(uuidString: uuidStr) {
            // Navigate to the entry's date - find the entry and select its date
            let entries = viewModel.store.allEntries()
            if let entry = entries.first(where: { $0.id.uuidString == uuidStr }) {
                viewModel.selectDate(entry.date)
            }
        }
    }
}
