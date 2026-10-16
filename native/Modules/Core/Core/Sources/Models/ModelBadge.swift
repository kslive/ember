import Foundation

/// Optional highlight on a model card ("model.badge.*" localization keys).
public enum ModelBadge: Hashable, Sendable {
    case recommended
    case balanced
}
