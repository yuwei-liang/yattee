import Foundation

enum AppGroup {
    static let identifier = "group.com.yuweiliang.yattee.shared"
    static let enabledSectionsKey = "topShelf.enabledSections"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
