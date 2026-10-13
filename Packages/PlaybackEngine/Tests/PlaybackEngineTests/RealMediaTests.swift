#if os(macOS)
import Testing

/// Every suite that plays real media in a real window lives in here, so they
/// run one at a time: several libVLC instances drawing at once trip libVLC's
/// OpenGL checks, which abort the process in VLCKit's development builds.
@Suite("Playback with real media", .serialized)
struct RealMediaTests {}
#endif
