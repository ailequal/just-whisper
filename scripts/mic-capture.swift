// Microphone recorder for scripts/record.sh, scripts/live.sh and scripts/devices.sh.
//
//   mic-capture devices                           one "[index] name" line per audio input
//   mic-capture record <index> <out.wav> [seconds]
//
// It records what the device delivers, at its own sample rate and channel count, as a 24-bit WAV.
// ffmpeg's avfoundation input is not used for capture: it loses about one audio buffer in ten.
// Every buffer is checked against the timestamp of the previous one, so lost audio is reported.
// Stop with q (when started from a terminal), Ctrl+C, SIGTERM, or after the given seconds.
// Built by need_mic_capture in scripts/lib/common.sh: swiftc -O -o .build/mic-capture scripts/mic-capture.swift

import AVFoundation
import Accelerate
import Foundation

var savedTerminal: termios?

func say(_ text: String) {
  FileHandle.standardError.write(Data(text.utf8))
}

func restoreTerminal() {
  if var saved = savedTerminal {
    tcsetattr(STDIN_FILENO, TCSANOW, &saved)
    savedTerminal = nil
  }
}

func fail(_ message: String) -> Never {
  restoreTerminal()
  say("mic-capture: \(message)\n")
  exit(1)
}

// The same list, in the same order, as ffmpeg's avfoundation input.
func inputDevices() -> [AVCaptureDevice] {
  let types: [AVCaptureDevice.DeviceType]
  if #available(macOS 14.0, *) {
    types = [.microphone]
  } else {
    types = [.builtInMicrophone]
  }
  return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified).devices
}

func requireMicrophoneAccess() {
  let denied = "the microphone is not permitted for this terminal app: System Settings, Privacy & Security, Microphone"
  switch AVCaptureDevice.authorizationStatus(for: .audio) {
  case .authorized:
    return
  case .notDetermined:
    let answered = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .audio) { _ in answered.signal() }
    answered.wait()
    if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { fail(denied) }
  default:
    fail(denied)
  }
}

final class Recorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
  let queue = DispatchQueue(label: "mic-capture")
  let session = AVCaptureSession()
  let url: URL
  let deviceName: String
  let seconds: Double?
  let interactive: Bool

  var file: AVAudioFile?
  var rate = 0.0
  var frames: AVAudioFramePosition = 0
  var frameLimit: AVAudioFramePosition?
  var expectedTime: Double?
  var gaps = 0
  var lostSeconds = 0.0
  var peak: Float = 0
  var clippedBuffers = 0
  var finished = false
  var sources: [DispatchSourceProtocol] = []

  init(device: AVCaptureDevice, url: URL, seconds: Double?, interactive: Bool) {
    self.url = url
    self.deviceName = device.localizedName
    self.seconds = seconds
    self.interactive = interactive
    super.init()

    let input: AVCaptureDeviceInput
    do { input = try AVCaptureDeviceInput(device: device) } catch { fail("cannot open \(deviceName): \(error.localizedDescription)") }
    guard session.canAddInput(input) else { fail("cannot record from \(deviceName)") }
    session.addInput(input)

    // 32-bit float at the device's own sample rate and channel count: no resampling, no downmix.
    let output = AVCaptureAudioDataOutput()
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    output.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddOutput(output) else { fail("cannot read audio from \(deviceName)") }
    session.addOutput(output)
  }

  func start() {
    // Signals are ignored as signals and delivered as events, so the WAV is always closed properly.
    for number in [SIGINT, SIGTERM, SIGHUP] {
      signal(number, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
      source.setEventHandler { [unowned self] in self.finish() }
      source.resume()
      sources.append(source)
    }
    if interactive {
      watchKeyboard()
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
      timer.setEventHandler { [unowned self] in self.showStatus() }
      timer.resume()
      sources.append(timer)
    }
    queue.asyncAfter(deadline: .now() + 5) { [unowned self] in
      if self.frames == 0 { fail("no audio from \(self.deviceName) after 5 seconds") }
    }
    session.startRunning()
  }

  // q stops the recording: read single keys, without echo, while this process owns the terminal.
  func watchKeyboard() {
    var settings = termios()
    guard tcgetattr(STDIN_FILENO, &settings) == 0 else { return }
    savedTerminal = settings
    settings.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &settings)
    Thread.detachNewThread { [unowned self] in
      var key: UInt8 = 0
      while read(STDIN_FILENO, &key, 1) == 1 {
        if key == UInt8(ascii: "q") || key == UInt8(ascii: "Q") {
          self.queue.async { self.finish() }
          return
        }
      }
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    if finished { return }
    let count = CMSampleBufferGetNumSamples(sampleBuffer)
    guard count > 0, let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

    if file == nil {
      let format = AVAudioFormat(cmAudioFormatDescription: description)
      guard format.commonFormat == .pcmFormatFloat32 else { fail("unexpected sample format from \(deviceName)") }
      let wav: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount,
        AVLinearPCMBitDepthKey: 24,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
      ]
      do {
        file = try AVAudioFile(forWriting: url, settings: wav, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
      } catch {
        fail("cannot write \(url.path): \(error.localizedDescription)")
      }
      rate = format.sampleRate
      if let seconds = seconds { frameLimit = AVAudioFramePosition((seconds * rate).rounded()) }
      let channels = format.channelCount == 1 ? "mono" : "\(format.channelCount) channels"
      say("input: \(deviceName), \(Int(rate)) Hz, \(channels), written as 24-bit WAV\n")
    }
    guard let file = file, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) else { return }
    buffer.frameLength = AVAudioFrameCount(count)
    guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList) == noErr else {
      fail("cannot read the audio delivered by \(deviceName)")
    }

    // A buffer that starts later than the end of the previous one means audio was lost in between.
    let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    let duration = Double(count) / rate
    if let expected = expectedTime, time - expected > max(0.002, duration / 2) {
      gaps += 1
      lostSeconds += time - expected
    }
    expectedTime = time + duration

    if let limit = frameLimit, frames + AVAudioFramePosition(count) > limit {
      buffer.frameLength = AVAudioFrameCount(limit - frames)
    }
    for part in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
      guard let data = part.mData else { continue }
      var loudest: Float = 0
      vDSP_maxmgv(data.assumingMemoryBound(to: Float.self), 1, &loudest, vDSP_Length(Int(part.mDataByteSize) / MemoryLayout<Float>.size))
      peak = max(peak, loudest)
      if loudest >= 0.999 { clippedBuffers += 1 }
    }
    do { try file.write(from: buffer) } catch { fail("cannot write \(url.path): \(error.localizedDescription)") }
    frames += AVAudioFramePosition(buffer.frameLength)
    if let limit = frameLimit, frames >= limit { finish() }
  }

  // Elapsed time and the peak level of the last moment, on one line that is redrawn in place.
  func showStatus() {
    guard rate > 0, !finished else { return }
    let elapsed = Int(Double(frames) / rate)
    let level = peak > 0 ? 20 * log10(Double(peak)) : -120
    let filled = max(0, min(20, Int((level + 60) / 3)))
    let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: 20 - filled)
    let clock = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    let value = String(format: "%6.1f dB", level)
    say("\r  \(clock)  [\(bar)] peak \(value)\(peak >= 0.999 ? "  CLIPPING" : "          ")")
    peak = 0
  }

  func finish() {
    if finished { return }
    finished = true
    file = nil  // closes the WAV and writes its final header
    restoreTerminal()
    if interactive { say("\r\u{1B}[K") }
    if frames == 0 { fail("no audio received from \(deviceName)") }
    if gaps > 0 {
      say(String(format: "warning: %.2f s of audio lost in %d gaps: the Mac was too busy to keep up\n", lostSeconds, gaps))
    }
    if clippedBuffers > 0 {
      say("warning: the input clipped \(clippedBuffers) times: lower the input volume in System Settings, Sound, Input\n")
    }
    exit(0)
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let usage = "usage: mic-capture devices | mic-capture record <index> <out.wav> [seconds]"

switch arguments.first {
case "devices":
  for (index, device) in inputDevices().enumerated() {
    print("[\(index)] \(device.localizedName)")
  }
case "record":
  guard arguments.count == 3 || arguments.count == 4, let index = Int(arguments[1]) else { fail(usage) }
  var seconds: Double?
  if arguments.count == 4 {
    guard let value = Double(arguments[3]), value > 0 else { fail("the duration must be a number of seconds, got '\(arguments[3])'") }
    seconds = value
  }
  let devices = inputDevices()
  guard devices.indices.contains(index) else { fail("no audio input with index \(index): see `just devices`") }
  requireMicrophoneAccess()
  // Keys and the status line only when a person is at the terminal, not when started in the background.
  let interactive = isatty(STDIN_FILENO) != 0 && isatty(STDERR_FILENO) != 0 && tcgetpgrp(STDIN_FILENO) == getpgrp()
  let recorder = Recorder(device: devices[index], url: URL(fileURLWithPath: arguments[2]), seconds: seconds, interactive: interactive)
  recorder.start()
  dispatchMain()
default:
  fail(usage)
}
