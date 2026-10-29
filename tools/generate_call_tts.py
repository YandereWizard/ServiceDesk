#!/usr/bin/env python3
"""Bake customer VO lines for Service Desk call graphs.

Reads data/calls/<call>.json, finds line_id fields, writes:
  audio/calls/<voice_dir>/<line_id>.ogg  (or .wav with --format wav)

No runtime API keys — bake at build/dev time only.

Backends
--------
  espeak   Free/local via espeak-ng + ffmpeg (default). Good for placeholders.
  piper    Offline neural TTS if `piper` is on PATH (model path via --piper-model).
  openai   OpenAI TTS — needs OPENAI_API_KEY in the environment (never pass on argv).
  eleven   ElevenLabs — needs ELEVENLABS_API_KEY + --voice-id.

Naming convention (must match JSON)
-----------------------------------
  ring.line_id              → ring_intro.ogg
  name_check.correct_line_id → name_correct.ogg
  name_check.wrong_line_id   → name_wrong.ogg
  diagnose.choices[].line_id → diagnose_<choice_id>.ogg
  resolve.success_line_id    → resolve_success.ogg
  resolve.partial_line_id    → resolve_partial.ogg

Examples
--------
  # Free local greeting (and any other lines) with espeak-ng:
  python3 tools/generate_call_tts.py data/calls/password_purge.json

  # One line only:
  python3 tools/generate_call_tts.py data/calls/password_purge.json --only ring_intro

  # Piper (offline neural):
  python3 tools/generate_call_tts.py data/calls/password_purge.json \\
      --backend piper --piper-model ~/models/en_US-lessac-medium.onnx

  # ElevenLabs (bake machine only — key from env):
  export ELEVENLABS_API_KEY=...
  python3 tools/generate_call_tts.py data/calls/password_purge.json \\
      --backend eleven --voice-id EXAVITQu4vr4xnSDxMaL

  # OpenAI TTS:
  export OPENAI_API_KEY=...
  python3 tools/generate_call_tts.py data/calls/password_purge.json \\
      --backend openai --voice-id nova
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]


def collect_lines(call: dict) -> list[tuple[str, str]]:
    """Return (line_id, text) pairs for every customer-spoken line."""
    out: list[tuple[str, str]] = []

    ring = call.get("ring") or {}
    if ring.get("line_id") and ring.get("intro"):
        out.append((str(ring["line_id"]), str(ring["intro"])))

    nc = call.get("name_check") or {}
    if nc.get("correct_line_id") and nc.get("correct_reply"):
        out.append((str(nc["correct_line_id"]), str(nc["correct_reply"])))
    if nc.get("wrong_line_id") and nc.get("wrong_reply"):
        out.append((str(nc["wrong_line_id"]), str(nc["wrong_reply"])))

    diag = call.get("diagnose") or {}
    for choice in diag.get("choices") or []:
        if not isinstance(choice, dict):
            continue
        lid = choice.get("line_id") or (
            f"diagnose_{choice['id']}" if choice.get("id") else None
        )
        if lid and choice.get("reply"):
            out.append((str(lid), str(choice["reply"])))

    res = call.get("resolve") or {}
    if res.get("success_line_id") and res.get("success_reply"):
        out.append((str(res["success_line_id"]), str(res["success_reply"])))
    if res.get("partial_line_id") and res.get("partial_reply"):
        out.append((str(res["partial_line_id"]), str(res["partial_reply"])))

    return out


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True)


def wav_to_ogg(wav: Path, ogg: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg required to write .ogg (or pass --format wav)")
    run(
        [
            ffmpeg,
            "-y",
            "-i",
            str(wav),
            "-c:a",
            "libvorbis",
            "-q:a",
            "4",
            str(ogg),
        ]
    )


def synth_espeak(text: str, wav: Path, voice: str) -> None:
    exe = shutil.which("espeak-ng") or shutil.which("espeak")
    if not exe:
        raise SystemExit("espeak-ng not found — install it or pick another --backend")
    run([exe, "-v", voice, "-s", "150", "-w", str(wav), text])


def synth_piper(text: str, wav: Path, model: str) -> None:
    exe = shutil.which("piper")
    if not exe:
        raise SystemExit("piper not on PATH")
    if not model:
        raise SystemExit("--piper-model is required for --backend piper")
    proc = subprocess.run(
        [exe, "--model", model, "--output_file", str(wav)],
        input=text.encode("utf-8"),
        check=True,
    )
    _ = proc


def synth_openai(text: str, wav: Path, voice_id: str) -> None:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise SystemExit("Set OPENAI_API_KEY in the environment (do not pass on argv)")
    voice = voice_id or "nova"
    body = json.dumps(
        {"model": "gpt-4o-mini-tts", "voice": voice, "input": text, "format": "wav"}
    ).encode("utf-8")
    # Fallback model name if mini-tts unavailable — try tts-1
    req = urllib.request.Request(
        "https://api.openai.com/v1/audio/speech",
        data=body,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            wav.write_bytes(resp.read())
    except urllib.error.HTTPError as exc:
        # Retry with classic tts-1 + mp3 then ffmpeg — keep script useful.
        if exc.code in (400, 404):
            body2 = json.dumps(
                {"model": "tts-1", "voice": voice, "input": text}
            ).encode("utf-8")
            req2 = urllib.request.Request(
                "https://api.openai.com/v1/audio/speech",
                data=body2,
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                },
                method="POST",
            )
            mp3 = wav.with_suffix(".mp3")
            with urllib.request.urlopen(req2) as resp:
                mp3.write_bytes(resp.read())
            run(["ffmpeg", "-y", "-i", str(mp3), str(wav)])
            mp3.unlink(missing_ok=True)
        else:
            raise


def synth_eleven(text: str, wav: Path, voice_id: str) -> None:
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise SystemExit("Set ELEVENLABS_API_KEY in the environment")
    if not voice_id:
        raise SystemExit("--voice-id is required for --backend eleven")
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=pcm_22050"
    body = json.dumps(
        {
            "text": text,
            "model_id": "eleven_monolingual_v1",
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "xi-api-key": key,
            "Content-Type": "application/json",
            "Accept": "application/octet-stream",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        pcm = resp.read()
    # Wrap raw PCM16 mono 22050 as WAV
    import wave

    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(pcm)


def bake_one(
    line_id: str,
    text: str,
    out_dir: Path,
    backend: str,
    voice: str,
    voice_id: str,
    piper_model: str,
    fmt: str,
) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / f"{line_id}.wav"
        if backend == "espeak":
            synth_espeak(text, wav, voice)
        elif backend == "piper":
            synth_piper(text, wav, piper_model)
        elif backend == "openai":
            synth_openai(text, wav, voice_id)
        elif backend == "eleven":
            synth_eleven(text, wav, voice_id)
        else:
            raise SystemExit(f"Unknown backend: {backend}")

        if fmt == "wav":
            dest = out_dir / f"{line_id}.wav"
            shutil.copyfile(wav, dest)
        else:
            dest = out_dir / f"{line_id}.ogg"
            wav_to_ogg(wav, dest)
        print(f"Wrote {dest.relative_to(REPO_ROOT)}")
        return dest


def main(argv: Iterable[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("call_json", type=Path, help="Path to call graph JSON")
    p.add_argument(
        "--backend",
        choices=("espeak", "piper", "openai", "eleven"),
        default="espeak",
    )
    p.add_argument(
        "--voice",
        default="en-us+f3",
        help="espeak voice id (default: en-us+f3)",
    )
    p.add_argument(
        "--voice-id",
        default="",
        help="ElevenLabs / OpenAI voice id",
    )
    p.add_argument("--piper-model", default="", help="Path to Piper .onnx model")
    p.add_argument("--only", default="", help="Bake a single line_id")
    p.add_argument("--format", choices=("ogg", "wav"), default="ogg")
    p.add_argument(
        "--list",
        action="store_true",
        help="List line ids and texts; do not synthesize",
    )
    args = p.parse_args(list(argv) if argv is not None else None)

    path = args.call_json
    if not path.is_absolute():
        path = (Path.cwd() / path).resolve()
    call = json.loads(path.read_text(encoding="utf-8"))
    voice_dir = str(call.get("voice_dir") or call.get("id") or path.stem)
    out_dir = REPO_ROOT / "audio" / "calls" / voice_dir

    lines = collect_lines(call)
    if args.only:
        lines = [(lid, txt) for lid, txt in lines if lid == args.only]
        if not lines:
            raise SystemExit(f"No line_id={args.only!r} in {path}")

    if args.list:
        for lid, txt in lines:
            print(f"{lid}\t{txt[:80]}{'…' if len(txt) > 80 else ''}")
        return 0

    for lid, txt in lines:
        bake_one(
            lid,
            txt,
            out_dir,
            args.backend,
            args.voice,
            args.voice_id,
            args.piper_model,
            args.format,
        )
    print(f"Done — {len(lines)} clip(s) → {out_dir.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
