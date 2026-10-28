# Service Desk

Workplace comedy helpdesk game — take the call, type the caller name, diagnose the mess, fix it before stress cooks you, then get graded like a real ticket review.

**Engine:** Godot 4 · **Demo Day 1** vertical slice (one playable call: *Password Purge*, text-only).

## Requirements

- [Godot 4.3+](https://godotengine.org/download) (4.3 or 4.4 recommended)
- Keyboard + mouse

## Open & run

1. Install Godot 4 and open the **Project Manager**.
2. **Import** → select this repo’s `project.godot` (repo root).
3. Open the project, then press **F5** (or Play).
4. Click **Clock In — Start Shift**, accept the incoming call, and play through:
   - **Name check** — type the caller name from the ticket (`Morgan Ellery`)
   - **Diagnose** — pick the real root cause (one correct, one red herring)
   - **Resolve** — complete the checklist **in order**
   - **Grade** — see letter grade + Lead roast, then end the demo shift

### From the command line (optional)

```bash
godot4 --path /path/to/ServiceDesk
# or
godot --path /path/to/ServiceDesk
```

## Demo Day 1 scope

| Piece | Status |
|-------|--------|
| Streamlined desk HUD (ticket, name field, choices, stress/score) | ✅ |
| Core loop: Ring → Name → Diagnose → Resolve → Grade | ✅ |
| Call: Password Purge (text-only) | ✅ |
| Stress + scoring stubs (wired to name/diagnose/resolve/speed) | ✅ |
| Full 6-call shift, VO, Steam export | Day 2–3 |

Design plan (project notes): tone = workplace comedy; UI = game HUD (not a ServiceNow clone); setting flavor = Northwave Corp Floor 2.

## Project layout

```
project.godot          # Godot 4 project
scenes/                # main, shift_start, desk_hud
scripts/               # game_state (autoload), UI + loop
data/calls/            # JSON call graphs (password_purge.json)
```

## Tips for playtesters

- Wrong name spikes stress; two fails escalate but the call continues.
- Resolve steps must be clicked in sequence — out-of-order hits stress.
- Stress at 100 ends the shift (manager override).
