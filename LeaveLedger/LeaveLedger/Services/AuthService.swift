import Foundation
import AuthenticationServices
import OSLog

/// Error types for authentication
enum AuthError: Error {
    case invalidCredential
    case invalidURL
    case networkError(String)
    case supabaseError(String)
    case cancelled
}

/// Manages Apple Sign In authentication and Supabase Auth integration
@Observable
class AuthService: NSObject {
    var isAuthenticating = false
    var authError: String?

    private var authCompletion: ((Result<AuthUser, Error>) -> Void)?

    /// Authenticated user data
    struct AuthUser {
        let appleUserId: String
        let email: String?
        let fullName: PersonNameComponents?
    }

    // MARK: - Sign in with Apple

    /// Initiates Sign in with Apple flow
    func signInWithApple(presentationAnchor: ASPresentationAnchor, completion: @escaping (Result<AuthUser, Error>) -> Void) {
        guard !isAuthenticating else {
            os_log(.error, log: Logger.auth, "Auth already in progress")
            completion(.failure(AuthError.networkError("Authentication already in progress")))
            return
        }

        isAuthenticating = true
        authCompletion = completion
        authError = nil

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()

        os_log(.info, log: Logger.auth, "Sign in with Apple initiated")
    }

    // MARK: - Supabase Auth Integration

    /// Exchanges Apple identity token with Supabase for session tokens
    private func exchangeAppleTokenWithSupabase(
        identityToken: String,
        appleUserId: String,
        completion: @escaping (Result<SupabaseSession, Error>) -> Void
    ) {
        guard !SupabaseConfig.url.isEmpty && !SupabaseConfig.anonKey.isEmpty else {
            os_log(.error, log: Logger.auth, "Supabase not configured")
            completion(.failure(AuthError.supabaseError("Supabase not configured")))
            return
        }

        guard let url = URL(string: "\(SupabaseConfig.url)/auth/v1/token?grant_type=id_token") else {
            os_log(.error, log: Logger.auth, "Invalid Supabase auth URL")
            completion(.failure(AuthError.invalidURL))
            return
        }

        let payload: [String: Any] = [
            "provider": "apple",
            "id_token": identityToken
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            os_log(.error, log: Logger.auth, "Failed to serialize auth payload")
            completion(.failure(AuthError.networkError("Failed to serialize auth payload")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        os_log(.info, log: Logger.auth, "Exchanging Apple token with Supabase")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                let errorMsg = error.localizedDescription
                os_log(.error, log: Logger.auth, "Supabase token exchange network error: %@", errorMsg)
                completion(.failure(AuthError.networkError(errorMsg)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                os_log(.error, log: Logger.auth, "Invalid response from Supabase")
                completion(.failure(AuthError.networkError("Invalid response")))
                return
            }

            guard httpResponse.statusCode < 300 else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let errorMsg = "Supabase auth failed with status \(httpResponse.statusCode): \(body)"
                os_log(.error, log: Logger.auth, "%@", errorMsg)
                completion(.failure(AuthError.supabaseError(errorMsg)))
                return
            }

            guard let data = data else {
                os_log(.error, log: Logger.auth, "No data received from Supabase")
                completion(.failure(AuthError.networkError("No data received")))
                return
            }

            // Parse Supabase session response
            do {
                let decoder = JSONDecoder()
                let session = try decoder.decode(SupabaseSession.self, from: data)
                os_log(.info, log: Logger.auth, "Successfully exchanged token with Supabase")
                completion(.success(session))
            } catch {
                os_log(.error, log: Logger.auth, "Failed to decode Supabase session: %@", error.localizedDescription)
                completion(.failure(AuthError.supabaseError("Failed to decode session")))
            }
        }.resume()
    }

    // MARK: - Session Management

    /// Checks if user has a valid stored session
    func loadStoredSession() -> Bool {
        if let token = KeychainService.getAccessToken(),
           let userId = KeychainService.getAppleUserId() {
            os_log(.info, log: Logger.auth, "Found stored session for user: %@", userId.prefix(8).description)
            return !token.isEmpty
        }
        return false
    }

    /// Signs out the user by clearing all auth credentials
    func signOut() {
        KeychainService.clearAuthTokens()
        os_log(.info, log: Logger.auth, "User signed out")
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            isAuthenticating = false
            let error = AuthError.invalidCredential
            authError = "Invalid credential"
            os_log(.error, log: Logger.auth, "Invalid Apple credential")
            authCompletion?(.failure(error))
            authCompletion = nil
            return
        }

        let user = AuthUser(
            appleUserId: credential.user,
            email: credential.email,
            fullName: credential.fullName
        )

        os_log(.info, log: Logger.auth, "Apple Sign In successful for user: %@", credential.user.prefix(8).description)

        // Store Apple user ID and email in keychain
        KeychainService.saveAppleUserId(credential.user)
        if let email = credential.email {
            KeychainService.saveEmail(email)
            os_log(.info, log: Logger.auth, "Stored email: %@", email)
        }

        // Exchange Apple token with Supabase
        if let identityTokenData = credential.identityToken,
           let identityToken = String(data: identityTokenData, encoding: .utf8) {

            exchangeAppleTokenWithSupabase(
                identityToken: identityToken,
                appleUserId: credential.user
            ) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isAuthenticating = false

                    switch result {
                    case .success(let session):
                        // Store Supabase tokens
                        KeychainService.saveAccessToken(session.accessToken)
                        if let refreshToken = session.refreshToken {
                            KeychainService.saveRefreshToken(refreshToken)
                        }
                        os_log(.info, log: Logger.auth, "Supabase session established")
                        self?.authCompletion?(.success(user))

                    case .failure(let error):
                        self?.authError = error.localizedDescription
                        os_log(.error, log: Logger.auth, "Supabase auth failed: %@", error.localizedDescription)
                        // Still return success with Apple user, auth can work without Supabase
                        self?.authCompletion?(.success(user))
                    }

                    self?.authCompletion = nil
                }
            }
        } else {
            // No identity token, continue with Apple user only
            isAuthenticating = false
            os_log(.info, log: Logger.auth, "No identity token, proceeding without Supabase auth")
            authCompletion?(.success(user))
            authCompletion = nil
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        isAuthenticating = false

        let nsError = error as NSError
        if nsError.code == 1001 { // User cancelled
            authError = "Sign in cancelled"
            os_log(.info, log: Logger.auth, "User cancelled Sign in with Apple")
            authCompletion?(.failure(AuthError.cancelled))
        } else {
            authError = error.localizedDescription
            os_log(.error, log: Logger.auth, "Sign in with Apple failed: %@", error.localizedDescription)
            authCompletion?(.failure(error))
        }

        authCompletion = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the first window scene's key window
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available for presentation")
        }
        return window
    }
}

// MARK: - SupabaseSession Model

/// Supabase authentication session response
struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

/// Supabase user data
struct SupabaseUser: Codable {
    let id: String
    let email: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
    }
}
