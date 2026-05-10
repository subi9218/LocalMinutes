#!/usr/bin/env python3
"""Run OpenAI/GPT transcription, diarization, summary, and local comparison.

This script intentionally does not call local Whisper, sherpa-onnx, llama.cpp,
or the app database. It only:
  1. Splits the WAV into API-size chunks with Python's stdlib wave module.
  2. Calls OpenAI's audio transcription API with gpt-4o-transcribe-diarize.
  3. Calls the Responses API with gpt-5.2 for summary and comparison.
  4. Writes outputs next to the existing local reference export.

Required:
  export OPENAI_API_KEY="..."

Usage:
  python3 tool/openai_gpt_extract_compare.py \
    "/path/to/meeting.wav" \
    "/path/to/local_reference_export"
"""

from __future__ import annotations

import argparse
import http.client
import json
import mimetypes
import os
import pathlib
import tempfile
import time
import uuid
import wave
from dataclasses import dataclass
from typing import Any


TRANSCRIBE_MODEL = "gpt-4o-transcribe-diarize"
SUMMARY_MODEL = "gpt-5.2"
OPENAI_HOST = "api.openai.com"
MAX_CHUNK_SECONDS = 8 * 60


@dataclass
class Segment:
    start_ms: int
    end_ms: int
    speaker: str | None
    text: str

    def to_json(self) -> dict[str, Any]:
        return {
            "startMs": self.start_ms,
            "endMs": self.end_ms,
            "speaker": self.speaker,
            "text": self.text,
        }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("wav_path")
    parser.add_argument("local_reference_dir")
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise SystemExit(
            "OPENAI_API_KEY가 없습니다. 예: export OPENAI_API_KEY='sk-...'"
        )

    wav_path = pathlib.Path(args.wav_path).expanduser().resolve()
    local_dir = pathlib.Path(args.local_reference_dir).expanduser().resolve()
    if not wav_path.exists():
        raise SystemExit(f"WAV 파일을 찾을 수 없습니다: {wav_path}")
    if not local_dir.exists():
        raise SystemExit(f"로컬 기준 결과 폴더를 찾을 수 없습니다: {local_dir}")

    stamp = time.strftime("%Y-%m-%dT%H%M%S")
    out_dir = pathlib.Path("/Users/channy/meeting_assistant2/exports") / (
        f"{wav_path.stem}_openai_gpt_{stamp}"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"출력 폴더: {out_dir}")
    print("[1/5] WAV 청크 분할")
    chunks, audio_ms = split_wav(wav_path, out_dir / "_chunks")
    print(f"오디오 길이: {format_duration(audio_ms)} · 청크 {len(chunks)}개")

    print(f"[2/5] OpenAI STT+화자분리 시작 ({TRANSCRIBE_MODEL})")
    stt_start = time.perf_counter()
    all_segments: list[Segment] = []
    raw_transcription_responses: list[dict[str, Any]] = []
    for idx, chunk in enumerate(chunks, start=1):
        chunk_offset_ms = int(chunk["offset_sec"] * 1000)
        print(
            f"  청크 {idx}/{len(chunks)} · "
            f"{format_duration(chunk_offset_ms)}부터 · "
            f"{chunk['path'].stat().st_size / 1024 / 1024:.1f}MB"
        )
        response = transcribe_chunk(api_key, chunk["path"])
        raw_transcription_responses.append(response)
        segments = parse_transcription_segments(response, chunk_offset_ms)
        all_segments.extend(segments)
        print(f"    세그먼트 +{len(segments)}")
    stt_elapsed_ms = int((time.perf_counter() - stt_start) * 1000)
    stt_rtf = stt_elapsed_ms / audio_ms if audio_ms else 0
    print(
        f"OpenAI STT 완료: {len(all_segments)}세그먼트 · "
        f"{format_duration(stt_elapsed_ms)} · RTF {stt_rtf:.3f}x"
    )

    write_transcription_outputs(out_dir, all_segments, raw_transcription_responses)

    print(f"[3/5] GPT 요약 생성 ({SUMMARY_MODEL})")
    transcript_text = diarized_transcript_text(all_segments)
    summary_start = time.perf_counter()
    summary_json_text = call_responses(
        api_key,
        SUMMARY_MODEL,
        build_summary_prompt(transcript_text),
        json_object=True,
    )
    summary_elapsed_ms = int((time.perf_counter() - summary_start) * 1000)
    summary = safe_json_loads(summary_json_text)
    (out_dir / "summary_raw.txt").write_text(summary_json_text, encoding="utf-8")
    (out_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (out_dir / "summary.md").write_text(summary_to_markdown(summary), encoding="utf-8")
    (out_dir / "decisions_action_items.md").write_text(
        decisions_action_items_to_markdown(summary), encoding="utf-8"
    )
    print(f"요약 완료: {format_duration(summary_elapsed_ms)}")

    print("[4/5] 로컬 결과와 GPT 결과 비교")
    compare_start = time.perf_counter()
    local_summary = read_optional(local_dir / "summary.md")
    local_metrics = read_optional(local_dir / "metrics.json")
    local_transcript_sample = read_optional(local_dir / "transcript_diarized.txt")
    comparison = call_responses(
        api_key,
        SUMMARY_MODEL,
        build_comparison_prompt(
            local_summary=local_summary,
            local_metrics=local_metrics,
            local_transcript_sample=local_transcript_sample,
            gpt_summary=summary_to_markdown(summary),
            gpt_metrics=json.dumps(
                {
                    "audioDuration": format_duration(audio_ms),
                    "sttModel": TRANSCRIBE_MODEL,
                    "sttElapsed": format_duration(stt_elapsed_ms),
                    "sttRtf": stt_rtf,
                    "segments": len(all_segments),
                    "summaryModel": SUMMARY_MODEL,
                    "summaryElapsed": format_duration(summary_elapsed_ms),
                },
                ensure_ascii=False,
                indent=2,
            ),
            gpt_transcript_sample=transcript_text,
        ),
        json_object=False,
    )
    compare_elapsed_ms = int((time.perf_counter() - compare_start) * 1000)
    (out_dir / "comparison.md").write_text(comparison, encoding="utf-8")
    print(f"비교 완료: {format_duration(compare_elapsed_ms)}")

    print("[5/5] 메트릭 저장")
    metrics = {
        "wavPath": str(wav_path),
        "audioMs": audio_ms,
        "audioDuration": format_duration(audio_ms),
        "sttModel": TRANSCRIBE_MODEL,
        "sttElapsedMs": stt_elapsed_ms,
        "sttElapsed": format_duration(stt_elapsed_ms),
        "sttRtf": stt_rtf,
        "segments": len(all_segments),
        "summaryModel": SUMMARY_MODEL,
        "summaryElapsedMs": summary_elapsed_ms,
        "summaryElapsed": format_duration(summary_elapsed_ms),
        "comparisonElapsedMs": compare_elapsed_ms,
        "comparisonElapsed": format_duration(compare_elapsed_ms),
        "localReferenceDir": str(local_dir),
        "outputDir": str(out_dir),
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    (out_dir / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (out_dir / "README.md").write_text(build_readme(metrics), encoding="utf-8")
    print(f"완료: {out_dir}")


def split_wav(
    wav_path: pathlib.Path, chunk_dir: pathlib.Path
) -> tuple[list[dict[str, Any]], int]:
    chunk_dir.mkdir(parents=True, exist_ok=True)
    chunks: list[dict[str, Any]] = []
    with wave.open(str(wav_path), "rb") as src:
        params = src.getparams()
        frame_rate = src.getframerate()
        total_frames = src.getnframes()
        audio_ms = int(total_frames / frame_rate * 1000)
        frames_per_chunk = int(frame_rate * MAX_CHUNK_SECONDS)
        idx = 0
        offset_frame = 0
        while offset_frame < total_frames:
            idx += 1
            frames_to_read = min(frames_per_chunk, total_frames - offset_frame)
            frames = src.readframes(frames_to_read)
            chunk_path = chunk_dir / f"chunk_{idx:03d}.wav"
            with wave.open(str(chunk_path), "wb") as dst:
                dst.setparams(params)
                dst.writeframes(frames)
            chunks.append(
                {
                    "path": chunk_path,
                    "offset_sec": offset_frame / frame_rate,
                    "duration_sec": frames_to_read / frame_rate,
                }
            )
            offset_frame += frames_to_read
    return chunks, audio_ms


def transcribe_chunk(api_key: str, path: pathlib.Path) -> dict[str, Any]:
    fields = {
        "model": TRANSCRIBE_MODEL,
        "response_format": "json",
        "chunking_strategy": "auto",
    }
    body, content_type = encode_multipart(fields, {"file": path})
    status, data = request(
        api_key,
        "POST",
        "/v1/audio/transcriptions",
        body=body,
        content_type=content_type,
        timeout=600,
    )
    if status >= 300:
        raise RuntimeError(f"transcription failed {status}: {data[:1000]}")
    return json.loads(data)


def call_responses(
    api_key: str, model: str, prompt: str, *, json_object: bool
) -> str:
    payload: dict[str, Any] = {
        "model": model,
        "input": prompt,
        "reasoning": {"effort": "medium"},
    }
    if json_object:
        payload["text"] = {"format": {"type": "json_object"}}
    status, data = request(
        api_key,
        "POST",
        "/v1/responses",
        body=json.dumps(payload).encode("utf-8"),
        content_type="application/json",
        timeout=900,
    )
    if status >= 300:
        raise RuntimeError(f"responses failed {status}: {data[:1000]}")
    response = json.loads(data)
    output_text = response.get("output_text")
    if isinstance(output_text, str):
        return output_text

    chunks: list[str] = []
    for item in response.get("output", []):
        for content in item.get("content", []):
            if content.get("type") in {"output_text", "text"}:
                chunks.append(content.get("text", ""))
    return "".join(chunks)


def request(
    api_key: str,
    method: str,
    path: str,
    *,
    body: bytes,
    content_type: str,
    timeout: int,
) -> tuple[int, str]:
    conn = http.client.HTTPSConnection(OPENAI_HOST, timeout=timeout)
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": content_type,
    }
    conn.request(method, path, body=body, headers=headers)
    resp = conn.getresponse()
    data = resp.read().decode("utf-8", errors="replace")
    conn.close()
    return resp.status, data


def encode_multipart(
    fields: dict[str, str], files: dict[str, pathlib.Path]
) -> tuple[bytes, str]:
    boundary = f"----codex-{uuid.uuid4().hex}"
    parts: list[bytes] = []
    for name, value in fields.items():
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        )
        parts.append(str(value).encode())
        parts.append(b"\r\n")
    for name, path in files.items():
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(
            (
                f'Content-Disposition: form-data; name="{name}"; '
                f'filename="{path.name}"\r\n'
            ).encode()
        )
        parts.append(f"Content-Type: {mime}\r\n\r\n".encode())
        parts.append(path.read_bytes())
        parts.append(b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def parse_transcription_segments(response: dict[str, Any], offset_ms: int) -> list[Segment]:
    candidates = []
    for key in ("segments", "words", "items"):
        value = response.get(key)
        if isinstance(value, list):
            candidates = value
            break

    if not candidates:
        text = str(response.get("text", "")).strip()
        return [Segment(offset_ms, offset_ms, None, text)] if text else []

    segments: list[Segment] = []
    for item in candidates:
        if not isinstance(item, dict):
            continue
        text = str(
            item.get("text")
            or item.get("transcript")
            or item.get("word")
            or ""
        ).strip()
        if not text:
            continue
        start_ms = seconds_to_ms(item.get("start") or item.get("start_time"))
        end_ms = seconds_to_ms(item.get("end") or item.get("end_time"))
        speaker = item.get("speaker") or item.get("speaker_label")
        segments.append(
            Segment(
                offset_ms + start_ms,
                offset_ms + end_ms,
                str(speaker) if speaker is not None else None,
                text,
            )
        )
    return segments


def seconds_to_ms(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, (int, float)):
        return int(float(value) * 1000)
    text = str(value).strip()
    try:
        return int(float(text) * 1000)
    except ValueError:
        return 0


def write_transcription_outputs(
    out_dir: pathlib.Path,
    segments: list[Segment],
    raw_responses: list[dict[str, Any]],
) -> None:
    transcript_lines = [
        f"[{format_timestamp(s.start_ms)} → {format_timestamp(s.end_ms)}] {s.text}"
        for s in segments
    ]
    diarized_lines = [
        f"[{format_timestamp(s.start_ms)} → {format_timestamp(s.end_ms)}] "
        f"{'화자 ' + s.speaker + ': ' if s.speaker else ''}{s.text}"
        for s in segments
    ]
    (out_dir / "transcript.txt").write_text("\n".join(transcript_lines), encoding="utf-8")
    (out_dir / "transcript_diarized.txt").write_text(
        "\n".join(diarized_lines), encoding="utf-8"
    )
    (out_dir / "segments.json").write_text(
        json.dumps([s.to_json() for s in segments], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (out_dir / "transcription_raw_responses.json").write_text(
        json.dumps(raw_responses, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def diarized_transcript_text(segments: list[Segment]) -> str:
    return "\n".join(
        f"[{format_timestamp(s.start_ms)} → {format_timestamp(s.end_ms)}] "
        f"{'화자 ' + s.speaker + ': ' if s.speaker else ''}{s.text}"
        for s in segments
    )


def build_summary_prompt(transcript: str) -> str:
    return f"""아래 한국어 회의 전사본을 분석해서 JSON만 출력하세요.

규칙:
- 전사본에 없는 내용은 만들지 마세요.
- 수치, 일정, 고유명사, 기술 용어는 원문 표기를 보존하세요.
- 화자 라벨이 있으면 담당자/입장 추정에 활용하되, 불명확하면 "(미언급)"이라고 쓰세요.
- keyDiscussions는 구체적 논점 중심으로 작성하세요.
- decisions에는 실제 결정/합의만 넣으세요.
- actionItems는 task/owner/deadline 필드를 가진 객체 배열로 작성하세요.
- openQuestions에는 미결 또는 추가 확인 필요 사항을 넣으세요.

JSON 스키마:
{{
  "meetingTitle": "string",
  "participants": ["string"],
  "keyDiscussions": ["string"],
  "decisions": ["string"],
  "actionItems": [
    {{"task": "string", "owner": "string", "deadline": "string"}}
  ],
  "openQuestions": ["string"]
}}

전사본:
{transcript}
"""


def build_comparison_prompt(
    *,
    local_summary: str,
    local_metrics: str,
    local_transcript_sample: str,
    gpt_summary: str,
    gpt_metrics: str,
    gpt_transcript_sample: str,
) -> str:
    return f"""아래는 같은 WAV에 대한 두 처리 결과입니다.

[로컬 처리 메트릭]
{local_metrics}

[로컬 요약]
{local_summary}

[로컬 전사 일부/전체]
{truncate(local_transcript_sample, 35000)}

[OpenAI/GPT 처리 메트릭]
{gpt_metrics}

[OpenAI/GPT 요약]
{gpt_summary}

[OpenAI/GPT 전사 일부/전체]
{truncate(gpt_transcript_sample, 35000)}

한국어 Markdown으로 비교 분석하세요.
반드시 포함:
- STT 속도/RTF 비교
- 화자 분리 품질과 화자 수 과분리 여부 비교
- 요약 제목/주요 논의/결정사항/액션아이템 차이
- GPT 결과가 더 나은 점
- 로컬 결과가 더 나은 점
- 앱 제품 관점에서 어떤 방식을 기본값/옵션으로 둘지 추천
"""


def summary_to_markdown(summary: dict[str, Any]) -> str:
    return "\n".join(
        [
            f"# {summary.get('meetingTitle', '회의 요약')}",
            "",
            "## 참석자",
            markdown_list(summary.get("participants")),
            "",
            "## 주요 논의",
            markdown_list(summary.get("keyDiscussions")),
            "",
            "## 결정사항",
            markdown_list(summary.get("decisions")),
            "",
            "## 액션아이템",
            markdown_actions(summary.get("actionItems")),
            "",
            "## 미해결 이슈",
            markdown_list(summary.get("openQuestions")),
            "",
        ]
    )


def decisions_action_items_to_markdown(summary: dict[str, Any]) -> str:
    return "\n".join(
        [
            "# 결정사항 / 액션아이템",
            "",
            "## 결정사항",
            markdown_list(summary.get("decisions")),
            "",
            "## 액션아이템",
            markdown_actions(summary.get("actionItems")),
            "",
        ]
    )


def markdown_list(value: Any) -> str:
    if not isinstance(value, list) or not value:
        return "- (없음)"
    return "\n".join(f"- {str(item)}" for item in value)


def markdown_actions(value: Any) -> str:
    if not isinstance(value, list) or not value:
        return "- (없음)"
    lines = []
    for item in value:
        if isinstance(item, dict):
            lines.append(
                f"- {item.get('task', '')} / "
                f"담당: {item.get('owner', '(미언급)')} / "
                f"기한: {item.get('deadline', '(미언급)')}"
            )
        else:
            lines.append(f"- {item}")
    return "\n".join(lines)


def safe_json_loads(text: str) -> dict[str, Any]:
    try:
        value = json.loads(text)
        if isinstance(value, dict):
            return value
    except json.JSONDecodeError:
        pass
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end > start:
        value = json.loads(text[start : end + 1])
        if isinstance(value, dict):
            return value
    raise ValueError("GPT 요약 JSON 파싱 실패")


def read_optional(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    head = text[: limit // 2]
    tail = text[-limit // 2 :]
    return f"{head}\n\n[...중간 생략...]\n\n{tail}"


def format_timestamp(ms: int) -> str:
    total = max(0, ms // 1000)
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def format_duration(ms: int) -> str:
    total = max(0, round(ms / 1000))
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}시간 {m:02d}분 {s:02d}초"
    return f"{m}분 {s:02d}초"


def build_readme(metrics: dict[str, Any]) -> str:
    return f"""# OpenAI/GPT 기준 추출 결과

- WAV: `{metrics["wavPath"]}`
- 오디오 길이: {metrics["audioDuration"]}
- STT+화자분리 모델: `{metrics["sttModel"]}`
- STT+화자분리 소요: {metrics["sttElapsed"]} / RTF {metrics["sttRtf"]:.3f}x
- 요약 모델: `{metrics["summaryModel"]}`
- 요약 소요: {metrics["summaryElapsed"]}
- 로컬 기준 폴더: `{metrics["localReferenceDir"]}`

## 파일

- `transcript.txt`: GPT 전사 텍스트
- `transcript_diarized.txt`: GPT 화자 라벨 포함 전사
- `segments.json`: 타임스탬프/화자 포함 세그먼트 JSON
- `summary.md`: GPT 회의록 요약
- `summary.json`: GPT 구조화 요약 JSON
- `decisions_action_items.md`: 결정사항/액션아이템만 분리
- `comparison.md`: 로컬 결과와 GPT 결과 비교 분석
- `metrics.json`: 처리 시간/RTF
"""


if __name__ == "__main__":
    main()
