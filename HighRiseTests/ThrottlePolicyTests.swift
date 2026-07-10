import Testing
@testable import HighRise

/// Pacing math is pure and deterministic (jitter aside, which is injected here),
/// so the schedule that protects the user's mailbox from rate limits is pinned.
struct ThrottlePolicyTests {

    @Test("Base delay applies after every message except the last")
    func baseDelayBetweenMessages() {
        let policy = ThrottlePolicy(baseDelay: 1.5)
        #expect(policy.delayAfter(index: 0, count: 3, randomFraction: { 0 }) == 1.5)
        #expect(policy.delayAfter(index: 1, count: 3, randomFraction: { 0 }) == 1.5)
        // Nothing follows the final message.
        #expect(policy.delayAfter(index: 2, count: 3, randomFraction: { 0 }) == 0)
    }

    @Test("Jitter adds a fraction of its max, from the injected source")
    func jitterAddsToDelay() {
        let policy = ThrottlePolicy(baseDelay: 1, jitter: 2)
        #expect(policy.delayAfter(index: 0, count: 10, randomFraction: { 0 }) == 1.0)
        #expect(policy.delayAfter(index: 0, count: 10, randomFraction: { 0.5 }) == 2.0)
        #expect(policy.delayAfter(index: 0, count: 10, randomFraction: { 1 }) == 3.0)
    }

    @Test("A full batch adds the batch pause on top of the base delay")
    func batchPauseAfterEachBatch() {
        let policy = ThrottlePolicy(baseDelay: 0.5, batchSize: 3, batchPause: 60)
        // Indices 0,1 are mid-batch → base only.
        #expect(policy.delayAfter(index: 0, count: 10, randomFraction: { 0 }) == 0.5)
        #expect(policy.delayAfter(index: 1, count: 10, randomFraction: { 0 }) == 0.5)
        // Index 2 completes a batch of 3 → base + pause.
        #expect(policy.delayAfter(index: 2, count: 10, randomFraction: { 0 }) == 60.5)
        // Index 5 completes the next batch.
        #expect(policy.delayAfter(index: 5, count: 10, randomFraction: { 0 }) == 60.5)
    }

    @Test("Batching is off when batchSize is zero")
    func noBatchingWhenZero() {
        let policy = ThrottlePolicy(baseDelay: 0.2, batchSize: 0, batchPause: 60)
        for i in 0..<9 {
            #expect(policy.delayAfter(index: i, count: 10, randomFraction: { 0 }) == 0.2)
        }
    }

    @Test("Negative inputs are clamped to zero")
    func clampsNegatives() {
        let policy = ThrottlePolicy(baseDelay: -1, jitter: -1, batchSize: -5, batchPause: -10)
        #expect(policy.baseDelay == 0)
        #expect(policy.jitter == 0)
        #expect(policy.batchSize == 0)
        #expect(policy.batchPause == 0)
    }

    @Test("Expected duration sums the gaps between messages")
    func expectedDurationBaseAndJitter() {
        // 10 messages → 9 gaps. baseDelay 2 + mean jitter (4/2=2) = 4s per gap.
        let policy = ThrottlePolicy(baseDelay: 2, jitter: 4)
        #expect(policy.expectedDuration(forCount: 10) == 36)      // 9 * 4
        #expect(policy.expectedDuration(forCount: 1) == 0)        // nothing to wait on
        #expect(policy.expectedDuration(forCount: 0) == 0)
    }

    @Test("Expected duration includes batch pauses")
    func expectedDurationWithBatches() {
        // 100 messages, base 1, no jitter, pause 60s every 25.
        // 99 gaps * 1 = 99, plus floor(99/25)=3 batch pauses * 60 = 180 → 279.
        let policy = ThrottlePolicy(baseDelay: 1, jitter: 0, batchSize: 25, batchPause: 60)
        #expect(policy.expectedDuration(forCount: 100) == 279)
    }

    @Test("humanDuration formats seconds, minutes, and hours")
    func humanDurationFormatting() {
        #expect(ThrottlePolicy.humanDuration(0) == "instant")
        #expect(ThrottlePolicy.humanDuration(45) == "~45s")
        #expect(ThrottlePolicy.humanDuration(120) == "~2 min")
        #expect(ThrottlePolicy.humanDuration(150) == "~2 min 30s")
        #expect(ThrottlePolicy.humanDuration(3600) == "~1 hr")
        #expect(ThrottlePolicy.humanDuration(3900) == "~1 hr 5 min")
    }

    @Test("Stops early once consecutive failures reach the threshold")
    func stopsAtThreshold() {
        let policy = ThrottlePolicy()
        #expect(policy.stopOnRepeatedFailures == true)   // on by default
        #expect(policy.shouldStopEarly(consecutiveFailures: 0) == false)
        #expect(policy.shouldStopEarly(consecutiveFailures: ThrottlePolicy.consecutiveFailureStopThreshold - 1) == false)
        #expect(policy.shouldStopEarly(consecutiveFailures: ThrottlePolicy.consecutiveFailureStopThreshold) == true)
        #expect(policy.shouldStopEarly(consecutiveFailures: ThrottlePolicy.consecutiveFailureStopThreshold + 5) == true)
    }

    @Test("Never stops early when the toggle is off")
    func noStopWhenDisabled() {
        let policy = ThrottlePolicy(stopOnRepeatedFailures: false)
        #expect(policy.shouldStopEarly(consecutiveFailures: 100) == false)
    }
}

struct SendingProviderTests {

    @Test("Warns only when the recipient count exceeds the provider cap")
    func warnsOverCap() {
        #expect(SendingProvider.gmailPersonal.quotaWarning(forRecipientCount: 400) == nil)
        let warning = SendingProvider.gmailPersonal.quotaWarning(forRecipientCount: 600)
        #expect(warning != nil)
        #expect(warning?.contains("500") == true)
    }

    @Test("Unknown providers never warn")
    func otherNeverWarns() {
        #expect(SendingProvider.other.approximateDailyCap == nil)
        #expect(SendingProvider.other.quotaWarning(forRecipientCount: 100_000) == nil)
    }

    @Test("Caps are ordered as expected across providers")
    func capsPresent() {
        #expect(SendingProvider.outlookCom.approximateDailyCap == 300)
        #expect(SendingProvider.googleWorkspace.approximateDailyCap == 2000)
        #expect(SendingProvider.microsoft365.approximateDailyCap == 10000)
    }
}
