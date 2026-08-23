import AVFoundation
import CoreAudio
import Foundation

/// 시스템 출력 오디오(온라인 회의 상대방 목소리 포함)를 Core Audio 프로세스 탭으로
/// 캡처해 WAV(16-bit PCM) 파일로 기록한다. macOS 14.2+ 공식 API 사용 — 가상 드라이버 불필요.
///
/// 흐름: CATapDescription(전역 stereo 탭) → AudioHardwareCreateProcessTap →
///       사설 aggregate device(탭 + 기본 출력 클럭) → IOProc → ExtAudioFile(WAV).
///
/// 주의: 런타임 캡처 동작은 기기에서 실측 필요. 이 모듈은 시작/중지/지원여부만 제공하며
/// Flutter `app/system_audio` 채널로 호출된다.
@available(macOS 14.2, *)
final class SystemAudioRecorder {
  private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
  private var ioProcID: AudioDeviceIOProcID?
  private var extFile: ExtAudioFileRef?
  private var streamFormat = AudioStreamBasicDescription()
  private var isRecording = false
  private let ioQueue = DispatchQueue(label: "com.subi9218.localminutes.systemaudio")

  // ── 실시간 전사용 16kHz 모노 int16 PCM 변환/버퍼 (B 마일스톤) ──────────
  // IOProc에서 탭 포맷 → 16kHz 모노 int16로 변환해 누적하고, Dart가 drainPcm으로
  // 주기적으로 가져가 마이크 윈도우와 실시간 믹스한다.
  private var converter: AVAudioConverter?
  private var inFormat: AVAudioFormat?
  private let outFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 16000,
    channels: 1,
    interleaved: true
  )
  private var pcmLock = os_unfair_lock()
  private var pcmBuffer = Data()
  private let maxPcmBytes = 16000 * 2 * 60 // 60초 분량 상한

  // 일시정지: IOProc에서 파일 쓰기·PCM 변환을 스킵한다.
  // 마이크(pause 시 바이트 무시)와 동일 동작 — 두 트랙의 믹스 싱크 유지.
  // IOProc 실시간 스레드에서 읽으므로 lock으로 보호.
  private var pausedLock = os_unfair_lock()
  private var _paused = false
  private var isPausedNow: Bool {
    os_unfair_lock_lock(&pausedLock)
    defer { os_unfair_lock_unlock(&pausedLock) }
    return _paused
  }

  func setPaused(_ value: Bool) {
    os_unfair_lock_lock(&pausedLock)
    _paused = value
    os_unfair_lock_unlock(&pausedLock)
  }

  var recording: Bool { isRecording }

  /// 누적된 16kHz 모노 int16 PCM을 반환하고 버퍼를 비운다.
  func drainPcm() -> Data {
    os_unfair_lock_lock(&pcmLock)
    let out = pcmBuffer
    pcmBuffer = Data()
    os_unfair_lock_unlock(&pcmLock)
    return out
  }

  /// 시스템 오디오 캡처 시작. 성공 시 nil, 실패 시 에러 메시지 반환.
  func start(outputPath: String) -> String? {
    if isRecording { return "이미 녹음 중입니다." }
    setPaused(false) // 이전 세션의 일시정지 상태가 남지 않도록 리셋

    // ── 1) 전역(시스템 전체) stereo 탭 생성 — 제외 프로세스 없음 ──────────
    let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    tapDescription.isPrivate = true
    tapDescription.muteBehavior = .unmuted

    var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
    guard status == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
      return "오디오 탭 생성 실패 (status \(status))"
    }

    // ── 2) 탭의 스트림 포맷 조회 ────────────────────────────────────────
    var formatAddr = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyFormat,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    status = AudioObjectGetPropertyData(
      tapID, &formatAddr, 0, nil, &formatSize, &streamFormat
    )
    guard status == noErr, streamFormat.mSampleRate > 0 else {
      cleanup()
      return "탭 포맷 조회 실패 (status \(status))"
    }

    // ── 2-1) 실시간 전사용 변환기 준비 (탭 포맷 → 16kHz 모노 int16) ────────
    if let inFmt = AVAudioFormat(streamDescription: &streamFormat),
       let outFmt = outFormat {
      inFormat = inFmt
      converter = AVAudioConverter(from: inFmt, to: outFmt)
    }
    os_unfair_lock_lock(&pcmLock)
    pcmBuffer = Data()
    os_unfair_lock_unlock(&pcmLock)

    // ── 3) 사설 aggregate device 생성 (탭 + 기본 출력 장치를 클럭으로) ─────
    let aggregateUID = UUID().uuidString
    let tapUID = tapDescription.uuid.uuidString
    var description: [String: Any] = [
      kAudioAggregateDeviceNameKey as String: "LocalMinutes System Tap",
      kAudioAggregateDeviceUIDKey as String: aggregateUID,
      kAudioAggregateDeviceIsPrivateKey as String: true,
      kAudioAggregateDeviceIsStackedKey as String: false,
      kAudioAggregateDeviceTapAutoStartKey as String: true,
      kAudioAggregateDeviceTapListKey as String: [
        [
          kAudioSubTapUIDKey as String: tapUID,
          kAudioSubTapDriftCompensationKey as String: true,
        ]
      ],
    ]
    if let outputUID = Self.defaultOutputDeviceUID() {
      description[kAudioAggregateDeviceSubDeviceListKey as String] = [
        [kAudioSubDeviceUIDKey as String: outputUID]
      ]
      description[kAudioAggregateDeviceMainSubDeviceKey as String] = outputUID
    }

    status = AudioHardwareCreateAggregateDevice(
      description as CFDictionary, &aggregateID
    )
    guard status == noErr, aggregateID != AudioObjectID(kAudioObjectUnknown) else {
      cleanup()
      return "aggregate device 생성 실패 (status \(status))"
    }

    // ── 4) 출력 WAV(int16) 파일 준비 — 클라이언트 포맷=탭 포맷(float) ──────
    // 파일은 처음부터 16kHz 모노 int16으로 기록한다 (STT 입력 규격과 동일).
    // ExtAudioFile이 클라이언트(탭 48kHz 스테레오 float) → 파일 포맷 변환을
    // 고품질 SRC로 내장 수행하므로:
    //  - 파일 크기가 1/6 (2시간 ≈ 1.4GB → 230MB)
    //  - 정지 후 믹스 시 Dart 선형보간 리샘플(앨리어싱 유발)을 아예 타지 않음
    //  - 믹스 메모리 피크가 수 GB → 수백 MB로 감소 (긴 회의 OOM 방지)
    var fileFormat = AudioStreamBasicDescription(
      mSampleRate: 16000,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: 2,
      mFramesPerPacket: 1,
      mBytesPerFrame: 2,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 16,
      mReserved: 0
    )
    let url = URL(fileURLWithPath: outputPath)
    status = ExtAudioFileCreateWithURL(
      url as CFURL,
      kAudioFileWAVEType,
      &fileFormat,
      nil,
      AudioFileFlags.eraseFile.rawValue,
      &extFile
    )
    guard status == noErr, let extFile else {
      cleanup()
      return "WAV 파일 생성 실패 (status \(status))"
    }
    // 클라이언트(입력) 포맷을 탭의 포맷으로 지정하면 ExtAudioFile이 int16으로 변환.
    status = ExtAudioFileSetProperty(
      extFile,
      kExtAudioFileProperty_ClientDataFormat,
      UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
      &streamFormat
    )
    guard status == noErr else {
      cleanup()
      return "클라이언트 포맷 설정 실패 (status \(status))"
    }
    // 비동기 쓰기 워밍업 (IOProc 내 ExtAudioFileWriteAsync 사용 위함)
    _ = ExtAudioFileWriteAsync(extFile, 0, nil)

    // ── 5) IOProc 설치 — 입력(탭) 버퍼를 파일로 비동기 기록 ───────────────
    let bytesPerFrame = streamFormat.mBytesPerFrame
    status = AudioDeviceCreateIOProcIDWithBlock(
      &ioProcID, aggregateID, ioQueue
    ) {
      [weak self] (_, inInputData, _, _, _) in
      guard let self, let extFile = self.extFile, bytesPerFrame > 0 else { return }
      if self.isPausedNow { return } // 일시정지 중 — 기록/변환 모두 스킵
      // AudioBufferList 를 안전하게 순회 (포인터를 클로저 밖으로 내보내지 않음)
      let bufferList = UnsafeMutableAudioBufferListPointer(
        UnsafeMutablePointer(mutating: inInputData)
      )
      guard let firstBuffer = bufferList.first, firstBuffer.mDataByteSize > 0
      else { return }
      let frames = firstBuffer.mDataByteSize / bytesPerFrame
      if frames == 0 { return }
      _ = ExtAudioFileWriteAsync(extFile, frames, inInputData)

      // 실시간 전사용: 탭 PCM → 16kHz 모노 int16로 변환해 누적
      self.appendConvertedPcm(inInputData)
    }
    guard status == noErr, ioProcID != nil else {
      cleanup()
      return "IOProc 생성 실패 (status \(status))"
    }

    status = AudioDeviceStart(aggregateID, ioProcID)
    guard status == noErr else {
      cleanup()
      return "오디오 캡처 시작 실패 (status \(status))"
    }

    isRecording = true
    return nil
  }

  /// 탭 입력 버퍼를 16kHz 모노 int16로 변환해 pcmBuffer에 누적한다.
  /// IOProc(실시간 스레드)에서 호출되므로 가볍게 유지한다.
  private func appendConvertedPcm(_ inInputData: UnsafePointer<AudioBufferList>) {
    guard let converter, let inFormat, let outFormat else { return }
    guard
      let inBuffer = AVAudioPCMBuffer(
        pcmFormat: inFormat,
        bufferListNoCopy: inInputData,
        deallocator: nil
      ),
      inBuffer.frameLength > 0
    else { return }

    let ratio = outFormat.sampleRate / inFormat.sampleRate
    let outCap = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 16
    guard
      let outBuffer = AVAudioPCMBuffer(
        pcmFormat: outFormat, frameCapacity: outCap
      )
    else { return }

    var fed = false
    var convErr: NSError?
    converter.convert(to: outBuffer, error: &convErr) { _, outStatus in
      if fed {
        outStatus.pointee = .noDataNow
        return nil
      }
      fed = true
      outStatus.pointee = .haveData
      return inBuffer
    }
    if convErr != nil { return }
    let n = Int(outBuffer.frameLength)
    if n == 0 { return }
    guard let ch = outBuffer.int16ChannelData else { return }
    let byteCount = n * 2
    let data = Data(bytes: ch[0], count: byteCount)

    os_unfair_lock_lock(&pcmLock)
    pcmBuffer.append(data)
    if pcmBuffer.count > maxPcmBytes {
      pcmBuffer.removeFirst(pcmBuffer.count - maxPcmBytes)
    }
    os_unfair_lock_unlock(&pcmLock)
  }

  /// 캡처 중지 및 자원 정리.
  func stop() {
    cleanup()
  }

  private func cleanup() {
    if let ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
      AudioDeviceStop(aggregateID, ioProcID)
      AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
    }
    ioProcID = nil
    if aggregateID != AudioObjectID(kAudioObjectUnknown) {
      AudioHardwareDestroyAggregateDevice(aggregateID)
      aggregateID = AudioObjectID(kAudioObjectUnknown)
    }
    if tapID != AudioObjectID(kAudioObjectUnknown) {
      AudioHardwareDestroyProcessTap(tapID)
      tapID = AudioObjectID(kAudioObjectUnknown)
    }
    if let extFile {
      ExtAudioFileDispose(extFile)
    }
    extFile = nil
    converter = nil
    inFormat = nil
    os_unfair_lock_lock(&pcmLock)
    pcmBuffer = Data()
    os_unfair_lock_unlock(&pcmLock)
    isRecording = false
  }

  /// 기본 출력 장치의 UID 문자열.
  private static func defaultOutputDeviceUID() -> String? {
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
    )
    guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
      return nil
    }
    var uid: CFString? = nil
    var uidSize = UInt32(MemoryLayout<CFString?>.size)
    var uidAddr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    status = withUnsafeMutablePointer(to: &uid) { ptr in
      AudioObjectGetPropertyData(deviceID, &uidAddr, 0, nil, &uidSize, ptr)
    }
    guard status == noErr, let resolved = uid else { return nil }
    return resolved as String
  }
}

/// 임의의 오디오/비디오 파일(m4a, mp3, aac, mp4, mov, caf, aiff, wav 등)을
/// 16kHz 모노 16-bit PCM WAV 로 변환한다. 온디바이스 STT 입력 규격에 맞춘다.
///
/// AVAssetReader 가 컨테이너/코덱 디코딩 + 리샘플 + 다운믹스를 모두 처리하므로
/// FFmpeg 같은 외부 의존성 없이 macOS 기본 프레임워크만으로 광범위한 포맷을 지원한다.
final class AudioFileConverter {
  /// 변환 실행. 성공 시 nil, 실패 시 사용자에게 보여줄 에러 메시지를 반환한다.
  static func convertToWav16kMono(inputPath: String, outputPath: String) -> String? {
    let fm = FileManager.default
    if !fm.fileExists(atPath: inputPath) {
      return "입력 파일을 찾을 수 없습니다."
    }
    let inURL = URL(fileURLWithPath: inputPath)
    let asset = AVURLAsset(url: inURL)
    // 백그라운드 큐에서 호출되므로 세마포어로 비동기 로드를 동기 대기한다(메인 블록 없음).
    var loadedTracks: [AVAssetTrack] = []
    let sem = DispatchSemaphore(value: 0)
    asset.loadTracks(withMediaType: .audio) { tracks, _ in
      loadedTracks = tracks ?? []
      sem.signal()
    }
    sem.wait()
    guard let track = loadedTracks.first else {
      return "오디오 트랙을 찾을 수 없습니다. (지원하지 않는 파일이거나 영상에 소리가 없습니다)"
    }

    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      return "파일을 여는 데 실패했습니다: \(error.localizedDescription)"
    }

    // 출력 규격을 16kHz 모노 16-bit LPCM 으로 지정 → 리더가 디코딩/리샘플/다운믹스.
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16000.0,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      return "오디오 디코딩 설정에 실패했습니다."
    }
    reader.add(output)

    guard reader.startReading() else {
      return "오디오 읽기를 시작하지 못했습니다: \(reader.error?.localizedDescription ?? "알 수 없는 오류")"
    }

    var pcm = Data()
    while reader.status == .reading {
      guard let sample = output.copyNextSampleBuffer() else { break }
      if let block = CMSampleBufferGetDataBuffer(sample) {
        let len = CMBlockBufferGetDataLength(block)
        if len > 0 {
          var tmp = [UInt8](repeating: 0, count: len)
          let copied = CMBlockBufferCopyDataBytes(
            block, atOffset: 0, dataLength: len, destination: &tmp
          )
          if copied == kCMBlockBufferNoErr {
            pcm.append(contentsOf: tmp)
          }
        }
      }
      CMSampleBufferInvalidate(sample)
    }

    if reader.status == .failed {
      return "오디오 변환에 실패했습니다: \(reader.error?.localizedDescription ?? "알 수 없는 오류")"
    }
    if pcm.isEmpty {
      return "변환 결과가 비어 있습니다. (소리가 없는 파일일 수 있습니다)"
    }

    let wav = wavData(pcm: pcm, sampleRate: 16000, channels: 1, bitsPerSample: 16)
    do {
      try wav.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    } catch {
      return "변환된 파일 저장에 실패했습니다: \(error.localizedDescription)"
    }
    return nil
  }

  /// 16-bit PCM 바이트 앞에 44바이트 WAV 헤더를 붙여 반환.
  private static func wavData(
    pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int
  ) -> Data {
    var d = Data()
    let byteRate = sampleRate * channels * bitsPerSample / 8
    let blockAlign = channels * bitsPerSample / 8
    let dataLen = pcm.count
    func u32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return Data(bytes: &x, count: 4) }
    func u16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return Data(bytes: &x, count: 2) }
    d.append("RIFF".data(using: .ascii)!)
    d.append(u32(36 + dataLen))
    d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!)
    d.append(u32(16))                 // fmt chunk 크기 (PCM)
    d.append(u16(1))                  // 오디오 포맷 = PCM
    d.append(u16(channels))
    d.append(u32(sampleRate))
    d.append(u32(byteRate))
    d.append(u16(blockAlign))
    d.append(u16(bitsPerSample))
    d.append("data".data(using: .ascii)!)
    d.append(u32(dataLen))
    d.append(pcm)
    return d
  }
}
