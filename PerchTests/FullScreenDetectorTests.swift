import CoreGraphics
import Testing
@testable import Perch

struct FullScreenDetectorTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    private let external = CGRect(x: 1710, y: 0, width: 2560, height: 1440)
    private var screens: [CGDirectDisplayID: CGRect] { [1: builtIn, 2: external] }

    @Test func fullScreenWindowCoversOnlyItsScreen() {
        let video = FullScreenDetector.Window(bounds: builtIn, layer: 0, ownerPID: 42)
        #expect(FullScreenDetector.coveringOwners(windows: [video], screens: screens, ownPID: 1) == [1: 42])
    }

    @Test func fullScreenBelowTheNotchCounts() {
        // What QuickTime reports in full screen on a 14" MacBook: under the notch band.
        let video = FullScreenDetector.Window(bounds: CGRect(x: 0, y: 34, width: 1710, height: 1073), layer: 0, ownerPID: 42)
        #expect(FullScreenDetector.coveringOwners(windows: [video], screens: screens, ownPID: 1) == [1: 42])
    }

    @Test func maximisedWindowAboveTheDockDoesNotCount() {
        let zoomed = FullScreenDetector.Window(bounds: CGRect(x: 0, y: 33, width: 1710, height: 1000), layer: 0, ownerPID: 42)
        #expect(FullScreenDetector.coveringOwners(windows: [zoomed], screens: screens, ownPID: 1).isEmpty)
    }

    @Test func ownAndOverlayWindowsAreIgnored() {
        let own = FullScreenDetector.Window(bounds: builtIn, layer: 0, ownerPID: 1)
        let shield = FullScreenDetector.Window(bounds: external, layer: 25, ownerPID: 42)
        #expect(FullScreenDetector.coveringOwners(windows: [own, shield], screens: screens, ownPID: 1).isEmpty)
    }

    @Test func frontmostFullScreenWindowWins() {
        let claude = FullScreenDetector.Window(bounds: builtIn, layer: 0, ownerPID: 7)
        let behind = FullScreenDetector.Window(bounds: builtIn, layer: 0, ownerPID: 8)
        #expect(FullScreenDetector.coveringOwners(windows: [claude, behind], screens: screens, ownPID: 1) == [1: 7])
    }

    @Test func onlyVideoCountsAsWatching() {
        // YouTube in a full-screen browser that is playing: hide.
        #expect(FullScreenDetector.isWatchingVideo(owner: "com.microsoft.edgemac", mediaSource: "com.microsoft.edgemac"))
        // Claude in full screen while Spotify plays: keep the notch.
        #expect(!FullScreenDetector.isWatchingVideo(owner: "com.anthropic.claudefordesktop", mediaSource: "com.spotify.client"))
        // A video player, even paused or not reporting: hide.
        #expect(FullScreenDetector.isWatchingVideo(owner: "com.colliderli.iina", mediaSource: nil))
        // Spotify itself in full screen is music, not video.
        #expect(!FullScreenDetector.isWatchingVideo(owner: "com.spotify.client", mediaSource: "com.spotify.client"))
    }
}
