import XCTest
@testable import LatteReader

@MainActor
final class PlaybackControlsTests: XCTestCase {
    var playbackControls: PlaybackControls!
    var mockKokoroReader: KokoroSpeechReader!
    var mockPiperReader: KokoroSpeechReader!
    
    override func setUp() async throws {
        playbackControls = PlaybackControls()
        mockKokoroReader = KokoroSpeechReader()
        mockPiperReader = KokoroSpeechReader(primary: PiperVoiceEngine(), fallback: PiperVoiceEngine())
        playbackControls.setEngines(kokoro: mockKokoroReader, piper: mockPiperReader)
    }
    
    func testInitialState() {
        XCTAssertFalse(playbackControls.canSkipBackward, "Should not be able to skip backward initially")
        XCTAssertFalse(playbackControls.canSkipForward, "Should not be able to skip forward initially")
    }
    
    func testSetActiveEngine() {
        playbackControls.setActiveEngine(.kokoro)
        playbackControls.updateSkipCapabilities()
        
        // Initially false as no segments loaded
        XCTAssertFalse(playbackControls.canSkipBackward)
        XCTAssertFalse(playbackControls.canSkipForward)
    }
    
    func testSkipCapabilitiesWithSegments() {
        // Create test segments
        let segments = [
            PlannedSpeechSegment(text: "First", voiceIdentifier: nil, kokoroVoiceID: "af_heart", piperModelPath: nil, speakerName: "Narrator"),
            PlannedSpeechSegment(text: "Second", voiceIdentifier: nil, kokoroVoiceID: "af_heart", piperModelPath: nil, speakerName: "Narrator"),
            PlannedSpeechSegment(text: "Third", voiceIdentifier: nil, kokoroVoiceID: "af_heart", piperModelPath: nil, speakerName: "Narrator")
        ]
        
        mockKokoroReader.start(segments: segments, rate: 1.0)
        playbackControls.setActiveEngine(.kokoro)
        playbackControls.updateSkipCapabilities()
        
        // At start: can't skip backward, can skip forward
        XCTAssertFalse(playbackControls.canSkipBackward, "Cannot skip backward from first segment")
        XCTAssertTrue(playbackControls.canSkipForward, "Can skip forward from first segment")
    }
}
