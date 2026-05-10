// whisper.cpp C 래퍼 구현
//
// 타깃 whisper.cpp 버전: 최신 main 브랜치
// API 변경 시 참고:
//   whisper_init_from_file → 일부 버전: whisper_init_from_file_with_params
//   WHISPER_SAMPLING_GREEDY → enum whisper_sampling_strategy 의 0번 값

#include "whisper_wrapper.h"
#include "whisper.h"
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <atomic>

// 단일 콜백 포인터 (Dart측에서 ctx 1개만 사용하므로 단순화).
//   회의 앱은 동시에 1개 전사만 돌린다는 전제.
static std::atomic<wsw_segment_cb> g_segment_cb{nullptr};

// whisper.cpp new_segment_callback 어댑터 — Dart로 이벤트 전달.
static void wsw_new_segment_adapter(struct whisper_context* ctx,
                                    struct whisper_state* /*state*/,
                                    int n_new,
                                    void* /*user_data*/) {
    auto cb = g_segment_cb.load(std::memory_order_acquire);
    if (cb == nullptr) return;
    const int total = whisper_full_n_segments(ctx);
    if (total <= 0) return;
    // whisper.cpp 타임스탬프 단위: centiseconds → ms
    const int64_t t1_ms = whisper_full_get_segment_t1(ctx, total - 1) * 10;
    cb(n_new, t1_ms);
}

extern "C" {

// ── 모델 ────────────────────────────────────────────────────────

void* wsw_load_model(const char* path) {
    return (void*)whisper_init_from_file(path);
}

void wsw_free_model(void* ctx) {
    whisper_free((struct whisper_context*)ctx);
}

// ── 전사 ────────────────────────────────────────────────────────

int wsw_transcribe(void* ctx_ptr, const float* samples, int n_samples,
                   const char* language, int n_threads,
                   const char* initial_prompt, int decode_mode) {
    auto* ctx = (struct whisper_context*)ctx_ptr;

    const int mode = std::clamp(decode_mode, 0, 2);
    auto params = whisper_full_default_params(
        mode == 0 ? WHISPER_SAMPLING_GREEDY : WHISPER_SAMPLING_BEAM_SEARCH
    );
    if (mode > 0) {
        // 0=greedy(빠름), 1=beam2(표준), 2=beam5(정밀).
        // 기존 앱은 항상 beam5였고, 긴 회의에서 속도 체감이 좋지 않았다.
        params.beam_search.beam_size = mode == 1 ? 2 : 5;
    }

    params.language        = language;     // "ko" 한국어 고정
    params.n_threads       = n_threads;    // CPU 스레드 (M3 권장: 6~8)
    params.translate       = false;        // 한국어 → 영어 번역 비활성화
    // no_context=true: 긴 묵음에서 "네. 네. 네." 환각 캐스케이드 방지.
    //   이전 세그먼트 문맥 차단 → 각 청크 독립 디코딩.
    //   단점: 청크 경계에서 문장이 끊길 수 있지만, 환각보다 훨씬 낫다.
    params.no_context      = true;
    params.single_segment  = false;        // 다중 세그먼트 허용
    params.print_special   = false;
    params.print_progress  = false;
    params.print_realtime  = false;
    params.print_timestamps = true;        // t0/t1 조회용

    // 고유명사/용어 힌트 (단어집 기반) — NULL/빈 문자열이면 미주입
    if (initial_prompt != nullptr && initial_prompt[0] != '\0') {
        params.initial_prompt = initial_prompt;
    }

    // ── 환각(hallucination) 방지 파라미터 ─────────────────────────
    // 묵음/반복/저확률 구간에서 학습 데이터 문장("네." 반복 등)을
    //   지어내는 문제 완화. 안전한 기본값 조합 사용.
    params.no_speech_thold = 0.6f;         // 기본값 — 묵음 판정 충분히 강함
    params.logprob_thold   = -1.0f;        // 기본값 — fallback에 판단 위임
    params.entropy_thold   = 2.4f;         // compression_ratio 유사 — 반복 검출
    // temperature=0 시작, 실패 시 0.2씩 올려 재샘플링 (fallback escape hatch).
    //   temperature_inc=0으로 완전 고정하면 환각 루프에서 벗어날 수 없음.
    params.temperature     = 0.0f;
    params.temperature_inc = 0.2f;
    params.suppress_blank  = true;         // 빈 토큰 시작 억제
    params.suppress_nst    = true;         // 비음성 토큰 억제 (음악/기호 등)

    // ── 진행률 콜백 (Dart에서 등록되어 있으면 연결) ────────────────
    if (g_segment_cb.load(std::memory_order_acquire) != nullptr) {
        params.new_segment_callback = wsw_new_segment_adapter;
        params.new_segment_callback_user_data = nullptr;
    }

    return whisper_full(ctx, params, samples, n_samples);
}

void wsw_set_segment_callback(void* /*ctx_ptr*/, wsw_segment_cb cb) {
    // ctx 파라미터는 향후 다중 ctx 지원 대비 예약. 현재는 전역 단일 포인터만 저장.
    g_segment_cb.store(cb, std::memory_order_release);
}

// ── 결과 조회 ────────────────────────────────────────────────────

int wsw_n_segments(void* ctx) {
    return whisper_full_n_segments((struct whisper_context*)ctx);
}

const char* wsw_segment_text(void* ctx, int i) {
    return whisper_full_get_segment_text((struct whisper_context*)ctx, i);
}

int64_t wsw_segment_t0_ms(void* ctx, int i) {
    // whisper.cpp 타임스탬프 단위: centiseconds (1/100초) → ms 변환
    return whisper_full_get_segment_t0((struct whisper_context*)ctx, i) * 10;
}

int64_t wsw_segment_t1_ms(void* ctx, int i) {
    return whisper_full_get_segment_t1((struct whisper_context*)ctx, i) * 10;
}

} // extern "C"
