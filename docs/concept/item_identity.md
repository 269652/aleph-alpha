# Item Identity

This doc specifies **what names an item** once items stop being entries in an
authored table and start being assembled by the player. It is the foundation
the emergent-crafting programme stands on: an item is a small typed graph of
parts joined by typed joints, and before any of that can exist, the game has to
be able to say *which* item a given assembly is — the same way, in every
session, on every machine.

The answer is one sentence: **an item's id IS a content hash of its canonical
structure.**

## The real bug this fixes

This is not a hypothetical. Two defects were verified against the shipped
source before a line of this was written, and together they blocked the whole
programme.

**1. The loader silently drops any id it does not recognise.**
`scenes/player.gd`'s `apply_save_dict` loaded the inventory with

```gdscript
for entry in data.get("inventory", []):
    if _item_catalog.has(entry.id):
        inventory.add(_item_catalog.make(entry.id), entry.count)
```

and equipment a few lines below with a matching `continue` on
`if not _item_catalog.has(item_id)`. `ItemCatalog.has` was
`return _ITEMS.has(item_id)` — a static, hand-authored table. So **every
emergent item would evaporate the first time the game was saved and reloaded**,
with no error, no log line, and no missing-item message. The player would
simply find their crafted sword gone.

**2. Stacking compares ids and nothing else.**
`src/gameplay/item_stack.gd`'s `can_stack_with` is `return item.id ==
other.item.id`. If two structurally different items could ever share an id,
they would merge into one stack and one of them would be silently lost.

## Design pillars

1. **The id is the structure, not a label for it.** Anything else needs a
   counter, and a counter needs an authority to hand out numbers. Content
   addressing has no authority: two players who build the same sword derive the
   same id independently, so a traded item needs no id negotiation and a save
   file means the same thing in every session.
2. **A false SPLIT is the failure that matters.** One real object getting two
   ids breaks stacking, trading, and the save round-trip simultaneously. A
   player who attaches the pommel before the grip has built the *same sword*, so
   the id must be an invariant of the part/joint graph, not a function of the
   order things were listed in.
3. **Bounded id space.** Continuous state is quantized. Without that, honing a
   blade would mint a fresh item per whetstone stroke and the id space would be
   unbounded.
4. **Degrade visibly, never silently.** Where the canonicaliser cannot give a
   full certificate it says so in the form itself rather than pretending.
5. **No refactor of what already works.** Inventory, ItemStack, Equipment and
   the save dict are untouched. Content addressing makes `can_stack_with`'s
   id-only comparison *correct* rather than a latent bug, so bug 2 is fixed by
   construction rather than by editing it.

## Mechanism: `assembly_id.gd`

An assembly is a plain Dictionary — deliberately **not** the Part/Joint/
PartGraph classes, so the two can land independently and compose later.
Everything is optional and unrecognised fields are carried into the id rather
than dropped, which is what makes the shape forward-compatible.

```
{
  "pattern": "sword",
  "parts": [
    {"material": "iron", "geometry": "blade", "role": "edge",
     "length_cm": 70.0, "volume_cm3": 120.0,
     "treatment": {"sharpening": 0.75}},
    ...
  ],
  "joints": [{"kind": "tang", "a": 0, "b": 1}],
}
```

A joint's `a` -> `b` is directional (a tang runs from the blade into the grip,
not the other way round). Any float under a key ending `_cm` is real
centimetres and `_cm3` real cubic centimetres; every other float is a 0..1
process level. A joint endpoint that does not index a real part is kept
verbatim in a `dangling_joints` list rather than crashing — a save file must
never be able to take the game down.

`canonical_form(assembly)` is three stages, not a sort:

1. **Quantize.** Every float becomes an integer quantum count, so the canonical
   form contains no floats at all and cannot vary with float formatting.
2. **Colour refinement (1-WL).** A part's colour starts as its own content and
   is repeatedly replaced by a hash of itself plus the sorted multiset of
   (joint, direction, neighbour colour) around it. This separates parts a plain
   content sort ties: two identical iron heads, one on the grip and one on the
   pommel, get different colours because their neighbourhoods differ.
3. **Exhaustive tie-breaking** inside whatever orbits survive refinement. Parts
   sharing a refined colour *and* identical content are genuinely
   interchangeable, so every ordering of them is enumerated and the
   lexicographically smallest serialization wins. The orbits are themselves
   order-independent, so the *set* of candidate orderings is the same for any
   listing of the same object, and therefore so is the minimum.

`assembly_id(assembly)` is `"asm_"` plus 64 hash bits of that form, as hex. The
prefix is a namespace, so a loader can tell a content-addressed id from a
hand-authored one (`iron_sword`) at a glance.

### The limit, stated honestly

Stage 3 is capped at `MAX_ORBIT_PERMUTATIONS` (720 = 6!) candidate orderings.
Past that cap — which needs seven or more mutually interchangeable parts in a
vertex-transitive arrangement, e.g. a closed ring of seven identical links — the
form degrades to the stage-2 refinement invariant and records that in its
`exact` field. The fallback is still fully deterministic and still
order-independent, so it never splits one object into two ids (pillar 2). But
it is an *invariant*, not a certificate: 1-WL cannot distinguish some
pathologically regular graphs, so two genuinely different such assemblies could
in principle collide. No real item is that graph, and the flag makes the
degradation visible instead of silent.

### Why not `hash()`

`hash()` is deliberately avoided in favour of FNV-1a run twice (different
offset basis, different odd multiplier, opposite byte order — 64 bits total).
Two reasons, both load-bearing:

- `hash()` correlates badly across near-identical inputs and this project has
  been bitten by exactly that twice, documented in `src/rendering/pixel_noise.gd`'s
  own doc comment. The inputs here **are** near-identical by construction: two
  swords differing by one millimetre of blade.
- An id lives in a save file forever. `hash()` is an engine implementation
  detail with no cross-version guarantee; FNV-1a is a published byte-exact
  specification, so a save written today still reads after a Godot upgrade.

### Tuned values and their grounding

Every quantum is a real-world measurement, pinned by a test that asserts *why*
it has that value — never an eyeballed constant.

| Value | Grounding | Pinned by |
|---|---|---|
| `DIMENSION_QUANTUM_CM = 0.1` | A smith works, and a hand perceives, to the millimetre. Sub-millimetre variation is not a different sword. | `test_the_dimension_quantum_is_one_real_millimetre`, `test_sub_millimetre_length_differences_do_not_mint_a_new_id` |
| `TREATMENT_LEVELS = 8` | A real waterstone progression is #220 / #400 / #1000 / #3000 / #6000 / #8000 — six stones — plus "blunt" below and "stropped on leather" above: eight steps from dull to razor. Honing a blade therefore mints nine ids across its whole life, not one per stroke. | `test_the_treatment_ladder_has_one_step_per_real_whetstone_stage`, `test_sharpening_across_its_full_range_mints_a_bounded_number_of_ids` |
| `VOLUME_QUANTUM_CM3 = 0.1` | A balance reads to the gram, so a volume difference that cannot move a scale must not mint an id. Derived from `MaterialProperties`' own densities rather than restated: 0.1 cm³ of the densest material modelled (iron, 7.8 g/cm³) is 0.78 g. Add a denser material one day and the test fails rather than the claim quietly becoming false. | `test_the_volume_quantum_is_finer_than_a_balance_can_read`, `test_the_volume_quantum_is_no_finer_than_it_needs_to_be` |
| `MAX_ORBIT_PERMUTATIONS = 720` | 6!, the full symmetric group on six interchangeable parts — three quarters of the 8-part design ceiling. | `test_the_orbit_budget_is_the_full_symmetric_group_on_six_parts`, `test_six_interchangeable_parts_still_canonicalise_exactly` |

## Mechanism: `crafted_item_registry.gd`

`id -> canonical form`. Registering the same object twice is automatically one
entry, however the player happened to list its parts.

`make_item(id)` builds the `Item` a crafted id resolves to. What it derives and
what it deliberately does not:

- **Name** — an object is colloquially named for the material that does its
  work, and on a tool or weapon that is the hardest part: an "iron sword" has a
  wooden grip, a "stone axe" a wooden haft. Reuses `MaterialProperties`' own
  hardness scalar rather than a second opinion on which material counts, so the
  name and the physics agree about what the thing is made of. The name derived
  for an iron sword is pinned equal to the shipped catalog's own wording, so
  the emergent and authored tracks do not read as two different games.
- **Mass** — real: density × volume summed over the parts, straight out of
  `MaterialProperties.mass_kg_for`, exactly as `ItemCatalog._mass_kg_for`
  already does for the authored weapons. Not a design decision, so it is
  derived rather than deferred.
- **A half-measured assembly reports no mass at all.** Summing only the parts
  that happen to carry a volume would report a sword lighter than its own blade
  and present that as physics — and mass feeds the shared momentum model, where
  a wrong number propagates and a visible `0.0` does not. `item.gd`'s own
  convention is that `0.0` means "nobody has modelled this yet".
- **Damage, armor, equip slot** — left at `0.0` / `""`. Deriving those from a
  part graph is the part-graph compiler's job; inventing them here would put a
  quieter second opinion in the codebase for the compiler to later contradict.
- **`kind`** is `"crafted"`, not `"weapon"` / `"tool"` / `"armor"`, for the
  same reason. **Note the consequence:** `Item.equip_slot_name()` returns
  `"weapon"` only for kind `"weapon"` or `"tool"`, so a crafted item is *not
  yet equippable*. That is correct until the compiler assigns a slot, but it
  means the equipment half of the load path is not yet exercised end to end.

`from_dicts` re-derives every id from its structure instead of trusting the
key. Content addressing makes the key redundant, so that is free, and it means
a hand-edited save cannot leave an id naming a structure it is not. For an
untouched save it is a no-op — which is exactly what canonicalisation being
idempotent buys.

Anything that is not `id -> Dictionary` is skipped, and non-Dictionary input
yields an empty registry: a truncated save must leave the player with no
crafted items rather than a half-built registry or a crash on the load path.

## Mechanism: the `ItemCatalog` seam

`ItemCatalog.has()` / `kind_of()` / `make()` consult an optional attached
registry. This is deliberately **one** seam rather than two conditionals in
`player.gd`: the loader's `if _item_catalog.has(entry.id)` is the single point
that decides whether a saved item survives, and every other caller (the shop,
`/give`, cooking, crafted output, tile pickup) reads the same functions and
gets the fallback for free.

Two rules govern it:

- **The authored table is checked first and always wins.** Every other system
  is wired to the shipped ids — the shop prices them, recipes name them as
  outputs — so an attached registry must never shadow one.
- **`make()` still fails loudly on an id neither source knows.** Several
  callers do not check `has()` first, and quietly returning null would trade a
  crash that names its bad id for a null item propagating into an inventory.
  Unknown ids became a normal condition here; they did not become a quiet one.

A registry-less catalog behaves exactly as it did before the seam existed,
which matters because every existing caller constructs one with a bare `new()`.

## Persistence

The registry rides in the player's own save dict as a sibling key of
`"inventory"` — `Player.to_save_dict()` / `apply_save_dict()`. Loading happens
*before* the inventory and equipment loops, which is the whole point: the
catalog has to be able to answer for this save's crafted ids before it is
asked. A save written before crafted items existed has no such key and loads to
an empty registry, exactly as it did.

**Alongside the inventory, not inside it.** An inventory entry is
`{id, count}`; a structure blob inlined there would be written once per stack
and could come back as two different objects for one item. `id -> structure` is
normalized, and the entry's id is the foreign key.

**Why the player's dict and not a new store file.** Riding the existing dict
inherits New Game's wipe and its pre-wipe backup generation automatically. The
failure mode of a new single-file store is precisely the one `scenes/world.gd`
already records in its own comment about `ROOF_MODIFICATIONS_DIR`: a store
added later than `backed_up_files()` / `_wipe_persisted_world()` and never
joined to them, so a new world silently inherits the previous one's state.

`crafted_item_registry_persistence.gd` exists as the world-scoped file store
for when structures must be resolvable *outside* the player's save — dropped
items on the ground, chest and `StructureStock` contents, NPC inventories,
trading. It follows the same `store_var`/`get_var` shape as
`EventStorePersistence`/`PlayerSave`, down to the "empty registry on a missing
file" contract, and is fully tested. **It currently has no caller.** Wiring it
means joining `world.gd`'s backup and wipe lists in the same change, and that
belongs with the work that actually needs world-scoped items.

## Status / mechanisms

- ✅ `assembly_id.gd` — `canonical_form` / `assembly_id`, quantization
  (`quantize_dimension_cm`, `quantize_volume_cm3`, `dequantize_volume_cm3`,
  `quantize_treatment`), 1-WL refinement, orbit tie-breaking, documented
  fallback with an `exact` flag. `test_assembly_id.gd`, 37 tests.
- ✅ `crafted_item_registry.gd` — `register` / `has` / `get_assembly` /
  `make_item` / `kind_of` / `size` / `to_dicts` / `from_dicts`.
  `test_crafted_item_registry.gd`, 29 tests.
- ✅ `crafted_item_registry_persistence.gd` — `has_save` / `save` /
  `load_registry` / `wipe`. Tested, **no caller yet** (see above).
- ✅ `ItemCatalog.use_crafted_registry` seam — `has`/`kind_of`/`make` fall back
  to the registry, authored ids always win. `test_item_catalog.gd`.
- ✅ Save round-trip through `Player.to_save_dict`/`apply_save_dict`, including
  a pre-crafted-items save still loading. `test_player_persistence.gd`.
- ✅ Bug 2 (`item_stack.gd:45`'s id-only `can_stack_with`) fixed by
  construction — pinned by
  `test_content_addressing_makes_id_only_stacking_correct`.
- 🚧 Equipment half of the load path — a crafted item's `kind` is `"crafted"`,
  so `Item.equip_slot_name()` returns `""` and it cannot be equipped yet. Correct
  until the part-graph compiler assigns a slot, but it means the `continue` at
  the equipment load site is not yet exercised by a real crafted item.
- ⬜ Nothing yet MINTS a crafted id in play. There is no crafting UI and no
  part-graph compiler, so the registry is empty in a running game today. This
  slice removes the constraint; it does not by itself put an emergent item in
  the player's hands.
- ⬜ Damage / armor / equip slot from the part graph — the compiler's job.
- ⬜ World-scoped item structures (dropped items, chests, NPC inventories,
  trading), which is what `crafted_item_registry_persistence.gd` is for.
