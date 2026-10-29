# Service Desk

Workplace comedy helpdesk game — take the call, type the caller name, diagnose the mess, fix it before stress cooks you, then get graded like a real ticket review.

**Engine:** Godot 4 · **Vertical slice:** *Password Purge* with desk workstation HUD, baked AI voice playback, and optional webcam/mic scaffolding.

## Requirements

- [Godot 4.3+](https://godotengine.org/download) (4.3 or 4.4 recommended)
- Keyboard + mouse
- Optional: webcam / mic (opt-in; never required)
- Optional for VO bake: `espeak-ng` + `ffmpeg`, or Piper / ElevenLabs / OpenAI (dev machine only)

## Open & run

1. Install Godot 4 → **Import** this repo’s `project.godot`.
2. Press **F5** (Play).
3. **Clock In** → top-right **Accept** the incoming call → play through name / diagnose / resolve / grade.

See **[PLAYTEST.md](PLAYTEST.md)** for the click-path, how to drop in WAV/OGG lines, and known gaps.

### From the command line (optional)

```bash
godot4 --path /path/to/ServiceDesk
```

## What works today vs next

| Feature | Today | Next / needs Phillip |
|---------|-------|----------------------|
| Password Purge loop (ring → grade) | ✅ | — |
| Desk HUD (ticket, incoming Accept/Decline, stress/score) | ✅ | Polish / more calls |
| Baked AI voice playback from `audio/calls/<id>/<line_id>.ogg` | ✅ | Quality VO for remaining lines |
| `ring_intro` sample (local espeak-ng) | ✅ shipped | Replace with ElevenLabs/Piper if desired |
| Missing clip → captions + optional OS TTS | ✅ | — |
| Runtime TTS API keys | ❌ not used (by design) | Keep bake-time only |
| Webcam preview (CameraServer, opt-in) | ✅ scaffold | OS permission on player machine |
| Mic push-to-talk record (opt-in) | ✅ scaffold | Real STT |
| Name via speech-to-text | Stub (typed fallback always) | Whisper.cpp / cloud STT + keys or offline model |
| Full 6-call shift | ❌ | Day 2 content |

## Regenerating AI voice clips

Clips live at `audio/calls/password_purge/<line_id>.ogg` and must match JSON `line_id` fields.

```bash
# List slots from the call graph
python3 tools/generate_call_tts.py data/calls/password_purge.json --list

# Free/local bake (espeak-ng + ffmpeg) — no secrets
python3 tools/generate_call_tts.py data/calls/password_purge.json

# Piper (offline neural)
python3 tools/generate_call_tts.py data/calls/password_purge.json \
  --backend piper --piper-model /path/to/en_US-lessac-medium.onnx

# ElevenLabs or OpenAI — keys in env only, never at game runtime
export ELEVENLABS_API_KEY=…    # or OPENAI_API_KEY
python3 tools/generate_call_tts.py data/calls/password_purge.json \
  --backend eleven --voice-id <voice_id>
```

Details: `audio/calls/password_purge/README.md`.

## Project layout

```
project.godot
scenes/                 # main, shift_start, desk_hud
scripts/                # game_state, desk_hud, call_voice, player_av
data/calls/             # JSON call graphs (+ line_id for VO)
audio/calls/<id>/       # baked OGG/WAV per line_id
tools/generate_call_tts.py
PLAYTEST.md
```

## Tips for playtesters

- Wrong name spikes stress; two fails escalate but the call continues.
- Resolve steps must be clicked in sequence.
- Stress at 100 ends the shift (manager override).
- Decline twice forces the call onto your headset (with stress).
- Camera/mic toggles are optional — play fully without them.
