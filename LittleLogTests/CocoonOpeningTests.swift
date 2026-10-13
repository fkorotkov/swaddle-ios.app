import Testing

@testable import BabyActivityRecorder

@MainActor
struct CocoonOpeningTests {
  @Test func openingCanOnlyBeClaimedOnceAcrossLayoutCandidates() {
    let session = CocoonOpeningSession()
    #expect(session.claim(reduceMotion: false))
    #expect(!session.claim(reduceMotion: false))
    #expect(!session.isSettled)
    session.settle()
    #expect(session.isSettled)
    #expect(!session.claim(reduceMotion: false))
  }

  @Test func routingBeforeTheHeaderAppearsSkipsDecoration() {
    let session = CocoonOpeningSession()
    session.settle()
    #expect(!session.claim(reduceMotion: false))
    #expect(session.isSettled)
  }

  @Test func reducedMotionAndInterruptionNeverReplayTheOpening() {
    let reduced = CocoonOpeningSession()
    #expect(!reduced.claim(reduceMotion: true))
    #expect(reduced.isSettled)
    #expect(!reduced.claim(reduceMotion: false))

    let interrupted = CocoonOpeningSession()
    #expect(interrupted.claim(reduceMotion: false))
    interrupted.settle()
    interrupted.settle()
    #expect(!interrupted.claim(reduceMotion: false))
  }
}
