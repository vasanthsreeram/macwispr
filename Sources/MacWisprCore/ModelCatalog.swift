import Foundation

/// The speech model MacWispr ships. The product runs exactly one model —
/// Moondream's Parakeet Redux — so there is nothing for the user to pick.
public enum ModelCatalog {
    /// `ASRModelSize` raw value of the only shipped model.
    public static let shippedModelID = "Parakeet-Redux"
    /// Hugging Face repo for the shipped model.
    public static let shippedRepoID = "moondream/parakeet-redux"
    public static let shippedDisplayName = "Parakeet Redux"
    public static let shippedDownloadLabel = "about 180 MB"

    /// Every model the app offers. One entry by design.
    public static let available: [String] = [shippedModelID]

    public static var defaultModelID: String { shippedModelID }

    /// Saved selections from older builds (Qwen 0.6B / 1.7B, Parakeet v3 INT4/INT8,
    /// unknown values, or nothing) all resolve to the shipped model.
    public static func migrate(savedModelID: String?) -> String {
        guard let saved = savedModelID, available.contains(saved) else {
            return defaultModelID
        }
        return saved
    }
}

/// Destinations in the main window sidebar.
public enum MainPane: String, CaseIterable, Sendable {
    case home
    case history
    case settings

    public var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
