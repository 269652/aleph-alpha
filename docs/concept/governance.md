# Governance

A settlement's own institutions eventually decide *how it is run*, not just
*what it does*. `docs/concept/npc.md`'s households and
`docs/emergence/01-society-and-institutions.md`'s institutions cover the
economic/social units this doc doesn't repeat; this doc is specifically
about the layer above them — who a settlement's real accumulated
institutional history says is actually in charge, and how legitimate its
population currently finds that arrangement — per
`docs/emergence/01-society-and-institutions.md`'s own "Governance"/
"Legitimacy" sections and `docs/emergence/07-implementation-roadmap.md`'s
Phase 13: "Implement governance models, legitimacy, policies, political
groups, representation, taxation, and enforcement. Governance changes
actual decisions and resource flows."

## Design pillars

1. **Governance is read off real history, never assigned.** A settlement's
   governance form is not chosen or authored — it is *inferred* from which
   kind of institution its households have actually formed and re-formed
   over time, the same "derived from flows, not a stored tag" discipline
   `docs/concept/npc.md`'s specialization inference already established for
   settlement tiers (`SettlementTier.specialization_for`).
2. **Legitimacy is grounded in the ONE real input this project already
   tracks.** `docs/emergence/01` lists eight legitimacy inputs (protection,
   food security, justice, tradition, wealth distribution, religious
   authority, military success, popular trust) — only food security has
   real, already-live data behind it (`SettlementState`, Phase 7's own
   GROWING/STABLE/DECLINING status). The other seven wait on systems that
   don't exist yet (a real justice/crime system, a real wealth/currency
   flow, a real trust/reputation graph), the same one-real-input-at-a-time
   discipline `SettlementState.food_stock` itself already used for carrying
   capacity.
3. **Governance must change something real, not just be a label.**
   `docs/emergence/07`'s own exit language: "Governance changes actual
   decisions and resource flows." A governance form that only renders in a
   console command isn't governance yet by this project's own standard —
   it has to feed back into a real decision the simulation already makes.

## Governance forms

Of `docs/emergence/01`'s own named forms (council, hereditary leadership,
merchant oligarchy, clan leadership, priesthood, military rule,
cooperative administration, representative governance), only the ones with
a real, already-tracked institution TYPE behind them
(`Institution.TYPES` — Emergence Phase 6) are grounded:

- **Military rule** ← `militia`
- **Merchant oligarchy** ← `merchant_company` and `guild` (a craft guild's
  real-world overlap with oligarchic economic power is closer than any
  other listed form)
- **Cooperative administration** ← `cooperative`
- **None** ← no institution yet, or a settlement whose only institution is
  a `criminal_group` — a purely criminal presence has *coercive* power, not
  *legitimate* authority (`docs/emergence/01`'s own invariant: "No
  authority without legitimacy or coercion"), and this first slice does not
  yet model coercion-based rule separately from legitimate governance.

A settlement's form is whichever institution TYPE it has formed most
across its real history (active or dissolved — a settlement's political
character persists through a specific institution's failure, the same
"history is kept" shape `InstitutionStore` already uses for individual
institutions). Council, hereditary leadership, clan leadership, priesthood,
and representative governance have no real institutional signal to derive
them from yet and are left unmapped rather than guessed at.

## Legitimacy

Three levels — high, stable, low — derived directly from
`SettlementState`'s own real status: a growing settlement (real food
headroom) reads as high legitimacy, a declining one (real food pressure) as
low, everything else as stable. The same dead-band/hysteresis reasoning
`SettlementState.status_for` already applies to growth/decline classifies
legitimacy too, since it's the exact same underlying signal viewed through
a different lens.

## What governance actually changes

Per this doc's own third design pillar: a settlement's governance form
feeds back into which institution TYPE a NEW automatic formation attempts
(`EarthChunkManager._step_settlement_trade`'s own automatic institution
check, Emergence Phase 4/6). A settlement with no governance history yet
defaults to attempting a `cooperative` (unchanged from before this phase);
one with a military-rule history attempts a `militia`; one with a
merchant-oligarchy history attempts a `merchant_company` — real political
inertia, not just a label. Taxation, enforcement, policy, and
representation are all real, separate mechanisms this doc's own exit
criterion names but none of them are built — see Status.

## Status

- ✅ Governance form and legitimacy are both real, derived classifications
  (`governance.gd`), inspectable via `/settlement`.
- ✅ Governance form changes a real decision: which institution type a
  settlement's own automatic formation attempts.
- ⬜ Policies, taxation, enforcement, and representation — all real,
  separate mechanisms this doc's own governance-forms list implies, none
  built. Taxation specifically needs a real currency/wealth-flow system
  that doesn't exist yet (Phase 4/5's own documented gap).
- ⬜ Legitimacy's other seven real-world inputs (protection, justice,
  tradition, wealth distribution, religious authority, military success,
  popular trust) — all wait on systems (crime, currency, trust/reputation,
  combat outcomes) that don't exist yet.
- ⬜ Council, hereditary leadership, clan leadership, priesthood, and
  representative governance — no real institutional signal grounds them
  yet.
- ⬜ Crime and religion (`docs/emergence/01`'s own adjacent "Crime"/
  "Religion" sections) are unbuilt and unrelated to this first slice,
  though a future criminal-governance slice would extend this doc's
  "None ← criminal_group" choice above rather than replace it.

## Open questions

- Once policies/enforcement exist, does low legitimacy actively degrade
  them (the doc's own "protests, defections, tax resistance, rival
  leaders, migration, coups, and civil conflict"), or is legitimacy
  read-only until then?
- Should governance form influence dissolution too (Emergence Phase 6's
  `InstitutionFormation.should_dissolve`), the way it now influences
  formation — a low-legitimacy settlement's institutions failing faster?
  Deliberately not built this pass to keep the dissolution mechanism's
  own recent fix (Emergence Phase 6 gap-closing) isolated from a second
  change in the same session.
