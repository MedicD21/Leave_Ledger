import Foundation
import OSLog

/// Centralized logging for the Leave Ledger app using OSLog.
/// Provides structured logging with different log levels for debugging and production.
enum Logger {
    private static let subsystem = "com.leaveLedger"

    static let dataStore = OSLog(subsystem: subsystem, category: "DataStore")
    static let sync = OSLog(subsystem: subsystem, category: "Sync")
    static let export = OSLog(subsystem: subsystem, category: "Export")
    static let viewModel = OSLog(subsystem: subsystem, category: "ViewModel")
    static let network = OSLog(subsystem: subsystem, category: "Network")
    static let keychain = OSLog(subsystem: subsystem, category: "Keychain")
    static let general = OSLog(subsystem: subsystem, category: "General")
}
