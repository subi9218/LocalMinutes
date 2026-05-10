# 모델 파일 배치 안내

이 디렉토리에 GGUF 모델 파일을 배치합니다.
앱 번들에 포함되지 않으므로 **빌드 전 수동 배치** 필요합니다.

---

## 필수 모델

### 1. LLM — Gemma 4 E2B (요약)
| 항목 | 내용 |
|------|------|
| 파일명 | `gemma-4-e2b-it-q8_0.gguf` |
| 크기 | ~3 GB |
| 출처 | Hugging Face: `google/gemma-4-e2b-it-GGUF` |
| 컨텍스트 | 128K 토큰 |
| 가속 | Metal (M3) |

### 2. STT — Whisper Large V3 Turbo (음성 인식)
| 항목 | 내용 |
|------|------|
| 파일명 | `whisper-large-v3-turbo-q8_0.gguf` |
| 크기 | ~1.6 GB |
| 출처 | Hugging Face: `ggerganov/whisper.cpp` 릴리즈 |
| 언어 | 한국어 고정 (`language=ko`) |

---

## 배치 방법

```bash
# Hugging Face CLI 사용 예시
pip install huggingface_hub

# Gemma 4 E2B
huggingface-cli download google/gemma-4-e2b-it-GGUF \
  gemma-4-e2b-it-q8_0.gguf \
  --local-dir assets/models/

# Whisper Large V3 Turbo
huggingface-cli download ggerganov/whisper.cpp \
  ggml-large-v3-turbo-q8_0.bin \
  --local-dir assets/models/
# → 파일명을 whisper-large-v3-turbo-q8_0.gguf 로 변경
```

---

## 주의 사항

- **이 디렉토리의 모델 파일은 `.gitignore`에 추가하세요** (용량 이슈)
- 앱 실행 시 `OnDeviceModelManager`가 이 경로에서 mmap 로드
- 두 모델을 동시에 메모리에 올리지 않음 (STT 종료 후 LLM 로드)
- M3 16GB RAM 기준 피크: Whisper ~2 GB / Gemma 4 ~6–8 GB

---

## 현재 배치 상태

- [ ] `gemma-4-e2b-it-q8_0.gguf`
- [ ] `whisper-large-v3-turbo-q8_0.gguf`
