#if DEBUG
import Libavutil
import TVVLCKit

/// Uses linked libraries' own version APIs; package/header numbers can differ.
enum NTVMediaDependencyAudit {
    static var ffmpegVersion: String { String(cString: av_version_info()) }
    static var vlcVersion: String { VLCLibrary.shared().version }
}
#endif
