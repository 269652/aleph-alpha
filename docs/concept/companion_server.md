# Companion Server

A companion webserver the game itself launches locally — a second, browsable
surface onto the same save, for creature bookkeeping, settlement management,
and (once earned) giving NPCs a real voice. It is not a second game; it is a
window, and everything it can *do* (not just show) is deliberately narrow.

## Status

Tier 1 is built for three of its four originally-envisioned views (plus a
per-item detail page beyond the original sketch): Character Sheet, Item
Catalog (now searchable and paginated) with a linked-through Item Detail
page per id, and Companions (narrower than "Bestiary" — see below), each a
pure `RefCounted` renderer with its own GUT test file
(`src/companion_server/`, `tests/unit/test_companion_*.gd`), served over a
hand-rolled HTTP/1.1 GET-only transport (`companion_http_request.gd`, which
now also parses the query string for search/pagination/
`companion_http_response.gd`/`companion_router.gd`, which now also extracts
a path parameter for `/items/<id>`) by a `CompanionServer` autoload
(`src/companion_server/companion_server.gd`) bound to `127.0.0.1:8731`.
`tools/probe_companion_server.gd` keeps a bare process alive for manual
inspection — it does NOT instantiate `CompanionServer` itself; that
autoload is instantiated by Godot's own autoload system for any process
boot, this bare script included. Settlement Dashboard is deferred — see its
own bullet below for why. All of Tier 2 remains unbuilt, as originally
written.

Every Tier 1 route reads a freshly-loaded `PlayerSave.load_data()`
(`src/gameplay/player_save.gd`, the same `user://player_save.bin` convention
persistence.md already established) — the "Local transport" section below's
"reuse the save file directly" leaning is now the decided, shipped design,
not a lean.

## Design pillars

1. **Tier 1 needs zero LLM and zero network.** The base companion view — a
   character sheet, a bestiary, a settlement dashboard — works fully offline,
   for every player, from the start. This mirrors [dialogue.md](dialogue.md)'s
   own floor: a real, complete feature with no model anywhere in it. The
   richer, LLM-touching stuff is additive, never load-bearing.
2. **The server proposes, the core decides.** No write path from the
   companion server reaches a wallet, a contract, a wage, or a quest
   directly. Every write is a proposal validated and applied by the same
   pure core the rest of the sim already runs through — identical in shape
   to dialogue.md's beat contract, where a model returns one string and
   "there is no code path from a model's output to a wallet, a contract, or
   a store." This doc reuses that sentence as a hard constraint, not an
   inspiration.
3. **Richness is earned, not configured.** The interesting Tier 2 features
   (live voice, chronicle, live breeding predictions, remote instructions)
   unlock behind an actual in-world hire — a real wage, a real relationship
   gate, the exact rule [npc.md](npc.md) already specifies for hiring any
   NPC. Not a settings toggle sitting outside the fiction.
4. **One data source, reused.** Every read the server offers is the same
   state another system already computed and persists —
   [persistence.md](persistence.md)'s `Player` save dict, `VillageWages`,
   `village_market.gd`, `AnimalFitness`/DNA fields. No parallel stat is
   invented for the sake of having something to show on a page.
5. **Secrets never live in the shipped client.** Any OAuth/API-key exchange
   for an LLM provider happens entirely on the companion server's side of
   the process boundary, never embedded in or transmitted through the
   Godot binary — the same reasoning [licensing.md](../licensing.md)'s
   GitHub Device Flow already uses for why a distributed client shouldn't
   hold a secret at all.

## Real-world / genre grounding

Asynchronous companion surfaces are an established MMO/colony-sim pattern,
not a novelty for its own sake: WoW's Armory, EVE Online's remote skill
queue and neocom, and the fan-made IV/breeding calculators Pokémon players
build externally because the base game doesn't expose the math. This system
is the native version of that last one — a tool players already reach for
outside the game, built with real data instead of reverse-engineered
guesses, plus the asynchronous "check in between sessions" loop the other
two examples prove players want.

## Mechanism

### Tier 1 — always on, no gate

Launches alongside the game (or via a menu toggle), bound to localhost only,
read-only:

- ✅ **Character sheet** — mirrors most of `Player.to_save_dict()`
  (class, health, wallet, XP/level, equipment, skill allocations, hotbar),
  not literally every save key: position, `dna_seed`, and the raw
  `skill_points_paid` ledger have no legible place on a sheet and are left
  for a future pass if ever wanted. Equipment/hotbar show real
  `ItemCatalog` display names, never a raw item id.
  `companion_character_sheet_view.gd`.
  - **A real portrait (2026-09-05)**, embedded as a base64
    `data:image/png;base64,...` `<img>` src rather than a second route --
    Tier 1 serves exactly one response per page, so a data URI needs no
    new dispatch case at all. `CharacterSheetPortraitScene`
    (`src/rendering/character_sheet_portrait_scene.gd`) composites the
    hero (`ProceduralCharacterSprite.generate_hero_portrait_image`, the
    SAME pure figure-only function the character creator's static portrait
    toggle already uses) onto a small sky/ground vignette with a couple of
    fixed grass-tuft/pebble accents -- a pure `Image` compositor, no Godot
    `Node` of any kind, so it stays inside this tier's own "reads only the
    save file" boundary below. Deliberately **not** a snapshot of the live
    `CharacterPreviewDiorama` scene (the character creator's actually-
    animated swaying-grass/pond/ambient-creatures preview, built for a
    `SubViewport`) -- that would mean instantiating live rendering nodes on
    every Character Sheet page load, which is exactly the "no live Player/
    scene-tree hook" boundary this tier exists to keep. The saved
    `appearance` dict is used when present; a save from before it was
    persisted (or any hand-built fixture missing it) instead gets one
    freshly derived from the same `(character_class, dna_seed)`
    `HeroAppearance.appearance_for` would have rolled originally, so the
    portrait is never blank/broken. Shows the hero's DNA-driven look only,
    same as the creator's own portrait -- not equipped armor/weapons (no
    existing function composites those onto a portable `Image` outside a
    live `CharacterView`; a real, separate follow-up if ever wanted).
- ✅ **Item Catalog** (`/items`) — every authored item
  (`ItemCatalog.known_ids()`), *not* filtered down to only what the save
  holds. Each row is annotated "have" when the save's
  inventory/equipment/hotbar currently references that id; a save's own
  crafted (content-addressed) items are looked up and shown alongside.
  Deliberately ungated: no discovery/spoiler tracking exists for items
  anywhere in this codebase ([item_identity.md](item_identity.md) is about
  content-addressing crafted items, not visibility), so showing the full
  authored reference, annotated, is the option that invents no new
  persisted state — pillar 4 applied literally, rather than building a
  "seen items" set nothing else needs. Searchable by name/id
  (case-insensitive) and paginated (`ITEMS_PER_PAGE := 20`, a pinned
  constant) — search narrows the list, it never replaces the full
  reference. `companion_item_catalog_view.gd`,
  `companion_pagination.gd`, `companion_html.gd`.
- ✅ **Item detail** (`/items/<id>`, a "PDP") — every catalog row's name
  links here. What the item is (a description synthesized from real
  fields — kind, mass, and `MaterialProperties.descriptors_for()` where a
  material is modeled — never a new lore-text field), how it's itself
  crafted (`CraftingRecipeBook.recipe_for_output()` + `recipe_inputs()`,
  each ingredient linked to its own detail page), and every recipe that
  uses it as an ingredient (scanned across the whole book — no reverse
  lookup exists in `crafting_recipe_book.gd` itself, deliberately not
  added there since it's a fixed data table, not a query engine).
  Crafted-from/Used-in only ever consult `CraftingRecipeBook`, which knows
  nothing about a save's own `asm_`-prefixed crafted items — rendering a
  crafted item's real part/joint assembly graph
  (`CraftedItemRegistry.get_assembly`) is a real, larger follow-up, not a
  same-shape addition. Does not show "have" status this pass (every other
  view foregrounds ownership; this one is a reference page) — a deliberate
  scope choice, not an oversight. `companion_item_detail_view.gd`.
- ✅ **Companions** (`/companions`), *not* "Bestiary" — deliberately renamed
  on implementation. A whole-repo search found no persisted
  creature-encounter log anywhere, built or spec'd (`docs/concept/pets.md`,
  `taming.md`, `dna.md`, `evolution.md` included) — `AnimalFitness`'s
  strength/agility/coat_vibrancy numbers are derived live from a seed with
  nothing about *which* creatures a player has met ever stored. What IS
  real and persisted is `Player.to_save_dict()`'s `bonded_companions`: a
  plain `[{"species": String}, ...]` list, nothing richer. This view shows
  exactly that and no more, honestly scoped rather than reusing the
  "Bestiary" name for something thinner than it implies.
  `companion_companions_view.gd`.
  - Two real, larger follow-ups this is NOT: (1) `KeptAnimals`
    (`src/world/kept_animals.gd`) DOES persist trust/order/`wander_seed`
    (→ live-rederivable fitness) for tied/tamed animals, but **per chunk**
    (`_kept_animals_path(chunk_coord)`) — showing those means scanning
    every chunk's save file on disk, real additional plumbing, not a
    same-file read like the three shipped views. (2) A full
    every-creature-ever-seen bestiary has no data source at all and would
    mean designing and building a new persisted tracking mechanism first —
    a concept-doc-sized decision of its own, not a view-sized addition.
- ⬜ **Settlement dashboard** — deferred, not built. `VillageWages`
  (`src/world/village_wages.gd`) turned out to be a stateless static
  module; the real live numbers (a settlement's gold purse) are `Object`
  metadata on a `VillageMarket` instance that `VillageRenderer.spawn_village`
  recreates empty on every chunk load — **never persisted**
  (`src/world/npc_economy.gd`'s own doc comment). A second, unrelated,
  *persisted* economy system already exists
  (`src/emergence/market_store.gd` + `market_store_persistence.gd`,
  `user://emergence_markets.bin`) but it's a separate subsystem (the
  `docs/emergence/*` simulation layer) with no confirmed link to what a
  player sees day-to-day. Picking between "read the live, unpersisted
  village state" and "read the persisted-but-different emergence state" is
  its own design decision — pillar 4 ("one data source, reused") can't be
  honored until that decision is made, so this view waits rather than
  guessing. See Open questions.

No outbound network call exists at this tier. Closing the browser tab loses
nothing — every value here is derived, not authored on the page.

### Tier 2 — the Hall and the Scrivener

A buildable structure (see [building.md](building.md)'s blueprint catalog;
working name "Registry Hall," see Open questions) that, once placed and
staffed, turns on the rest.

**A new occupation.** `NpcIdentity.OCCUPATIONS` currently holds `farmer,
blacksmith, merchant, guard, fisher, herbalist, hunter, nurse`
(`src/world/npc_identity.gd`). This adds a ninth: `scrivener` — a
non-producer, same as blacksmith/guard/nurse, eating by buying rather than
gathering (see npc.md's occupation economy section).

**Hiring follows the existing rule exactly**, not a special case: an
ongoing wage out of [economy.md](economy.md)'s gold, gated by relationship —
"a stranger won't work for you at any price" (npc.md's Hiring & instruction
section). What differs is what the wage buys: a cheap/local model is an
always-affordable, barely-literate apprentice; a strong hosted model is a
renowned wordsmith who costs a real recurring wage — and, per the same
relationship gate, may simply decline to work for a low-trust employer
regardless of price. The OAuth/API-key handshake for whichever backend is
chosen happens entirely server-side (pillar 5).

**What hiring one unlocks:**

- **Voice.** Plugs into dialogue.md's already-specified, deliberately narrow
  AI seam: the scribe restyles one `template` string in the villager's
  voice. It does not choose what is said, whether a quest is offered, or
  what it pays — that boundary is unchanged, just given an in-fiction face.
- **Chronicle.** Browsable settlement/NPC history, generated from the real
  append-only `EventStore` plus each NPC's own memory/rumor confidence (see
  npc.md's Memory, beliefs, and rumor propagation section). "The scribe
  wrote it down" doubles as the in-fiction reason an unwitnessed or old
  event reads fainter — reuses the existing decay mechanic rather than
  inventing a second one for display purposes.
- **Live breeding planner.** The bestiary's crossing predictor (mirroring
  `dna_crossover.gd`'s real math) only activates for creatures actually
  walked past the Hall. Registration is a real action with a real in-world
  footprint, not passive omniscience — matches taming.md's "nothing is
  hidden, but nothing is free."
- **Instruction queue.** Remote queuing through npc.md's still-unbuilt
  hiring/instruction DSL — the Scrivener is the one relaying written orders
  to the workforce while the player is away, which is also why this
  specific feature can't exist before that DSL does (see Open questions).

### The boundary, stated once more explicitly

Every Tier 2 write — a queued instruction, a registered creature, a hire —
is a *proposal*. It is validated and applied by the same pure-core module
the rest of the sim already uses for that kind of state change; the
companion server holds no authority to mutate a wallet, a relationship, or
a quest on its own. An LLM's only possible output anywhere in this system is
a rephrased string for Voice — never a decision.

### Local transport

**Decided and shipped, for Tier 1.** Every route reads
`PlayerSave.new().load_data()` fresh per request — persistence.md's existing
`user://player_save.bin` `FileAccess.store_var`/`get_var` convention, reused
directly rather than a second one invented for this server ("one
convention, reused," persistence.md's own pillar 4). There is no live
`Player`/scene-tree hook anywhere in `companion_server.gd`: a request only
ever sees what's actually been saved, the same staleness a manual reload
would show, and the server needs no wiring into `scenes/world.gd` at all.

HTTP itself is hand-rolled: Godot has no built-in HTTP server class (only
`HTTPClient`/`HTTPRequest` for the client side), so `companion_server.gd`
owns a raw `TCPServer` bound to `127.0.0.1:8731`
(`CompanionRouter.PORT`, a test-pinned constant), parses just the request
line (method + path; no route reads a header), and always responds with
`Connection: close` — one request, one response, no keep-alive. Registered
as an autoload, not a node `scenes/world.gd` instances, because
`world.gd`'s `_ready()` re-runs on every scene reload (New Game, a license
retry) and an instanced node would rebind its socket each time; an autoload
survives that. A failed bind (port already taken by another running
instance) is caught, logged, and never takes the game down — the companion
server is optional by construction.

Tier 2 writes (unbuilt): a minimal local endpoint the running Godot process
exposes for proposals only, validated by the same core the rest of the sim
calls.

## Non-goals (for now)

Mirrors [overview.md](overview.md)'s own Non-goals section:

- No multiplayer or shared companion server. Single local player, single
  local save — matches the confirmed single-player MVP scope.
- No LLM output ever reaches game state directly, at any tier, ever.
- Tier 1 requires no network access under any circumstance. Only Tier 2's
  Voice feature makes an outbound call, and only once a Scrivener is
  actually hired.

## Open questions

- **Naming.** "Registry Hall" / "Scrivener" are working names chosen for
  clarity while writing this doc, not a final creative decision — see
  follow-up brainstorm.
- Where the Hall sits in building.md's blueprint catalog, and what gates
  building it (always available at some civic tier? a quest?).
- The wage curve mapping backend "quality" to gold cost needs to be a
  tested/pinned constant once it exists, per CLAUDE.md's no-eyeballed-tuning
  rule — not specified here.
- This doc assumes npc.md's instruction DSL and hiring/relationship systems
  exist; today they don't (see npc.md's own divergence note). The
  Instruction queue feature specifically has no floor to stand on until the
  DSL is real — everything else in Tier 2 doesn't share that dependency.
- Exact LLM backend/provider list is deliberately left open, matching
  overview.md's own unresolved "hosted API vs. local model" question — this
  doc answers *where* that choice is made (companion server, per-hire), not
  *which* backends are supported.
- Should Tier 1 have any gate at all, or is a totally-ungated dashboard the
  right default even before a player has built anything? (Answered *for the
  three shipped views* by implementation: totally ungated, no gate exists.)
- **Settlement dashboard needs a real pick between two economy systems**
  before it can be built at all: the live-only `VillageMarket`/
  `NpcEconomy` purse (matches what a player actually sees in a loaded
  village, but is never persisted, so a companion server reading only the
  save file cannot show it) versus the persisted `src/emergence/
  market_store.gd` system (already saved, but a separate subsystem with no
  confirmed link to the village a player is standing in). Whichever is
  chosen, showing it likely means this view is the first Tier 1 exception
  to "reads only `PlayerSave.load_data()`" — worth deciding deliberately,
  not by default.
- **A full "every creature encountered" bestiary** and **richer
  `KeptAnimals`-backed companion stats** (trust, per-chunk tied-animal
  locations, live fitness numbers) are real, wanted follow-ups with no
  tracking mechanism (bestiary) or same-file read (KeptAnimals is
  per-chunk) to build them from yet — see the Companions bullet above.
