import SwiftUI
import AuthenticationServices
import OSLog

/// View model for managing authentication state
@Observable
class AuthViewModel {
    private let authService: AuthService
    private let dataStore: DataStore

    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?
    var currentUserEmail: String?

    init(authService: AuthService = AuthService(), dataStore: DataStore) {
        self.authService = authService
        self.dataStore = dataStore

        // Check for existing session on init
        checkAuthStatus()
    }

    // MARK: - Auth Status

    /// Checks if user has a valid stored session
    func checkAuthStatus() {
        if authService.loadStoredSession() {
            isAuthenticated = true
            currentUserEmail = KeychainService.getEmail()
            os_log(.info, log: Logger.auth, "Auth session restored")
        } else {
            isAuthenticated = false
            os_log(.info, log: Logger.auth, "No stored auth session")
        }
    }

    // MARK: - Sign In

    /// Initiates Sign in with Apple flow
    func signInWithApple(presentationAnchor: ASPresentationAnchor) {
        isLoading = true
        errorMessage = nil

        authService.signInWithApple(presentationAnchor: presentationAnchor) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let user):
                    self?.isAuthenticated = true
                    self?.currentUserEmail = user.email
                    self?.updateUserProfile(with: user)
                    os_log(.info, log: Logger.auth, "Sign in successful")

                case .failure(let error):
                    if case AuthError.cancelled = error {
                        os_log(.info, log: Logger.auth, "Sign in cancelled by user")
                    } else {
                        self?.errorMessage = error.localizedDescription
                        os_log(.error, log: Logger.auth, "Sign in failed: %@", error.localizedDescription)
                    }
                }
            }
        }
    }

    /// Handles Sign in with Apple result from SignInWithAppleButton
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid credential"
                return
            }

            let user = AuthService.AuthUser(
                appleUserId: credential.user,
                email: credential.email,
                fullName: credential.fullName
            )

            // Store credentials
            KeychainService.saveAppleUserId(credential.user)
            if let email = credential.email {
                KeychainService.saveEmail(email)
            }

            isAuthenticated = true
            currentUserEmail = user.email
            updateUserProfile(with: user)
            os_log(.info, log: Logger.auth, "Sign in successful via button")

        case .failure(let error):
            let nsError = error as NSError
            if nsError.code != 1001 { // Not cancelled
                errorMessage = error.localizedDescription
                os_log(.error, log: Logger.auth, "Sign in failed: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Sign Out

    /// Signs out the current user
    func signOut() {
        authService.signOut()
        isAuthenticated = false
        currentUserEmail = nil
        errorMessage = nil
        os_log(.info, log: Logger.auth, "User signed out")
    }

    // MARK: - User Profile Updates

    /// Updates UserProfile with authentication data
    private func updateUserProfile(with user: AuthService.AuthUser) {
        dataStore.updateProfile { profile in
            profile.appleUserId = user.appleUserId
            profile.email = user.email
            profile.isAuthenticated = true
        }
        os_log(.info, log: Logger.auth, "User profile updated with auth data")
    }
}
