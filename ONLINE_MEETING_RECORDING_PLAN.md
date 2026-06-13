# 온라인 회의 녹음 (시스템 오디오 캡처) — 설계/구현 계획

목표 버전: **2.2.0** (버그 수정 2.1.4와 분리, `feature/system-audio-capture` 브랜치)

## 문제
현재 앱은 마이크 입력만 녹음한다. Zoom/Meet/Teams 등 온라인 회의에서 상대방
목소리는 스피커로 나오므로(이어폰 사용 시 마이크에 안 들어옴) 녹음되지 않는다.
→ **시스템 출력 오디오를 직접 캡처**해야 한다.

## 접근 (App Store 호환, 드라이버 설치 불필요)
**Core Audio 프로세스 탭** (`AudioHardwareCreateProcessTap`, macOS 14.2+)을 사용한다.
앱 최소 타깃이 macOS 15.5라 사용 가능. 시스템 출력 전체를 stereo로 탭 → 사설(private)
aggregate device에 연결 → IOProc에서 PCM을 받아 WAV로 기록.

대안: ScreenCaptureKit(`SCStream.capturesAudio`, 13+)도 가능하나 화면 녹화 권한이
필요해 오디오 전용에는 과하다. → 프로세스 탭 채택.

## 녹음 소스 모드 (UI에서 선택)
1. **마이크만** — 기존 동작 (대면 회의)
2. **시스템 오디오만** — 상대방 목소리만 (내 마이크 끄고 듣기만 할 때)
3. **마이크 + 시스템 오디오 (믹스)** — 온라인 회의 권장. 내 목소리 + 상대 목소리

믹스 전략: 시스템 오디오(탭)와 마이크를 각각 캡처해 합산(또는 2채널로 분리 저장).
2채널 분리 저장 시 화자 분리(나 vs 상대) 품질이 올라간다 — 1차는 모노 믹스로 단순화.

## 구성 요소
- **네이티브**: `macos/Runner/SystemAudioRecorder.swift`
  - 메서드 채널 `app/system_audio`: `isSupported`, `start{path}`, `stop`, `permissionStatus`
  - Core Audio 프로세스 탭 → 사설 aggregate device → IOProc → `ExtAudioFile`(WAV int16)
- **Dart**: `lib/data/datasources/system_audio_service.dart` — 채널 래퍼
- **파이프라인**: 기존 WAV → Whisper 경로 그대로 재사용 (출력 WAV만 시스템 오디오로 교체/믹스)
- **UI**: 녹음 준비 화면에 소스 선택 추가 (`recording_view`), 권한 안내

## 권한 / 엔타이틀먼트 (검증 필요 항목)
- 샌드박스 유지(`com.apple.security.app-sandbox = true`).
- 시스템 오디오 탭은 macOS에서 **오디오 캡처 권한(TCC)** 프롬프트를 띄울 수 있음
  (마이크 권한과 별개). 첫 `start` 시 OS가 사용자에게 허용을 요청.
- `Info.plist`에 사용 목적 문자열 추가 필요 가능성 (예: `NSAudioCaptureUsageDescription` —
  실제 키/엔타이틀먼트는 테스트 빌드에서 확인).
- App Store: 회의 녹음/전사는 허용 카테고리. 사용자 주도 + 명확한 고지 + 녹음 표시 필요.

## 법적 고지
통화 녹음은 지역에 따라 상대방 동의가 필요. 시스템 오디오 녹음 시작 시 1회 안내 문구 권장.

## 마일스톤
1. **스파이크(현재)**: 네이티브 탭 → WAV 기록 모듈 + 채널 + Dart 서비스, **컴파일 검증**.
   (실제 Zoom 통화로 캡처되는지는 기기 실측 필요 — 사용자 테스트)
2. 권한 흐름(요청/거부/설정 이동) + Info.plist/엔타이틀먼트 확정.
3. 마이크 + 시스템 오디오 믹스 (또는 2채널).
4. 녹음 준비 UI에 소스 선택 + 녹음 표시 + 법적 고지.
5. 전사/요약 파이프라인 연결, 화자 분리(나/상대) 개선.
6. QA(권한 거부, 기기 변경, 장시간 녹음, 디스크 부족) → 2.2.0 제출.

## 리스크
- 프로세스 탭 API는 런타임 동작을 기기에서 실측해야 함(헤드리스 검증 불가).
- 권한 프롬프트/엔타이틀먼트가 macOS 버전에 따라 다를 수 있음.
- 장시간(수 시간) 캡처 시 디스크/메모리 — 기존 파이프라인의 청크 처리 재사용.
