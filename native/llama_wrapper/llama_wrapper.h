#pragma once
#include <stdbool.h>
#include <stdint.h>

// Dart FFI에 노출하는 C API
// 내부적으로 llama.cpp struct-by-value 반환 함수를 래핑해 Dart ABI 문제 방지
// 타깃 llama.cpp 버전: b3000+ (2024 후반)

#ifdef __cplusplus
extern "C" {
#endif

// ── 백엔드 초기화/정리 ────────────────────────────────────────
void llw_backend_init(void);
void llw_backend_free(void);

// ── 모델 로드/해제 ────────────────────────────────────────────
// n_gpu_layers=99 → 모든 레이어를 Metal GPU로 오프로드
// 반환값: 모델 포인터 (NULL=실패)
void* llw_load_model(const char* path, int n_gpu_layers);
void  llw_free_model(void* model);

// ── 컨텍스트 (KV 캐시) ────────────────────────────────────────
// flash_attn=true 내부 설정 (M3 Metal 최적화)
// 반환값: 컨텍스트 포인터 (NULL=실패, 메모리 부족 가능성)
void* llw_create_context(void* model, int n_ctx, int n_batch);
void  llw_free_context(void* ctx);
void  llw_kv_cache_clear(void* ctx);

// ── 토크나이저 ────────────────────────────────────────────────
// llw_tokenize: 반환값=토큰 수, 음수=오류(토큰 수 초과 등)
// add_bos=true → BOS 토큰 자동 추가 (Gemma 4 필수)
// parse_special=true 내부 고정 → <start_of_turn> 등 특수 토큰 파싱
int     llw_tokenize(void* model, const char* text,
                     int32_t* out_tokens, int max_tokens, bool add_bos);

// llw_token_to_piece: 반환값=바이트 수, 음수=오류
// null 종단 문자 포함하여 out_buf에 저장
int     llw_token_to_piece(void* model, int32_t token,
                            char* out_buf, int buf_len);

int32_t llw_token_eos(void* model);
int32_t llw_token_bos(void* model);

// ── 디코드 ────────────────────────────────────────────────────
// llw_decode_prompt: 프롬프트 전체를 512 배치 단위로 분할 디코드
//   마지막 토큰만 logits 계산 (메모리 절약)
//   반환값: 0=성공, 비0=실패
int llw_decode_prompt(void* ctx, int32_t* tokens, int n_tokens);

// llw_decode_token: 생성 루프에서 단일 토큰 디코드
//   pos: KV 캐시에서 이 토큰이 위치할 절대 위치
//   반환값: 0=성공
int llw_decode_token(void* ctx, int32_t token, int32_t pos);

// ── 샘플러 ────────────────────────────────────────────────────
// temperature<=0.0 → greedy 샘플링
// 반환값: 샘플러 포인터
void*   llw_create_sampler(float temperature, float top_p, uint32_t seed);
int32_t llw_sample(void* sampler, void* ctx);
void    llw_sampler_accept(void* sampler, int32_t token);
void    llw_free_sampler(void* sampler);

#ifdef __cplusplus
}
#endif
