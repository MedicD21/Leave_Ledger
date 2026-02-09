import SwiftUI
import SwiftData

@main
struct LeaveLedgerApp: App {
    @State private var appViewModel = AppViewModel()
    @State private var authViewModel: AuthViewModel?

    init() {
        // Initialize AuthViewModel with dataStore from AppViewModel
        let tempAppVM = AppViewModel()
        _appViewModel = State(initialValue: tempAppVM)
        _authViewModel = State(initialValue: AuthViewModel(dataStore: tempAppVM.store))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let authVM = authViewModel {
                    if !authVM.isAuthenticated {
                        // Not authenticated - show login
                        LoginView(authViewModel: authVM)
                    } else if !appViewModel.profile.isSetupComplete {
                        // Authenticated but not setup - show onboarding
                        OnboardingContainerView(viewModel: appViewModel)
                    } else {
                        // Authenticated and setup - show main app
                        MainTabView(viewModel: appViewModel)
                            .onOpenURL { url in
                                handleDeepLink(url)
                            }
                    }
                } else {
                    // Loading state
                    ProgressView()
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: authViewModel?.isAuthenticated) { _, isAuth in
                if isAuth == true {
                    appViewModel.refreshData()
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Handle leaveLedger://entry/<uuid>
        guard url.scheme == "leaveLedger" else { return }
        if url.host == "entry", let uuidStr = url.pathComponents.last,
           let _ = UUID(uuidString: uuidStr) {
            // Navigate to the entry's date - find the entry and select its date
            let entries = appViewModel.store.allEntries()
            if let entry = entries.first(where: { $0.id.uuidString == uuidStr }) {
                appViewModel.selectDate(entry.date)
            }
        }
    }
}
