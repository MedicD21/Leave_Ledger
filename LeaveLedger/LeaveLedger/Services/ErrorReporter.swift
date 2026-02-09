import Foundation
import OSLog

/// Centralized error reporting infrastructure.
/// This service logs errors and can be extended to integrate with third-party
/// crash reporting services like Sentry, Firebase Crashlytics, or Bugsnag.
enum ErrorReporter {
    /// Error severity levels for prioritization and filtering
    enum Severity: String {
        case debug
        case info
        case warning
        case error
        case fatal
    }

    /// Reports an error with context information
    /// - Parameters:
    ///   - error: The error to report
    ///   - severity: The severity level of the error
    ///   - context: Additional context about where/why the error occurred
    ///   - file: The file where the error occurred (automatically captured)
    ///   - function: The function where the error occurred (automatically captured)
    ///   - line: The line number where the error occurred (automatically captured)
    static func report(
        _ error: Error,
        severity: Severity = .error,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = (file as NSString).lastPathComponent
        let location = "\(fileName):\(line) \(function)"

        // Log to OSLog with appropriate level
        let logLevel: OSLogType = {
            switch severity {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error, .fatal: return .error
            }
        }()

        os_log(logLevel, log: Logger.general,
               "[%@] Error at %@: %@",
               severity.rawValue.uppercased(),
               location,
               error.localizedDescription)

        // Log context if provided
        if let context = context, !context.isEmpty {
            let contextString = context.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            os_log(logLevel, log: Logger.general, "Context: %@", contextString)
        }

        // Future: Integrate with third-party crash reporting service if needed
    }

    /// Reports a message without an associated error
    /// - Parameters:
    ///   - message: The message to report
    ///   - severity: The severity level
    ///   - context: Additional context
    ///   - file: The file where the message was logged
    ///   - function: The function where the message was logged
    ///   - line: The line number where the message was logged
    static func reportMessage(
        _ message: String,
        severity: Severity = .info,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = (file as NSString).lastPathComponent
        let location = "\(fileName):\(line) \(function)"

        let logLevel: OSLogType = {
            switch severity {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error, .fatal: return .error
            }
        }()

        os_log(logLevel, log: Logger.general,
               "[%@] %@ at %@",
               severity.rawValue.uppercased(),
               message,
               location)

        if let context = context, !context.isEmpty {
            let contextString = context.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            os_log(logLevel, log: Logger.general, "Context: %@", contextString)
        }

        // Future: Integrate with third-party service if needed
    }

    /// Sets a user identifier for error tracking (useful for debugging specific user issues)
    /// - Parameter userId: The user identifier
    static func setUser(_ userId: String) {
        os_log(.info, log: Logger.general, "User identified: %@", userId)
        // Future: Set user in crash reporting service if needed
    }

    /// Adds breadcrumb information for debugging error context
    /// - Parameters:
    ///   - message: The breadcrumb message
    ///   - category: The category of the breadcrumb (e.g., "navigation", "user_action")
    ///   - data: Additional data for the breadcrumb
    static func addBreadcrumb(
        message: String,
        category: String? = nil,
        data: [String: Any]? = nil
    ) {
        var logMessage = "Breadcrumb: \(message)"
        if let category = category {
            logMessage += " [\(category)]"
        }
        os_log(.debug, log: Logger.general, "%@", logMessage)

        // Future: Add breadcrumb to crash reporting service if needed
    }
}

// MARK: - Convenience Extensions

extension ErrorReporter {
    /// Reports a data persistence error
    static func reportDataStoreError(_ error: Error, operation: String) {
        report(error, severity: .error, context: [
            "component": "DataStore",
            "operation": operation
        ])
    }

    /// Reports a network error
    static func reportNetworkError(_ error: Error, endpoint: String) {
        report(error, severity: .error, context: [
            "component": "Network",
            "endpoint": endpoint
        ])
    }

    /// Reports an export error
    static func reportExportError(_ error: Error, type: String) {
        report(error, severity: .warning, context: [
            "component": "Export",
            "type": type
        ])
    }
}
