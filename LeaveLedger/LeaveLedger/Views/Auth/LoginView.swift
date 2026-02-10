import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Bindable var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App Logo and Title
            VStack(spacing: 12) {
                // App Icon
                if let appIcon = Bundle.main.icon {
                    Image(uiImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                } else {
                    // Fallback to SF Symbol if icon not found
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                }

                Text("Leave Ledger")
                    .font(.largeTitle.bold())

                Text("Track your leave balances with confidence")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Sign in with Apple Button
            VStack(spacing: 16) {
                SignInWithAppleButton(
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { result in
                        authViewModel.handleSignInResult(result)
                    }
                )
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .padding(.horizontal, 40)

                if authViewModel.isLoading {
                    ProgressView()
                        .padding(.top, 8)
                }

                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Spacer()

            // Privacy Note
            Text("Your data is private and secure")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .padding()
    }
}
