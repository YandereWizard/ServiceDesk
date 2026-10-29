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

## Second window / dual display

Fantasy: primary screen = softphone + ticket workspace; second OS window = **Northwave Knowledge Base** (SOP glance board + live ticket mirror).

### How to try it

1. **F5** in Godot 4.3+.
2. On Clock In (or at the desk): click **Settings** (top-right) or press **Esc**.
3. Toggle **Second window**.
4. **One monitor:** the display picker is disabled with a note; the KB window opens **offset** on the same screen so both stay usable.
5. **Two+ monitors:** use **Target display** to choose which screen hosts the KB window (Godot `DisplayServer` screen list). The window centers on that screen.
6. Toggle off (or close the KB window’s title-bar X) → second window closes; preference persists in `user://settings.cfg`.
7. Restart the game with the toggle still on → KB window should reopen on the saved display.

### What you should see on the second window

- Header: Northwave Knowledge Base, live phase / stress / score
- Left: live ticket mirror (id, caller, subject) synced from the desk
- Right: Password Purge SOP quick reference (read-only)

Requires `display/window/subwindows/embed_subwindows=false` (already set) so Godot creates a real OS window, not an embedded sub-viewport.

## Known gaps for Phillip

| Item | Status |
|------|--------|
| Quality VO (replace espeak stand-ins) | Bake with Piper/ElevenLabs + preferred voice id |
| Real speech-to-text for name check | Stub only (PTT records; typed fallback required) |
| Whisper / cloud STT | Next PR — needs plugin or API key policy |
| Mic/camera OS permissions | Player must allow when opting in; game continues if denied |
| Full 6-call shift | Still Day 2 |
| Multi-monitor on some Linux/Wayland setups | Confirm screen indices / placement in your DE |
