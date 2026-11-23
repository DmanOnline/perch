import Foundation
import Testing
@testable import Perch

struct NowPlayingStreamTests {
    private func line(_ json: String) -> Data { Data(json.utf8) }

    private let full = """
    {"type":"data","diff":false,"payload":{"title":"Song","artist":"Band","album":"LP",\
    "playing":true,"playbackRate":1,"durationMicros":200000000,"elapsedTimeMicros":10000000,\
    "timestampEpochMicros":1700000000000000,"bundleIdentifier":"com.spotify.client"}}
    """

    @Test func fullPayloadBecomesState() throws {
        var stream = NowPlayingStream()
        let state = try #require(stream.consume(line(full)) ?? nil)
        #expect(state.title == "Song")
        #expect(state.artist == "Band")
        #expect(state.isPlaying)
        #expect(state.duration == 200)
        #expect(state.elapsed == 10)
        #expect(state.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(state.bundleID == "com.spotify.client")
    }

    @Test func diffUpdatesOnlyChangedKeys() throws {
        var stream = NowPlayingStream()
        _ = stream.consume(line(full))
        let state = try #require(stream.consume(line(#"{"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0}}"#)) ?? nil)
        #expect(!state.isPlaying)
        #expect(state.title == "Song")
    }

    @Test func nullInDiffRemovesKey() throws {
        var stream = NowPlayingStream()
        _ = stream.consume(line(full))
        let state = try #require(stream.consume(line(#"{"type":"data","diff":true,"payload":{"artist":null}}"#)) ?? nil)
        #expect(state.artist == "")
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        var stream = NowPlayingStream()
        _ = stream.consume(line(full))
        let result = stream.consume(line(#"{"type":"data","diff":false,"payload":{}}"#))
        #expect(result != nil)
        #expect(result! == nil)
    }

    @Test func garbageLineIsIgnored() {
        var stream = NowPlayingStream()
        #expect(stream.consume(line("not json")) == nil)
    }

    @Test func artworkIsDecodedAndKeptAcrossDiffs() throws {
        var stream = NowPlayingStream()
        let bytes = Data([1, 2, 3, 4])
        _ = stream.consume(line(#"{"type":"data","diff":false,"payload":{"title":"A","artworkData":"\#(bytes.base64EncodedString())"}}"#))
        let state = try #require(stream.consume(line(#"{"type":"data","diff":true,"payload":{"artist":"B"}}"#)) ?? nil)
        #expect(state.artwork == bytes)
    }

    @Test func elapsedIsExtrapolatedWhilePlaying() {
        let start = Date(timeIntervalSince1970: 1000)
        var state = NowPlaying(title: "A", artist: "", album: "", duration: 100, elapsed: 10,
                               timestamp: start, rate: 1, isPlaying: true, bundleID: nil, artwork: nil)
        #expect(state.elapsed(at: start + 5) == 15)
        #expect(state.elapsed(at: start + 500) == 100)
        state.isPlaying = false
        #expect(state.elapsed(at: start + 5) == 10)
    }
}
