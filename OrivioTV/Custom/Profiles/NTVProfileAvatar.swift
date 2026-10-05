import Foundation

/// Bundled, small images remain available offline. Only their stable ID is saved.
enum NTVProfileAvatar: String, CaseIterable, Identifiable {
    case glasses = "ntv.glasses"
    case curls = "ntv.curls"
    case ginger = "ntv.ginger"

    var id: String { rawValue }
    var assetName: String {
        switch self {
        case .glasses: return "NTVAvatarGlasses"
        case .curls: return "NTVAvatarCurls"
        case .ginger: return "NTVAvatarGinger"
        }
    }
    var title: String {
        switch self {
        case .glasses: return "Lunettes"
        case .curls: return "Boucles"
        case .ginger: return "Roux"
        }
    }
}
