import Foundation

/// Network sources: SMB 1/2/3, UPnP/DLNA, FTP/SFTP, NFS, WebDAV and streams,
/// with Bonjour discovery and Keychain-stored credentials. Browsing goes
/// through VLCKit's media discoverers via the PlaybackEngine package.
///
/// Status: placeholder. Built in Milestone 7. Stream URLs (HTTP, HLS, RTSP…)
/// already play today because the router sends them to the right engine.
public enum Networking {
    public static let plannedMilestone = 7
}
