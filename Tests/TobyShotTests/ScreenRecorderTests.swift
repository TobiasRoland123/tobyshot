import Foundation
import ScreenCaptureKit
import Testing
@testable import TobyShot

@Suite(.serialized)
@MainActor
struct ScreenRecorderTests {
    enum StaleEvent: CaseIterable { case success, outputFailure, streamFailure }

    @Test(arguments: StaleEvent.allCases)
    func callbacksFromFinishedSessionCannotAffectTheActiveSession(event: StaleEvent) async throws {
        let recorder = ScreenRecorder()
        let oldResult = CompletionProbe()
        let old = try makeSession(recorder: recorder, completion: oldResult.append)
        defer { old.removeFile() }
        try await recorder.start(session: old.session)
        recorder.recordingOutputDidFinishRecording(old.output)
        try await oldResult.waitForCount(1)

        let activeResult = CompletionProbe()
        let active = try makeSession(recorder: recorder, size: CGSize(width: 640, height: 360), completion: activeResult.append)
        defer { active.removeFile() }
        try await recorder.start(session: active.session)

        switch event {
        case .success: recorder.recordingOutputDidFinishRecording(old.output)
        case .outputFailure: recorder.recordingOutput(old.output, didFailWithError: testError(1))
        case .streamFailure: recorder.stream(old.stream, didStopWithError: testError(2))
        }
        await drainCallbacks()
        #expect(activeResult.results.isEmpty)
        #expect(active.stream.stopCallCount == 0)
        #expect(FileManager.default.fileExists(atPath: active.file.path))

        recorder.recordingOutputDidFinishRecording(active.output)
        try await activeResult.waitForCount(1)

        #expect(oldResult.results.count == 1)
        #expect(activeResult.results.count == 1)
        #expect(try #require(try? activeResult.results.first?.get()) == active.file)
        #expect(recorder.size == active.size)
        #expect(FileManager.default.fileExists(atPath: old.file.path))
        #expect(FileManager.default.fileExists(atPath: active.file.path))
    }

    @Test func duplicateSuccessThenFailureCompletesOnlyOnce() async throws {
        let recorder = ScreenRecorder()
        let result = CompletionProbe()
        let session = try makeSession(recorder: recorder, completion: result.append)
        defer { session.removeFile() }
        try await recorder.start(session: session.session)

        recorder.recordingOutputDidFinishRecording(session.output)
        try await result.waitForCount(1)
        recorder.recordingOutputDidFinishRecording(session.output)
        recorder.recordingOutput(session.output, didFailWithError: testError(3))
        recorder.stream(session.stream, didStopWithError: testError(3))
        await drainCallbacks()

        #expect(result.results.count == 1)
        #expect(session.stream.stopCallCount == 0)
        #expect(try #require(try? result.results.first?.get()) == session.file)
        #expect(FileManager.default.fileExists(atPath: session.file.path))
    }

    @Test func duplicateFailureThenSuccessCompletesOnlyOnce() async throws {
        let recorder = ScreenRecorder()
        let result = CompletionProbe()
        let session = try makeSession(recorder: recorder, stopSuspended: true, completion: result.append)
        defer { session.removeFile() }
        try await recorder.start(session: session.session)

        recorder.recordingOutput(session.output, didFailWithError: testError(4))
        try await result.waitForCount(1)
        try await session.stream.waitForStopCount(1)
        recorder.recordingOutputDidFinishRecording(session.output)
        recorder.recordingOutput(session.output, didFailWithError: testError(4))
        recorder.stream(session.stream, didStopWithError: testError(4))
        await drainCallbacks()

        #expect(result.results.count == 1)
        #expect(session.stream.stopCallCount == 1)
        #expect(isError(result.results[0], code: 4))
        #expect(FileManager.default.fileExists(atPath: session.file.path))

        session.stream.resumeStop()
        try await waitForFile(session.file, toExist: false)
        #expect(result.results.count == 1)
    }

    @Test func suspendedFailureCleanupCannotRemoveOrStopRetry() async throws {
        let recorder = ScreenRecorder()
        let failedResult = CompletionProbe()
        let failed = try makeSession(recorder: recorder, stopSuspended: true, completion: failedResult.append)
        defer { failed.removeFile() }
        try await recorder.start(session: failed.session)

        recorder.recordingOutput(failed.output, didFailWithError: testError(5))
        try await failedResult.waitForCount(1)
        try await failed.stream.waitForStopCount(1)

        let retryResult = CompletionProbe()
        let retry = try makeSession(recorder: recorder, completion: retryResult.append)
        defer { retry.removeFile() }
        try await recorder.start(session: retry.session)
        recorder.recordingOutputDidFinishRecording(failed.output)
        recorder.recordingOutput(failed.output, didFailWithError: testError(6))
        recorder.stream(failed.stream, didStopWithError: testError(6))
        failed.stream.resumeStop(with: testError(6))
        try await waitForFile(failed.file, toExist: false)
        await drainCallbacks()

        #expect(FileManager.default.fileExists(atPath: retry.file.path))
        #expect(failedResult.results.count == 1)
        #expect(failed.stream.stopCallCount == 1)
        #expect(retry.stream.stopCallCount == 0)
        #expect(retryResult.results.isEmpty)

        recorder.recordingOutputDidFinishRecording(retry.output)
        try await retryResult.waitForCount(1)
        #expect(try #require(try? retryResult.results.first?.get()) == retry.file)
    }

    @Test func delayedStartFailureAfterRetryRemainsScopedToItsSession() async throws {
        let recorder = ScreenRecorder()
        let oldResult = CompletionProbe()
        let old = try makeSession(recorder: recorder, startSuspended: true, stopSuspended: true, completion: oldResult.append)
        defer { old.removeFile() }
        let oldStart = Task { try await recorder.start(session: old.session) }
        try await old.stream.waitForStartCount(1)

        recorder.stream(old.stream, didStopWithError: testError(7))
        try await oldResult.waitForCount(1)
        try await old.stream.waitForStopCount(1)

        let retryResult = CompletionProbe()
        let retry = try makeSession(recorder: recorder, completion: retryResult.append)
        defer { retry.removeFile() }
        try await recorder.start(session: retry.session)

        old.stream.resumeStart(with: testError(8))
        do {
            try await oldStart.value
            Issue.record("The suspended start should throw its injected error")
        } catch {
            #expect((error as NSError).code == 8)
        }
        #expect(FileManager.default.fileExists(atPath: retry.file.path))
        #expect(retry.stream.stopCallCount == 0)
        #expect(oldResult.results.count == 1)
        #expect(retryResult.results.isEmpty)

        recorder.recordingOutputDidFinishRecording(retry.output)
        try await retryResult.waitForCount(1)
        #expect(try #require(try? retryResult.results.first?.get()) == retry.file)

        old.stream.resumeStop()
        try await waitForFile(old.file, toExist: false)
    }

    @Test func delayedStopFailureAfterRetryRemainsScopedToItsSession() async throws {
        let recorder = ScreenRecorder()
        let oldResult = CompletionProbe()
        let old = try makeSession(recorder: recorder, stopSuspended: true, completion: oldResult.append)
        defer { old.removeFile() }
        try await recorder.start(session: old.session)
        let oldStop = Task { await recorder.stop() }
        try await old.stream.waitForStopCount(1)
        recorder.recordingOutputDidFinishRecording(old.output)
        try await oldResult.waitForCount(1)

        let retryResult = CompletionProbe()
        let retry = try makeSession(recorder: recorder, completion: retryResult.append)
        defer { retry.removeFile() }
        try await recorder.start(session: retry.session)
        old.stream.resumeStop(with: testError(9))
        await oldStop.value
        await drainCallbacks()

        #expect(oldResult.results.count == 1)
        #expect(old.stream.stopCallCount == 1)
        #expect(retryResult.results.isEmpty)
        #expect(retry.stream.stopCallCount == 0)
        #expect(FileManager.default.fileExists(atPath: old.file.path))
        #expect(FileManager.default.fileExists(atPath: retry.file.path))
        recorder.recordingOutputDidFinishRecording(retry.output)
        try await retryResult.waitForCount(1)
        #expect(try #require(try? retryResult.results.first?.get()) == retry.file)
    }

    @Test func startFailureThrowsAndCleansItsSessionWithoutCallingCompletion() async throws {
        let recorder = ScreenRecorder()
        let failedResult = CompletionProbe()
        let failed = try makeSession(recorder: recorder, startSuspended: true, stopSuspended: true, completion: failedResult.append)
        defer { failed.removeFile() }
        let start = Task { try await recorder.start(session: failed.session) }
        try await failed.stream.waitForStartCount(1)
        failed.stream.resumeStart(with: testError(10))
        do {
            try await start.value
            Issue.record("The suspended start should throw its injected error")
        } catch {
            #expect((error as NSError).code == 10)
        }
        try await failed.stream.waitForStopCount(1)

        let retryResult = CompletionProbe()
        let retry = try makeSession(recorder: recorder, completion: retryResult.append)
        defer { retry.removeFile() }
        try await recorder.start(session: retry.session)
        failed.stream.resumeStop()
        try await waitForFile(failed.file, toExist: false)
        #expect(failedResult.results.isEmpty)
        #expect(retryResult.results.isEmpty)
        #expect(retry.stream.stopCallCount == 0)
        #expect(FileManager.default.fileExists(atPath: retry.file.path))
        recorder.recordingOutputDidFinishRecording(retry.output)
        try await retryResult.waitForCount(1)
        #expect(try #require(try? retryResult.results.first?.get()) == retry.file)
    }

    @Test func startRejectsAnOverlappingSessionWithoutReplacingTheOwner() async throws {
        let recorder = ScreenRecorder()
        let activeResult = CompletionProbe()
        let active = try makeSession(recorder: recorder, completion: activeResult.append)
        defer { active.removeFile() }
        try await recorder.start(session: active.session)

        let rejectedResult = CompletionProbe()
        let rejected = try makeSession(recorder: recorder, completion: rejectedResult.append)
        defer { rejected.removeFile() }
        do {
            try await recorder.start(session: rejected.session)
            Issue.record("An overlapping session should be rejected")
        } catch {
            #expect(rejectedResult.results.isEmpty)
        }

        recorder.recordingOutputDidFinishRecording(active.output)
        try await activeResult.waitForCount(1)
        #expect(try #require(try? activeResult.results.first?.get()) == active.file)
        #expect(rejectedResult.results.isEmpty)
    }
}

@MainActor
private final class ControlledStream: SCStream {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuations: [CheckedContinuation<Void, Error>] = []
    private var startSuspended: Bool
    private var stopSuspended: Bool

    init(delegate: SCStreamDelegate?, startSuspended: Bool, stopSuspended: Bool) {
        self.startSuspended = startSuspended
        self.stopSuspended = stopSuspended
        super.init(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: delegate)
    }

    override func addRecordingOutput(_ recordingOutput: SCRecordingOutput) throws {}

    override func startCapture() async throws {
        startCallCount += 1
        guard startSuspended else { return }
        try await withCheckedThrowingContinuation { startContinuation = $0 }
    }

    override func stopCapture() async throws {
        stopCallCount += 1
        guard stopSuspended else { return }
        try await withCheckedThrowingContinuation { stopContinuations.append($0) }
    }

    func waitForStartCount(_ count: Int) async throws {
        try await waitUntil { self.startCallCount >= count }
    }

    func waitForStopCount(_ count: Int) async throws {
        try await waitUntil { self.stopCallCount >= count }
    }

    func resumeStart(with error: Error? = nil) {
        guard let continuation = startContinuation else { Issue.record("No suspended startCapture call"); return }
        startContinuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    func resumeStop(with error: Error? = nil) {
        guard !stopContinuations.isEmpty else { Issue.record("No suspended stopCapture call"); return }
        let continuation = stopContinuations.removeFirst()
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    func cancelPendingCalls() {
        startSuspended = false; stopSuspended = false
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        let pending = stopContinuations
        stopContinuations = []
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }
}

@MainActor
private final class CompletionProbe {
    private(set) var results: [Result<URL, Error>] = []

    func append(_ result: Result<URL, Error>) { results.append(result) }

    func waitForCount(_ count: Int) async throws {
        try await waitUntil { self.results.count >= count }
    }
}

@MainActor
private struct SessionFixture {
    let session: ScreenRecorder.Session
    let stream: ControlledStream
    var output: SCRecordingOutput { session.output }
    var file: URL { session.file }
    var size: CGSize { session.size }

    func removeFile() {
        stream.cancelPendingCalls()
        try? FileManager.default.removeItem(at: file)
    }
}

@MainActor
private func makeSession(
    recorder: ScreenRecorder,
    size: CGSize = CGSize(width: 320, height: 200),
    startSuspended: Bool = false,
    stopSuspended: Bool = false,
    completion: @escaping (Result<URL, Error>) -> Void
) throws -> SessionFixture {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("TobyShot-test-\(UUID().uuidString).mp4")
    try Data([1, 2, 3]).write(to: file)
    let configuration = SCRecordingOutputConfiguration()
    configuration.outputURL = file
    configuration.outputFileType = .mp4
    configuration.videoCodecType = .h264
    let output = SCRecordingOutput(configuration: configuration, delegate: recorder)
    let stream = ControlledStream(delegate: recorder, startSuspended: startSuspended, stopSuspended: stopSuspended)
    let session = ScreenRecorder.Session(stream: stream, output: output, file: file, size: size, completion: completion)
    return SessionFixture(session: session, stream: stream)
}

@MainActor
private func waitForFile(_ file: URL, toExist expected: Bool) async throws {
    try await waitUntil { FileManager.default.fileExists(atPath: file.path) == expected }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    try #require(condition(), "Timed out waiting for the recording callback or stream operation")
}

@MainActor
private func drainCallbacks() async {
    // Let queued delegate tasks and their cleanup tasks run before checking for no effects.
    for _ in 0..<2 {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

private func testError(_ code: Int) -> NSError {
    NSError(domain: "ScreenRecorderTests", code: code)
}

private func isError(_ result: Result<URL, Error>, code: Int) -> Bool {
    guard case let .failure(error) = result else { return false }
    return (error as NSError).code == code
}
