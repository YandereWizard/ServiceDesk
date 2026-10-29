# Password Purge — baked AI voice slots

Drop clips here named by JSON `line_id`. Runtime looks for `.ogg`, then `.wav`, then `.mp3`.

| File | JSON field | Shipped? |
|------|------------|----------|
| `ring_intro.ogg` | `ring.line_id` | ✅ espeak-ng (placeholder quality) |
| `name_correct.ogg` | `name_check.correct_line_id` | ✅ espeak-ng |
| `name_wrong.ogg` | `name_check.wrong_line_id` | ✅ espeak-ng |
| `diagnose_mfa_stale.ogg` | `diagnose.choices[mfa_stale].line_id` | ✅ espeak-ng |
| `diagnose_keyboard.ogg` | `diagnose.choices[keyboard].line_id` | ✅ espeak-ng |
| `resolve_success.ogg` | `resolve.success_line_id` | ✅ espeak-ng |
| `resolve_partial.ogg` | `resolve.partial_line_id` | ✅ espeak-ng |

All clips are free local espeak-ng stand-ins. Re-bake with Piper / ElevenLabs / OpenAI for ship quality.

Missing clips → HUD shows captions and may try OS TTS. **No API key at game runtime.**

```bash
# List slots
python3 tools/generate_call_tts.py data/calls/password_purge.json --list

# Bake all with free local espeak-ng
python3 tools/generate_call_tts.py data/calls/password_purge.json

# One line
python3 tools/generate_call_tts.py data/calls/password_purge.json --only name_correct
```

See repo README and `docs/voice-and-av-plan.md` (project store) for ElevenLabs / OpenAI / Piper.
