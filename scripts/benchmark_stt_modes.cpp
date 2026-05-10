#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "../native/whisper_wrapper/whisper_wrapper.h"

namespace {

uint32_t u32le(const std::vector<uint8_t>& b, size_t p) {
    return static_cast<uint32_t>(b[p]) |
           (static_cast<uint32_t>(b[p + 1]) << 8) |
           (static_cast<uint32_t>(b[p + 2]) << 16) |
           (static_cast<uint32_t>(b[p + 3]) << 24);
}

uint16_t u16le(const std::vector<uint8_t>& b, size_t p) {
    return static_cast<uint16_t>(b[p]) |
           (static_cast<uint16_t>(b[p + 1]) << 8);
}

std::string fourcc(const std::vector<uint8_t>& b, size_t p) {
    return std::string(reinterpret_cast<const char*>(&b[p]), 4);
}

std::vector<float> load_wav_16k_mono_i16(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) throw std::runtime_error("cannot open wav: " + path);
    std::vector<uint8_t> bytes(
        (std::istreambuf_iterator<char>(in)),
        std::istreambuf_iterator<char>());
    if (bytes.size() < 44 || fourcc(bytes, 0) != "RIFF" ||
        fourcc(bytes, 8) != "WAVE") {
        throw std::runtime_error("not a RIFF/WAVE file");
    }

    uint16_t audio_format = 0;
    uint16_t channels = 0;
    uint32_t sample_rate = 0;
    uint16_t bits_per_sample = 0;
    size_t data_offset = 0;
    uint32_t data_size = 0;

    for (size_t p = 12; p + 8 <= bytes.size();) {
        const auto id = fourcc(bytes, p);
        const auto chunk_size = u32le(bytes, p + 4);
        if (p + 8 + chunk_size > bytes.size()) break;
        if (id == "fmt ") {
            audio_format = u16le(bytes, p + 8);
            channels = u16le(bytes, p + 10);
            sample_rate = u32le(bytes, p + 12);
            bits_per_sample = u16le(bytes, p + 22);
        } else if (id == "data") {
            data_offset = p + 8;
            data_size = chunk_size;
            break;
        }
        p += 8 + chunk_size + (chunk_size & 1);
    }

    if (audio_format != 1 || channels != 1 || sample_rate != 16000 ||
        bits_per_sample != 16 || data_offset == 0) {
        throw std::runtime_error("expected PCM s16 mono 16k wav");
    }

    const int frames = static_cast<int>(data_size / 2);
    std::vector<float> out(frames);
    for (int i = 0; i < frames; ++i) {
        const size_t p = data_offset + static_cast<size_t>(i) * 2;
        const int16_t v = static_cast<int16_t>(u16le(bytes, p));
        out[i] = static_cast<float>(v) / 32768.0f;
    }
    return out;
}

struct Mode {
    std::string label;
    std::string model_path;
    int decode_mode;
};

void run_mode(const Mode& mode, const std::vector<float>& samples) {
    constexpr int sample_rate = 16000;
    constexpr int chunk_samples = sample_rate * 30;
    constexpr int overlap_samples = sample_rate * 2;
    constexpr int advance = chunk_samples - overlap_samples;

    void* ctx = wsw_load_model(mode.model_path.c_str());
    if (ctx == nullptr) throw std::runtime_error("model load failed: " + mode.model_path);

    const auto started = std::chrono::steady_clock::now();
    int chunks = 0;
    int segments = 0;
    for (int start = 0; start < static_cast<int>(samples.size()); start += advance) {
        const int end = std::min(start + chunk_samples, static_cast<int>(samples.size()));
        const int n = end - start;
        const int ret = wsw_transcribe(
            ctx,
            samples.data() + start,
            n,
            "ko",
            6,
            "회의록 전사.",
            mode.decode_mode);
        if (ret != 0) {
            wsw_free_model(ctx);
            throw std::runtime_error("transcribe failed: " + mode.label);
        }
        segments += wsw_n_segments(ctx);
        chunks++;
        if (end >= static_cast<int>(samples.size())) break;
    }
    const auto ended = std::chrono::steady_clock::now();
    wsw_free_model(ctx);

    const double elapsed =
        std::chrono::duration_cast<std::chrono::milliseconds>(ended - started).count() /
        1000.0;
    const double audio_sec = samples.size() / 16000.0;
    std::cout << mode.label
              << "\tdecode=" << mode.decode_mode
              << "\tchunks=" << chunks
              << "\tsegments=" << segments
              << "\telapsed_sec=" << elapsed
              << "\trtf=" << (elapsed / audio_sec)
              << std::endl;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "usage: benchmark_stt_modes WAV FAST_MODEL ACCURATE_MODEL [mode]\n"
                  << "mode: ultra|balanced|accurate|all\n";
        return 2;
    }

    const std::string wav = argv[1];
    const std::string fast_model = argv[2];
    const std::string accurate_model = argv[3];
    const std::string selected = argc >= 5 ? argv[4] : "all";
    const auto samples = load_wav_16k_mono_i16(wav);
    std::cout << "audio_sec=" << (samples.size() / 16000.0)
              << "\tsamples=" << samples.size() << std::endl;

    const std::vector<Mode> modes = {
        {"ultra", fast_model, 0},
        {"balanced", fast_model, 1},
        {"accurate", accurate_model, 2},
    };
    for (const auto& mode : modes) {
        if (selected != "all" && selected != mode.label) continue;
        run_mode(mode, samples);
    }
    return 0;
}
