# Dialogue — talking to a villager

How a conversation with an NPC works. This is the real system
[npc.md](npc.md)'s "Minimal talk interaction" section named itself a
placeholder for: `npc_greeting.gd`'s single deterministic line, with no memory,
no branching and no quest hook, was always a stand-in.

It is deliberately **an entirely offline system**. There is no LLM anywhere in
this document's mechanism, and the game is complete without one. See
[The AI seam](#the-ai-seam-deliberately-not-built) for the one narrow place a
model could later be added, and why that place is narrow on purpose.

## Design pillars

1. **A conversation is a read of the simulation.** Every sentence a villager
   says is grounded in a fact some other system already computed — their real
   wallet, their household's real shortfall, a real memory at its real
   confidence, the real weather. Nothing is authored fiction layered on top.
   Same relationship [quests.md](quests.md) already has to need state.
2. **Empty facts mean no topic.** A topic is *omitted* when the facts behind it
   are empty, rather than falling back to filler. This is what keeps the system
   from being a mad-libs mill, and it doubles as an instrument: a topic that is
   always empty is a *substrate* bug, surfaced before a line of prose is
   written.
3. **The player is a node in the graph, not a camera.** Talking is a real act
   that writes real state — an event other villagers witness, a memory that
   transmits, a ledger entry that changes what you are told next time.
4. **Salience is measured, never authored.** How much a villager wants to talk
   about something is a real number already in the simulation (hunger,
   `1.0 - yield_signal`, `confidence × (1 - distortion)`), not a hand-tuned
   weight — satisfying [CLAUDE.md](../../CLAUDE.md)'s no-eyeballed-tuning rule
   by construction.
5. **Pure core, thin glue.** Every decision lives in `RefCounted` modules under
   `src/dialogue/` that take Dictionaries and return Dictionaries. The window is
   glue that renders what they decide.

## Substrate first

The conversation engine is only as good as the facts underneath it, and a
survey found those facts largely absent. Before any dialogue code, five gaps
were closed (see [progress.md](../progress.md) for what landed):

| Gap | Why it made conversation impossible |
|---|---|
| Of 18 `Event.new` sites, only 2 called `MemoryStore.witness_event` | `Event.witnesses` and the whole belief/rumor layer existed and were **unused**. Every villager's memory bank held identical founding trivia — nothing to know, nothing to gossip, nothing to disagree about. |
| `production_failed` fired every step, not on change | ~1.25 identical records per settlement per 30s. Within ten minutes every villager's only news is "production failed". |
| Hunger was an occupation constant | 5 of 8 occupations have no gold source, so non-producers were permanently broke and therefore permanently hungry. A permanent state is not news. |
| Every settlement classified `DECLINING` | Two unrelated things are called "the market"; capacity read the persisted emergence `Market`, which is never stocked. A village that is always declining can never be *made* to grow. |
| 2 of 8 occupations had a recipe | Three quarters of villagers could never have a shortfall, so could never ask for anything. |

## The pipeline

Six pure modules. Each takes plain Dictionaries and is unit-tested with no
engine dependency.

```
world state ─▶ DialogueContext.build ─▶ frame (one flat ~35-field Dictionary)
                                          │
              NpcVoice.register_for ──────┤
                    (8 genes → voice_key) │
                                          ▼
                          DialogueTopic.available_for ─▶ scored topics
                                          │
              NpcSeenLedger.decay ────────┤
                                          ▼
                            DialogueMove.select ─▶ Move
                                          ▼
                            DialogueBeat.build ─▶ Beat
                                          ▼
                        OfflineRenderer.render ─▶ the sentence
```

**`DialogueContext`** is the one place that reads the world. It produces a flat,
hashable *frame* — no object references — shaped after `FieldJournal.entry_for`.
It reads memories from all three banks (`npc:`, `household:`, `settlement:`),
sorted by `recorded_at` **descending** (`.back()` is first-formed order, not
latest), and uses the **world** clock, never `NpcMarker`'s private per-marker
one.

**`NpcVoice`** taps a signal the game already generates and throws away:
`identity.genome.traits` is a full 8-entry continuous map, of which only the
argmax is currently read. Five axes (`warmth`, `bluntness`, `verbosity`,
`hedging`, `self_interest`) are computed from the real genes and **banded by
quantile, not by a threshold**. This matters arithmetically: with 8 independent
uniforms, `P(max ≥ 0.85) = 1 − 0.85⁸ = 72.8%`, so an eyeballed "strong" cut puts
three villagers in four into one band, and a linear combination of 8 uniforms
concentrates at its mean. The band edges are therefore *measured against the
real generator* and pinned by a 5000-seed distribution test.

**`DialogueTopic`** holds ~16 topics, each a pure `is_available(frame)` /
`salience(frame)` pair, subject to pillar 2.

**`DialogueMove`** picks top-k by `salience × NpcSeenLedger.decay(...)`, with a
deterministic tie-break. The ledger is keyed `npc:<seed>` so it survives chunk
unload — every `NpcMarker` is freed — and save/load.

**`OfflineRenderer`** is a five-slot sentence plan (OPENER, CORE, HEDGE, ASIDE,
CLOSER) with pools indexed by voice band. High `bluntness` with low `verbosity`
drops three of five slots and you get four words. The HEDGE is chosen from the
memory's **actual** `source_type` and `confidence`: firsthand → "I saw it
myself"; `stranger_testimony` at 0.36 → "Someone at the well said —"; `rumor` →
"There's talk. I'd not swear to it."

**This is where `rumor.gd`'s distortion is finally applied** — in the renderer,
leaving `EventStore`'s ground truth uncorrupted, exactly the fact-versus-belief
split [docs/emergence/02](../emergence/02-history-memory-rumors.md) specifies.

Choice labels are built from the beat's **own slots** — "Ask about the three
rock", "Ask what Doran said" — never from a fixed global menu.

## Why it stays interesting past the tenth conversation

Six mechanisms, each observable in play:

1. **The facts move.** After the substrate fixes, hunger, wallet, village stock,
   yield, season, weather, settlement status and tier all change over a session.
2. **The ledger burns topics.** Talk twice and you get the *second* most salient
   thing, with an opener that acknowledges the first — and the stack has
   re-sorted underneath you because of (1).
3. **You are in the graph.** One event per conversation makes `player:local` a
   real actor; recognition goes `stranger → knows you → owed → trusted →
   disappointed`, read from the append-only `EventStore` (not `MemoryStore`,
   which the 30s gossip step can talk a villager out of).
4. **You are the fastest rumor vector in the world.** When a villager tells you
   news you *hold* that memory at degraded confidence; carry it two settlements
   over and it enters a gossip network that already runs every 30 seconds.
   Because you walk between settlements and villagers do not, you are
   structurally the highest-bandwidth edge in the graph. No template fakes this
   and no LLM is needed for it.
5. **Villagers disagree, and you can see it.** The `contradiction` topic is
   available when this villager and a co-present neighbour hold the *same*
   `event_id` at source types two or more steps apart. Pure function over two
   memory lists, zero new state.
6. **Your errands change what everyone says.** Fill a shortfall → the market
   gets real stock → status flips → a real event, witnessed by five villagers →
   gossiped at the well → the `village` topic changes for everyone there, and a
   stranger two settlements away eventually greets you as someone they have
   heard of.

**Pinned, not asserted.** `test_village_content_floor.gd` walks a real village's
villagers through every available topic across three simulated days and fails if
distinct *fact-bearing* sentences per villager fall below a floor, or if two
villagers share more than a ceiling of them. Surface-form combinatorics are
explicitly not the metric.

## Emergent quests, no LLM

A quest stays a **projection** — [quests.md](quests.md)'s own falsifiable claim
is the law: delete the query and the village is still starving. Nothing is
persisted but the *acceptance*, and that is a `Contract`, which already exists.

`QuestOffer` merges six grounded sources into one shape with a **derived**
`offer_id` (`"<kind>:<item>:<count>"`), so the same real shortage always yields
the same id and offers dedupe across recomputation:

1. **Production shortfall, attributed to a face.** The existing shortfall query
   returns `{household_id, recipe_id, missing}`; because a household id is built
   from its founder, `EntityRef.key_of(household_id)` *is* the villager's seed.
   One line turns an anonymous `household:483920 needs 3 rock` into Bren asking
   you for three rock.
2. **Village hunger** — the live market cannot buy a meal and this villager is
   hungry. Now a real transient state rather than an occupation constant.
3. **Remembered threat** — a memory of a raid or a ruin above a confidence
   floor. `CaravanRaid` already drops real goods at a real position, so "someone
   should go and look" has a completable objective.
4. **Deeper need** — `NeedResolver`'s recursive walk over the real recipe graph.
   This is the "why can't you make it yourself" branch: "It's the forge — there
   isn't one this side of the river."
5. **Carried news** — a memory the *player* holds that this villager does not.
6. **Hardship** — real snow depth above a floor plus a non-producer occupation.

**Rewards are derived, and re-derived.** `Contract.obligations` is
`Array[String]`, `consideration` is a `String`, and nothing in the codebase
interprets either; there is no deadline sweep. So `QuestReward` computes the
reward from real state (the asking household's actual wallet, capped at what
they hold), and **re-derives it at fulfilment from live state** — a villager who
went broke pays less and says so. Deadlines are checked **lazily at conversation
open**, not in a background sweep, because the only observer that matters is the
conversation itself; a lapse records a broken promise that other villagers
witness.

**Tracking is the world, not a log.** The existing floating prompt becomes
`Talk (G) · owed 3 rock`, fed from the throttle that already exists.

## The beat contract

The pipeline's output is one Dictionary. It exists as an explicit contract for
two reasons: it is what the renderer consumes, and it is the *only* surface a
future AI layer would ever touch.

```gdscript
Beat := {
  "kind":             String,   # greet | answer | ask | ask_detail | deflect | farewell
  "topic_id":         String,
  "voice_key":        String,   # "bluntness_high"
  "fact_band":        String,   # "yield:barren|market:empty|status:declining"
  "speaker":          { name, occupation, recognition, allowed_names },
  "facts":            Array,    # [{key, value, unit}]
  "slots":            { item, count, place, name },
  "required_slots":   Array,
  "required_lexemes": Array,
  "template":         String,   # pre-substitution
  "offline_text":     String,   # ALREADY substituted — the guaranteed floor
}
```

Note `template` versus `offline_text`: quantities and names live in `slots` and
are substituted by the core, never written into a sentence by whatever produced
it. That separation is what makes the next section safe.

## The AI seam, deliberately not built

[npc.md](npc.md) has always wanted LLM-authored NPCs, and its own thesis is that
this happens **statically**, not at runtime. Nothing in this document needs a
model, and none of it is built as though one is coming. But the beat contract
leaves exactly one seam open, and its narrowness is the design:

- A model would receive a beat and return **one string** — a rephrasing of
  `template`, in that villager's voice, with every quantity and name left as its
  placeholder. It would not be asked what to say, who to say it about, whether
  to offer a quest, what the quest wants, or what it pays. All of that has
  already been decided by the pure pipeline.
- The returned string is validated, then **slot-substituted by the core**. There
  is no code path from a model's output to a wallet, a contract, or a store.
- Because the natural cache key is `(voice_key, topic_id, kind, fact_band)` and
  **not** the NPC, a phrasing baked ahead of time and one fetched live are the
  same artifact — so the static-generation thesis and a live call are the same
  mechanism, not two.

This is the whole of what enabling AI could ever buy: **different wording, never
different game state.** Written down here so that if it is built later, "works
without it" is a property of the architecture rather than a promise someone has
to keep.

## Status

- ⬜ Everything below is being built now; this doc is the spec, written first.
- ⬜ Substrate: witness wiring, `production_failed` change-guard, `VillageWages`,
  `SettlementFood`, 8-occupation recipe map.
- ⬜ `NpcVoice`, `DialogueContext`, `DialogueTopic`, `DialogueMove`,
  `NpcSeenLedger`, `DialogueBeat`, `OfflineRenderer`.
- ⬜ `ConversationWindow` + typewriter; opens on the existing talk key.
- ⬜ `NpcRecognition`, player-conversation events, the rumor-vector loop.
- ⬜ `QuestOffer`, `QuestReward`, `NpcAsk`, contract propose/accept/fulfil/lapse.
- ⬜ **Not planned in this pass:** any LLM provider, settings tab, network code
  or baked phrasing pack. The seam above is documented, not implemented.
