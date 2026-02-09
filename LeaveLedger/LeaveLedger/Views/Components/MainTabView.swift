import SwiftUI

struct MainTabView: View {
    @State var viewModel: AppViewModel

    var body: some View {
        TabView {
            // Calendar tab - always shown
            NavigationStack {
                HomeView(viewModel: viewModel)
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }

            // Comp tab - conditional
            if viewModel.profile.compEnabled {
                NavigationStack {
                    LedgerView(viewModel: viewModel, leaveType: .comp)
                }
                .tabItem {
                    Label("Comp", systemImage: "clock.arrow.circlepath")
                }
            }

            // Vacation tab - conditional
            if viewModel.profile.vacationEnabled {
                NavigationStack {
                    LedgerView(viewModel: viewModel, leaveType: .vacation)
                }
                .tabItem {
                    Label("Vacation", systemImage: "airplane")
                }
            }

            // Sick tab - conditional
            if viewModel.profile.sickEnabled {
                NavigationStack {
                    LedgerView(viewModel: viewModel, leaveType: .sick)
                }
                .tabItem {
                    Label("Sick", systemImage: "cross.case")
                }
            }

            // Settings tab - always shown
            NavigationStack {
                SettingsView(viewModel: viewModel)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(.blue)
    }
}
