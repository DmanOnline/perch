import AudioToolbox
import Foundation
import Testing
@testable import Perch

@Suite struct BandAnalyzerTests {
    /// Feeds `seconds` of a sine in 512-frame mono blocks, returns the last levels.
    private func levels(frequency: Float, amplitude: Float = 0.5, seconds: Float = 0.5) -> [Float] {
        let rate: Float = 48000
        let analyzer = BandAnalyzer(sampleRate: rate, channels: 1, interleaved: true)
        var result: [Float] = []
        var phase = 0
        for _ in 0..<Int(rate * seconds / 512) {
            var block = (0..<512).map { amplitude * sin(2 * .pi * frequency * Float(phase + $0) / rate) }
            phase += 512
            block.withUnsafeMutableBytes { bytes in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                if let out = analyzer.feed(UnsafeMutableAudioBufferListPointer(&list)) { result = out.levels }
            }
        }
        return result
    }

    @Test func bassToneLightsTheFirstBar() {
        let bars = levels(frequency: 80)
        #expect(bars[0] > 0.8)
        #expect(bars[3] < bars[0])
    }

    @Test func trebleToneLightsTheLastBar() {
        let bars = levels(frequency: 6000)
        #expect(bars[3] > 0.8)
        #expect(bars[0] < bars[3])
    }

    @Test func silenceLeavesTheBarsDown() {
        #expect(levels(frequency: 200, amplitude: 0).allSatisfy { $0 == 0 })
    }
}
