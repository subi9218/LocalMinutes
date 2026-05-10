# 온디바이스 AI 회의록 — 설치 가이드

> 팀 내부 배포용 문서입니다.

---

## 시스템 요구사항

| 항목 | 최소 사양 |
|------|----------|
| macOS | Ventura 13.0 이상 |
| 메모리 (RAM) | 16 GB (권장 32 GB) |
| 저장 공간 | 15 GB 이상 여유 공간 |
| 칩 | Apple Silicon (M1 이상) 권장 |

---

## 1단계: 앱 설치

1. `온디바이스_AI_회의록_v1.0.0.dmg` 파일을 더블클릭합니다.
2. 열린 창에서 `meeting_assistant2.app`을 `Applications` 폴더로 드래그합니다.
3. DMG 창을 닫고 마운트를 해제합니다.

### ⚠️ Gatekeeper 우회 (미서명 앱)

Apple 보안 정책으로 인해 첫 실행 시 "손상되었거나 열 수 없습니다" 오류가 발생할 수 있습니다.  
터미널에서 아래 명령을 실행한 뒤 앱을 열어주세요.

```bash
xattr -cr /Applications/meeting_assistant2.app
```

---

## 2단계: AI 모델 파일 설치

앱 크기를 최소화하기 위해 AI 모델 파일은 앱과 별도로 배포됩니다.  
아래 경로에 두 파일을 복사해야 앱이 정상 동작합니다.

### 설치 경로

```
~/Library/Application Support/meeting_assistant2/models/
```

터미널에서 폴더를 미리 만들어두면 편리합니다:

```bash
mkdir -p ~/Library/Application\ Support/meeting_assistant2/models
```

### 필요한 파일

| 파일명 | 용도 | 크기 |
|--------|------|------|
| `whisper-large-v3-turbo-q8_0.gguf` | STT (음성 인식) | ~2 GB |
| `gemma-4-e2b-it-q8_0.gguf` | LLM (요약 생성) | ~8 GB |

### 파일 다운로드

팀 내부 파일 서버에서 다운로드하거나, 담당자에게 전달 요청하세요.  
(외부 인터넷 다운로드 링크: 내부 Wiki 참조)

### 복사 예시

```bash
# USB 드라이브 또는 내부 서버에서 복사하는 경우
cp /Volumes/TeamDrive/models/whisper-large-v3-turbo-q8_0.gguf \
   ~/Library/Application\ Support/meeting_assistant2/models/

cp /Volumes/TeamDrive/models/gemma-4-e2b-it-q8_0.gguf \
   ~/Library/Application\ Support/meeting_assistant2/models/
```

---

## 3단계: 앱 실행

1. `/Applications/meeting_assistant2.app` 실행
2. 초기 설정 화면에서 두 모델이 **"설치됨"** 으로 표시되는지 확인
3. **"확인 완료 → 앱 시작"** 버튼 클릭

---

## 사용 방법

| 작업 | 방법 |
|------|------|
| 새 녹음 시작 | 사이드바 상단 **"새 녹음"** 버튼 또는 좌측 홈 화면 버튼 |
| 녹음 중지 | 녹음 화면의 **"녹음 중지"** 버튼 |
| AI 요약 생성 | 중지 후 **"Gemma 4 요약"** 버튼 (6–8 GB LLM 로드, 약 1–2분 소요) |
| 회의 목록 보기 | 좌측 사이드바에서 클릭 |
| 내보내기 | 회의 상세 화면 우측 상단 **↑ 버튼** → 텍스트/PDF/이메일/공유 |

---

## 메모리 사용량

| 단계 | 메모리 |
|------|--------|
| 대기 중 | ~200 MB |
| 녹음 중 (STT 로드) | ~2.5 GB |
| 요약 중 (LLM 로드) | ~9–10 GB |

> STT와 LLM은 동시에 메모리에 올라가지 않습니다.  
> M2 Pro 이상 (32 GB) 환경에서 가장 쾌적하게 동작합니다.

---

## 문제 해결

### 앱이 실행되지 않음
```bash
xattr -cr /Applications/meeting_assistant2.app
```

### "모델을 찾을 수 없습니다" 오류
- 설치 경로의 파일명이 정확한지 확인 (`gguf` 확장자 포함)
- 경로에 띄어쓰기나 한글이 없는지 확인

### 요약이 너무 느림
- 배터리 절약 모드 해제 후 실행
- 다른 메모리 집약적 앱을 종료하세요

### 전사가 되지 않음
- 시스템 환경설정 → 개인 정보 보호 → 마이크 → meeting_assistant2 허용 확인

---

## 문의

Netmarble 사내 Slack `#온디바이스-회의록` 채널 또는 담당자에게 문의하세요.
