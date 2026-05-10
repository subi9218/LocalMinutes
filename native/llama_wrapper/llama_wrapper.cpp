// llama.cpp C 래퍼 구현
//
// 타깃 llama.cpp 버전: b4000+ (2025)
// 최신 API 사용:
//   llama_model_load_from_file  (이전: llama_load_model_from_file)
//   llama_init_from_model       (이전: llama_new_context_with_params)
//   llama_model_free            (이전: llama_free_model)
//   llama_model_get_vocab       → vocab 포인터 획득
//   llama_vocab_eos/bos         (이전: llama_token_eos/bos)
//   llama_memory_clear          (이전: llama_kv_cache_clear)

#include "llama_wrapper.h"
#include "llama.h"
#include <algorithm>
#include <cstring>
#include <cstdio>

extern "C" {

// ── 백엔드 ──────────────────────────────────────────────────────

void llw_backend_init() {
    llama_backend_init();
}

void llw_backend_free() {
    llama_backend_free();
}

// ── 모델 ────────────────────────────────────────────────────────

void* llw_load_model(const char* path, int n_gpu_layers) {
    llama_model_params p = llama_model_default_params();
    p.n_gpu_layers = n_gpu_layers; // 99 → 전체 Metal 오프로드
    return (void*)llama_model_load_from_file(path, p);
}

void llw_free_model(void* model) {
    llama_model_free((struct llama_model*)model);
}

// ── 컨텍스트 ─────────────────────────────────────────────────────

void* llw_create_context(void* model, int n_ctx, int n_batch) {
    llama_context_params p = llama_context_default_params();
    p.n_ctx      = (uint32_t)n_ctx;
    p.n_batch    = (uint32_t)n_batch;
    p.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO; // M3 Metal 성능 최적화
    return (void*)llama_init_from_model((struct llama_model*)model, p);
}

void llw_free_context(void* ctx) {
    llama_free((struct llama_context*)ctx);
}

void llw_kv_cache_clear(void* ctx) {
    // 최신 API: llama_memory_clear (context->memory, data=false)
    llama_memory_t mem = llama_get_memory((struct llama_context*)ctx);
    if (mem) {
        llama_memory_clear(mem, false);
    }
}

// ── 토크나이저 ────────────────────────────────────────────────────

int llw_tokenize(void* model, const char* text,
                 int32_t* out_tokens, int max_tokens, bool add_bos) {
    const struct llama_vocab* vocab =
        llama_model_get_vocab((const struct llama_model*)model);
    return llama_tokenize(
        vocab,
        text, (int32_t)strlen(text),
        out_tokens, max_tokens,
        add_bos, // add_special: BOS/EOS 자동 추가
        true      // parse_special: <start_of_turn> 등 특수 토큰 파싱
    );
}

int llw_token_to_piece(void* model, int32_t token, char* out_buf, int buf_len) {
    const struct llama_vocab* vocab =
        llama_model_get_vocab((const struct llama_model*)model);
    return llama_token_to_piece(
        vocab,
        token, out_buf, buf_len,
        0,     // lstrip: 앞쪽 공백 제거 안 함
        false  // special: 특수 토큰 텍스트 표현 사용 안 함
    );
}

int32_t llw_token_eos(void* model) {
    const struct llama_vocab* vocab =
        llama_model_get_vocab((const struct llama_model*)model);
    return llama_vocab_eos(vocab);
}

int32_t llw_token_bos(void* model) {
    const struct llama_vocab* vocab =
        llama_model_get_vocab((const struct llama_model*)model);
    return llama_vocab_bos(vocab);
}

// ── 디코드 ────────────────────────────────────────────────────────

int llw_decode_prompt(void* ctx_ptr, int32_t* tokens, int n_tokens) {
    auto* ctx = (struct llama_context*)ctx_ptr;
    const int BATCH = 512; // 배치 단위 분할 (메모리 절약)

    for (int i = 0; i < n_tokens; i += BATCH) {
        int this_n = std::min(BATCH, n_tokens - i);
        llama_batch batch = llama_batch_init(this_n, 0, 1);

        for (int j = 0; j < this_n; j++) {
            batch.token   [j] = tokens[i + j];
            batch.pos     [j] = i + j;
            batch.n_seq_id[j] = 1;
            batch.seq_id  [j][0] = 0;
            // 마지막 배치의 마지막 토큰만 logits 계산
            batch.logits  [j] = (i + j == n_tokens - 1) ? 1 : 0;
        }
        batch.n_tokens = this_n;

        int ret = llama_decode(ctx, batch);
        llama_batch_free(batch);
        if (ret != 0) return ret;
    }
    return 0;
}

int llw_decode_token(void* ctx_ptr, int32_t token, int32_t pos) {
    auto* ctx = (struct llama_context*)ctx_ptr;
    llama_batch batch = llama_batch_init(1, 0, 1);
    batch.token   [0] = token;
    batch.pos     [0] = pos;
    batch.n_seq_id[0] = 1;
    batch.seq_id  [0][0] = 0;
    batch.logits  [0] = 1; // 항상 logits 계산 (샘플링 필요)
    batch.n_tokens = 1;
    int ret = llama_decode(ctx, batch);
    llama_batch_free(batch);
    return ret;
}

// ── 샘플러 ────────────────────────────────────────────────────────

void* llw_create_sampler(float temperature, float top_p, uint32_t seed) {
    auto sparams = llama_sampler_chain_default_params();
    auto* chain = llama_sampler_chain_init(sparams);

    if (temperature <= 0.0f) {
        llama_sampler_chain_add(chain, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(top_p, 1));
        llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(chain, llama_sampler_init_dist(seed));
    }
    return (void*)chain;
}

int32_t llw_sample(void* sampler, void* ctx) {
    return llama_sampler_sample(
        (struct llama_sampler*)sampler,
        (struct llama_context*)ctx,
        -1 // -1 = 마지막 토큰 logits 사용
    );
}

void llw_sampler_accept(void* sampler, int32_t token) {
    llama_sampler_accept((struct llama_sampler*)sampler, token);
}

void llw_free_sampler(void* sampler) {
    llama_sampler_free((struct llama_sampler*)sampler);
}

} // extern "C"
