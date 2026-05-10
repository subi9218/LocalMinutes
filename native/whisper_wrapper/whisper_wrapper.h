#pragma once
#include <stdint.h>

// Dart FFI에 노출하는 whisper.cpp C API 래퍼
// llw_ (llama) 와 구분하기 위해 wsw_ (whisper_wrapper) 접두사 사용
// 타깃 whisper.cpp 버전: 최신 main 브랜치

#ifdef __cplusplus
extern "C" {
#endif

// ── 모델 로드/해제 ─────────────────────────────────────────────
// path: GGUF 또는 ggml 형식 모델 파일 경로
// 반환값: whisper_context 포인터 (NULL=실패)
void* wsw_load_model(const char* path);
void  wsw_free_model(void* ctx);

// ── 전사 실행 ──────────────────────────────────────────────────
// 동기 호출, 완료까지 블로킹 → Dart Isolate에서 호출 필수
// samples:  16kHz, 모노, float32 PCM [-1.0, 1.0]
// n_samples: 샘플 수
// language:  "ko" 고정 (한국어)
// n_threads: CPU 스레드 수 (M3 권장 6~8)
// initial_prompt: 고유명사/용어 힌트 (NULL 허용). Whisper 모델 컨텍스트에 주입되어
//                 회의 용어·참석자 이름 인식률을 높인다. 예: "회의록 전사. 용어: 넷마블, Gemma, Isar."
// decode_mode: 0=빠름(greedy), 1=표준(beam2), 2=정밀(beam5)
// 반환값: 0=성공, 비0=실패
int wsw_transcribe(void* ctx, const float* samples, int n_samples,
                   const char* language, int n_threads,
                   const char* initial_prompt, int decode_mode);

// ── 진행률 콜백 등록 ────────────────────────────────────────────
// wsw_transcribe 실행 중 새 세그먼트가 디코딩될 때마다
//   on_segment(n_new, t1_ms) 가 호출된다.
//     n_new : 이번 디코드 패스에서 새로 확정된 세그먼트 수
//     t1_ms : 현재까지 처리된 오디오 타임(마지막 세그먼트 종료 ms)
// Dart 측에서는 NativeCallable.listener 등을 사용해 Isolate 간 안전하게 수신해야 한다.
// ctx 1개당 하나의 콜백만 등록 가능 (재등록 시 덮어쓰기). NULL=해제.
// 스레드: whisper.cpp 워커 스레드에서 호출됨 (블로킹 금지, 가볍게 처리할 것)
typedef void (*wsw_segment_cb)(int n_new, int64_t t1_ms);
void wsw_set_segment_callback(void* ctx, wsw_segment_cb cb);

// ── 결과 조회 (wsw_transcribe 성공 후 유효) ─────────────────────
// 다음 wsw_transcribe 호출 전까지 유효한 내부 메모리 포인터 반환
int         wsw_n_segments(void* ctx);
const char* wsw_segment_text(void* ctx, int i);
int64_t     wsw_segment_t0_ms(void* ctx, int i); // 시작 시각 (밀리초)
int64_t     wsw_segment_t1_ms(void* ctx, int i); // 종료 시각 (밀리초)

#ifdef __cplusplus
}
#endif
