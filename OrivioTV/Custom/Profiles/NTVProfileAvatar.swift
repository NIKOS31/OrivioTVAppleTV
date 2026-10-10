import Foundation

/// Bundled, small images remain available offline. Only their stable ID is saved.
enum NTVProfileAvatar: String, CaseIterable, Identifiable {
    case glasses = "ntv.glasses"
    case curls = "ntv.curls"
    case ginger = "ntv.ginger"
    case bob = "ntv.bob"
    case silver = "ntv.silver"
    case braids = "ntv.braids"
    case cap = "ntv.cap"
    case beard = "ntv.beard"
    case freckles = "ntv.freckles"
    case ponytail = "ntv.ponytail"
    case shortCurls = "ntv.shortcurls"
    case roundGlasses = "ntv.roundglasses"

    var id: String { rawValue }
    var assetName: String {
        switch self {
        case .glasses: return "NTVAvatarGlasses"
        case .curls: return "NTVAvatarCurls"
        case .ginger: return "NTVAvatarGinger"
        case .bob: return "NTVAvatarBob"
        case .silver: return "NTVAvatarSilver"
        case .braids: return "NTVAvatarBraids"
        case .cap: return "NTVAvatarCap"
        case .beard: return "NTVAvatarBeard"
        case .freckles: return "NTVAvatarFreckles"
        case .ponytail: return "NTVAvatarPonytail"
        case .shortCurls: return "NTVAvatarShortCurls"
        case .roundGlasses: return "NTVAvatarRoundGlasses"
        }
    }
    var title: String {
        switch self {
        case .glasses: return "Niko"
        case .curls: return "Lina"
        case .ginger: return "Émile"
        case .bob: return "Zoé"
        case .silver: return "Gabriel"
        case .braids: return "Inès"
        case .cap: return "Noé"
        case .beard: return "Adam"
        case .freckles: return "Lou"
        case .ponytail: return "Emma"
        case .shortCurls: return "Sacha"
        case .roundGlasses: return "Milo"
        }
    }
}
