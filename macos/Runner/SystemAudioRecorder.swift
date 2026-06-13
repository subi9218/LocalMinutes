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

  var recording: Bool { isRecording }

  /// 시스템 오디오 캡처 시작. 성공 시 nil, 실패 시 에러 메시지 반환.
  func start(outputPath: String) -> String? {
    if isRecording { return "이미 녹음 중입니다." }

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
    var fileFormat = AudioStreamBasicDescription(
      mSampleRate: streamFormat.mSampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: UInt32(2 * Int(streamFormat.mChannelsPerFrame)),
      mFramesPerPacket: 1,
      mBytesPerFrame: UInt32(2 * Int(streamFormat.mChannelsPerFrame)),
      mChannelsPerFrame: streamFormat.mChannelsPerFrame,
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
      // AudioBufferList 를 안전하게 순회 (포인터를 클로저 밖으로 내보내지 않음)
      let bufferList = UnsafeMutableAudioBufferListPointer(
        UnsafeMutablePointer(mutating: inInputData)
      )
      guard let firstBuffer = bufferList.first, firstBuffer.mDataByteSize > 0
      else { return }
      let frames = firstBuffer.mDataByteSize / bytesPerFrame
      if frames == 0 { return }
      _ = ExtAudioFileWriteAsync(extFile, frames, inInputData)
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
