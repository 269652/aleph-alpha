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

## Conflict and enforcement (mechanism spec)

Compiled from a design-brainstorm session — this section is exactly what
the Status list below used to flag as unbuilt ("a future criminal-
governance slice would extend this doc's 'None ← criminal_group' choice
above rather than replace it"), and it deliberately reuses real signals
already tracked rather than inventing a parallel crime/law layer:

- **Failed-state banditry.** `Institution.TYPES` already declares a
  `criminal_group` type that has NO formation trigger anywhere in the
  codebase today — listed, never chosen. A settlement whose real
  `SettlementState` reads DECLINING and whose real legitimacy (above) reads
  LOW gets one more real formation attempt: `criminal_group`, extending
  `Governance`'s existing form→attempted-institution mapping table exactly
  the way military-rule→`militia`/merchant-oligarchy→`merchant_company`
  already work. Once formed, [trade.md](trade.md)'s own real
  `CaravanRaid.raid_chance_for_tier` mechanism gets re-sourced from that
  specific settlement's own state rather than a bare `RegionDifficulty`
  tier lookup — raids trace back via `/why` to a named, starving village,
  not an anonymous danger-tier dice roll. Real grounding: resource-
  scarcity-driven banditry is a well-documented political-economy
  phenomenon — opportunistic raiding emerging once legitimate subsistence
  channels (farming, trade) stop covering a population's real needs, the
  actual mechanism behind real agrarian-famine banditry.
- **Whose militia catches you.** The already-real but currently passive
  `militia` institution type becomes a real enforcement actor: committing a
  flagged offense (theft, or being the player-attributed source of a
  caravan raid) inside a military-rule settlement's territory makes its
  militia hostile, extending [pvp.md](pvp.md)'s existing zone-based
  flagging model with a governance-form gate rather than replacing it — the
  exact same offense inside a settlement with no governance history yet, or
  a cooperative/merchant-oligarchy one, draws no militia response at all,
  purely because of which institution that settlement's own history
  happened to produce. Real grounding: Weber's monopoly-on-legitimate-
  violence framing — enforcement capacity is not a universal constant, it
  is a function of which coercive/legitimate institutions a polity actually
  has, independent of how much anyone might want the player punished.
  Deliberately does NOT invent a full crime/justice system — just a
  minimal offense event and a militia reaction rule, the same one-real-
  input-at-a-time discipline this doc's own pillars already insist on.

On the wider Phase 17 gate ("only after local society is stable"):
Governance, Institutions, Settlements, and RegionalTrade are now all real
and live-verified, so the foundation for a scoped conflict slice like the
one above is close — but this section deliberately stays scoped to exactly
these two real-signal-reuse mechanisms, not the full territory/war/treaty/
diplomacy scope Phase 17 eventually names. Two real, larger follow-ups are
visible from here but explicitly NOT built by this section: a settlement
that stops resupplying an ally once its own stock gets squeezed (real
trade-dependency-as-leverage, Hirschman's asymmetric-dependence framing),
and a raided settlement's own rumor network turning a specific attack into
a lasting inter-settlement grudge (a real scarcity → raid → distrust →
reduced cooperation → worse scarcity feedback loop) — both depend on
Failed-state banditry existing first as a real event to propagate or react
to, and are left for a later pass.

## Status

- ✅ Governance form and legitimacy are both real, derived classifications
  (`governance.gd`), inspectable via `/settlement`.
- ✅ Governance form changes a real decision: which institution type a
  settlement's own automatic formation attempts.
- ⬜ Failed-state banditry and militia enforcement (see "Conflict and
  enforcement" above) — design spec only, not yet implemented. Both reuse
  entirely real, already-tracked signals (`SettlementState`, `Governance`,
  the already-declared-but-untriggered `criminal_group` type,
  [trade.md](trade.md)'s `CaravanRaid`, [pvp.md](pvp.md)'s zone flagging).
- ⬜ Policies, taxation, and representation — real, separate mechanisms
  this doc's own governance-forms list implies, none built. Taxation
  specifically needs a real currency/wealth-flow system that doesn't exist
  yet (Phase 4/5's own documented gap).
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
