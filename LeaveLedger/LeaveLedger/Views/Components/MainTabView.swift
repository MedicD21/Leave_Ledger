import SwiftUI

struct MainTabView: View {
    @State var viewModel: AppViewModel

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(viewModel: viewModel)
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }

            NavigationStack {
                LedgerView(viewModel: viewModel, leaveType: .comp)
            }
            .tabItem {
                Label("Comp", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                LedgerView(viewModel: viewModel, leaveType: .vacation)
            }
            .tabItem {
                Label("Vacation", systemImage: "airplane")
            }

            NavigationStack {
                LedgerView(viewModel: viewModel, leaveType: .sick)
            }
            .tabItem {
                Label("Sick", systemImage: "cross.case")
            }

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
