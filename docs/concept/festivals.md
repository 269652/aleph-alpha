## Festivals: emergent, not scheduled

[npc.md](npc.md)'s NPCs self-plan daily schedules and [weather.md](weather.md)
adds real seasons — festivals are what happens when those combine, and stay
consistent with the whole NPC system's "nothing is hand-scripted, it
emerges from real state" philosophy.

- **Trigger conditions are real, not a fixed calendar date**: a harvest
  festival triggers off actual high crop yield
  ([farming.md](farming.md)), a solstice/seasonal festival off
  [weather.md](weather.md)'s season clock, and — the most distinctive
  case — a village can spontaneously hold an anniversary/commemoration
  festival tied to its own simulated history (surviving a
  [disaster](weather.md), a notable [world boss](worldbosses.md) being
  slain nearby, a village founding date) — a genuinely village-specific
  festival, not identical content stamped on every settlement.
- **NPCs collectively replan for it.** On a triggered festival day, the
  affected NPCs' daily planner ([npc.md](npc.md)) produces
  festival-specific schedule entries (a stall, a performance, a shared
  meal — see [cooking.md](cooking.md)) instead of their normal routine,
  same planning architecture, just a different day's inputs.
- **Real payoff for players**: special limited-time activities, and a
  settlement-wide relationship/[reputation](factions.md) boost for
  participating, giving festivals a mechanical reason to seek out and
  attend, not just flavor.

### Open questions

- Trigger thresholds — how "real" does the underlying event need to be
  (numeric threshold on crop yield, disaster severity, etc.) before a
  festival fires, and how do we keep that from feeling arbitrary/unclear
  to the player?
- Cross-settlement festivals (multiple villages coordinating) — interesting
  but probably a later-layer addition once single-settlement festivals
  work.
