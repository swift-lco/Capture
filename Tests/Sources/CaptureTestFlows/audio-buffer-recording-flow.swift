import Capture
import Foundation
import MediaCore
import TestFlows

extension CaptureFlowSuite {
    static var audioBufferRecordingFlow: TestFlow {
        TestFlow(
            "audio-buffer-recording",
            tags: [
                "audio",
                "buffer",
                "recording",
            ]
        ) {
            Step("finite recording result preserves Media buffers") {
                let start = CaptureAudioInputStartResult(
                    device: CaptureDevice(
                        id: "test-mic",
                        name: "Test microphone",
                        kind: .audio_input
                    ),
                    sampleRate: 48_000,
                    channelCount: 1
                )
                let first = MediaAudioBuffer(
                    data: Data(),
                    frameCount: 4_800,
                    packetCount: 4_800,
                    sampleRate: 48_000,
                    channelCount: 1,
                    sample: .float32,
                    hostTimeSeconds: 12.5
                )
                let second = MediaAudioBuffer(
                    data: Data(),
                    frameCount: 4_800,
                    packetCount: 4_800,
                    sampleRate: 48_000,
                    channelCount: 1,
                    sample: .float32,
                    hostTimeSeconds: 12.6
                )
                let result = CaptureAudioBufferRecordingResult(
                    start: start,
                    buffers: [
                        first,
                        second,
                    ],
                    firstSampleHostTimeSeconds: 12.5
                )

                try Expect.equal(
                    result.bufferCount,
                    2,
                    "audio-buffer-recording.buffer-count"
                )
                try Expect.equal(
                    result.frameCount,
                    9_600,
                    "audio-buffer-recording.frame-count"
                )
                try Expect.equal(
                    result.isEmpty,
                    false,
                    "audio-buffer-recording.nonempty"
                )
                try Expect.equal(
                    result.firstSampleHostTimeSeconds,
                    12.5,
                    "audio-buffer-recording.first-host-time"
                )
                try Expect.equal(
                    result.start.device.id,
                    "test-mic",
                    "audio-buffer-recording.device"
                )
                try Expect.equal(
                    result.buffers.first?.sample,
                    .float32,
                    "audio-buffer-recording.media-sample"
                )
            }

            Step("recording status derives duration and latest RMS level") {
                let sampleData = [
                    Float(0.5),
                    Float(-0.5),
                ].withUnsafeBufferPointer { samples in
                    Data(
                        bytes: samples.baseAddress!,
                        count: samples.count
                            * MemoryLayout<Float>.size
                    )
                }

                let buffer = MediaAudioBuffer(
                    data: sampleData,
                    frameCount: 2,
                    packetCount: 2,
                    sampleRate: 4,
                    channelCount: 1,
                    sample: .float32,
                    hostTimeSeconds: nil
                )
                let status = CaptureAudioBufferRecordingStatus(
                    durationSeconds: 0.5,
                    rmsAmplitude: buffer.rmsAmplitude
                )

                try Expect.equal(
                    status.durationSeconds,
                    0.5,
                    "audio-buffer-recording.status-duration"
                )

                try Expect.equal(
                    status.rmsAmplitude,
                    0.5,
                    "audio-buffer-recording.status-rms"
                )
            }

            Step("empty finite recording result is explicit") {
                let result = CaptureAudioBufferRecordingResult(
                    start: CaptureAudioInputStartResult(
                        device: CaptureDevice(
                            id: "test-mic",
                            name: "Test microphone",
                            kind: .audio_input
                        ),
                        sampleRate: 48_000,
                        channelCount: 1
                    ),
                    buffers: [],
                    firstSampleHostTimeSeconds: nil
                )

                try Expect.equal(
                    result.isEmpty,
                    true,
                    "audio-buffer-recording.empty"
                )
                try Expect.equal(
                    result.frameCount,
                    0,
                    "audio-buffer-recording.empty-frame-count"
                )
            }
        }
    }
}