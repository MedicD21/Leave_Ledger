import UIKit

extension Bundle {
    /// Returns the app icon as a UIImage
    var icon: UIImage? {
        // Try to get the primary app icon name from the Info.plist
        guard let iconsDictionary = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIconsDictionary = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIconsDictionary["CFBundleIconFiles"] as? [String],
              let lastIcon = iconFiles.last else {
            return nil
        }

        // Try to load the icon image
        return UIImage(named: lastIcon)
    }
}
