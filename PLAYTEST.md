# Playtest notes — Desk UI + AI voice + AV scaffold

## What to click (Password Purge)

1. Open the project in **Godot 4.3+** → **F5**.
2. **Clock In — Start Shift**.
3. Top-right **Incoming Call** panel: pulsing amber = ringing.
   - **Accept** → call starts, Morgan’s greeting plays if `ring_intro.ogg` is present.
   - **Decline** → stress bump; queue retries. Decline twice → forced pickup.
4. **Name check** — type `Morgan Ellery` from the ticket (keyboard always works).
   - Optional: enable **Mic (PTT)** on the right, hold **Push-to-Talk** (records only; STT stub — still confirm by typing).
5. **Diagnose** — pick the stale-MFA option (not Caps Lock).
6. **Resolve** — check the three steps **in order**.
7. Read the **grade card** → **Next — End Demo Shift**.

Optional AV (right rail):

- **Enable camera** — shows webcam preview if CameraServer finds a device; otherwise stays “WEBCAM OFFLINE”.
- Missing cam/mic **never** blocks the loop.

## Dropping in AI voice clips

Path: `audio/calls/password_purge/<line_id>.ogg` (`.wav` / `.mp3` also OK).

| line_id | When it plays |
|---------|----------------|
| `ring_intro` | On Accept (greeting) — espeak sample shipped |
| `name_correct` / `name_wrong` | After name confirm / fail — espeak shipped |
| `diagnose_mfa_stale` / `diagnose_keyboard` | After diagnose pick — espeak shipped |
| `resolve_success` / `resolve_partial` | After checklist / partial — espeak shipped |

Quality is placeholder (espeak-ng). Re-bake with Piper/ElevenLabs for ship VO.

Regenerate (free, no API key):

```bash
python3 tools/generate_call_tts.py data/calls/password_purge.json --list
python3 tools/generate_call_tts.py data/calls/password_purge.json
# or one line:
python3 tools/generate_call_tts.py data/calls/password_purge.json --only name_correct
```

Paid bake (dev machine only — keys in env, never at runtime):

```bash
export ELEVENLABS_API_KEY=…   # or OPENAI_API_KEY
python3 tools/generate_call_tts.py data/calls/password_purge.json \
  --backend eleven --voice-id <id>
```

If a clip is missing, captions still show; OS TTS may speak if the host exposes voices.

## Known gaps for Phillip

| Item | Status |
|------|--------|
| Quality VO (replace espeak stand-ins) | Bake with Piper/ElevenLabs + preferred voice id |
| Real speech-to-text for name check | Stub only (PTT records; typed fallback required) |
| Whisper / cloud STT | Next PR — needs plugin or API key policy |
| Mic/camera OS permissions | Player must allow when opting in; game continues if denied |
| Full 6-call shift | Still Day 2 |
