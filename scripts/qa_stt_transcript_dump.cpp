#include <algorithm>
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

std::string clean_text(std::string text) {
    while (!text.empty() && (text.front() == ' ' || text.front() == '\t')) {
        text.erase(text.begin());
    }
    for (char& c : text) {
        if (c == '\n' || c == '\r' || c == '\t') c = ' ';
    }
    return text;
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

}  // namespace

int main(int argc, char** argv) {
    if (argc < 6) {
        std::cerr << "usage: qa_stt_transcript_dump WAV MODEL mode out_tsv label [initial_prompt]\n"
                  << "mode: 0=fast/greedy, 1=balanced/beam2, 2=accurate/beam5\n";
        return 2;
    }

    const std::string wav = argv[1];
    const std::string model = argv[2];
    const int decode_mode = std::stoi(argv[3]);
    const std::string out_path = argv[4];
    const std::string label = argv[5];
    const std::string prompt = argc >= 7 ? argv[6] : "";
    const auto samples = load_wav_16k_mono_i16(wav);

    void* ctx = wsw_load_model(model.c_str());
    if (ctx == nullptr) throw std::runtime_error("model load failed: " + model);

    std::ofstream out(out_path, std::ios::app);
    if (!out) throw std::runtime_error("cannot open output: " + out_path);

    constexpr int sample_rate = 16000;
    constexpr int chunk_samples = sample_rate * 30;
    constexpr int overlap_samples = sample_rate * 2;
    constexpr int advance = chunk_samples - overlap_samples;

    const auto started = std::chrono::steady_clock::now();
    int chunks = 0;
    int emitted = 0;
    int64_t last_end_ms = -1;

    for (int start = 0; start < static_cast<int>(samples.size()); start += advance) {
        const int end = std::min(start + chunk_samples, static_cast<int>(samples.size()));
        const int n = end - start;
        const int ret = wsw_transcribe(
            ctx,
            samples.data() + start,
            n,
            "ko",
            6,
            prompt.c_str(),
            decode_mode);
        if (ret != 0) {
            wsw_free_model(ctx);
            throw std::runtime_error("transcribe failed");
        }

        const int64_t chunk_start_ms = static_cast<int64_t>(start) * 1000 / sample_rate;
        const int segments = wsw_n_segments(ctx);
        for (int i = 0; i < segments; ++i) {
            const int64_t t0 = chunk_start_ms + wsw_segment_t0_ms(ctx, i);
            const int64_t t1 = chunk_start_ms + wsw_segment_t1_ms(ctx, i);
            const std::string text = clean_text(wsw_segment_text(ctx, i));
            if (text.empty()) continue;
            if (last_end_ms >= 0 && t1 <= last_end_ms + 250) continue;
            out << label << '\t'
                << (t0 / 1000.0) << '\t'
                << (t1 / 1000.0) << '\t'
                << text << '\n';
            last_end_ms = std::max(last_end_ms, t1);
            emitted++;
        }

        chunks++;
        if (end >= static_cast<int>(samples.size())) break;
    }

    const auto ended = std::chrono::steady_clock::now();
    const double elapsed =
        std::chrono::duration_cast<std::chrono::milliseconds>(ended - started).count() /
        1000.0;
    std::cout << label
              << "\taudio_sec=" << (samples.size() / 16000.0)
              << "\tchunks=" << chunks
              << "\temitted_segments=" << emitted
              << "\telapsed_sec=" << elapsed
              << "\trtf=" << (elapsed / (samples.size() / 16000.0))
              << std::endl;

    wsw_free_model(ctx);
    return 0;
}
