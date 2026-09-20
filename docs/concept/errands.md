# Errands — handing a villager the thing they need

The loop this project has never been able to close. A settlement's
households really do run short of the inputs their own occupation recipe
needs; [quests.md](quests.md)'s projection really does read that shortage
off live market and recipe state; the dialogue layer really does notice
when the player is carrying exactly what is missing
(`DialogueContext`'s `shortfall_covered_by_player`, read by
`DialogueTopic._household_ask_facts` as `covered_by_player`). And then
the villager says *"I could use three more rock"* to a player who has
three rock and **there is no key that gives it to them**.

Measured in the 2026-09-20 diagnosis pass: the production-shortfall
projection is a read-only surface end to end. `QuestLog` carries
`accept`/`abandon`/`reconcile` and pays `Karma.QUEST_FULFILLED_REWARD`
when a shortage *happens to* disappear — which today means the village
fixed it itself and the player is paid for standing nearby. Nothing the
player does can make a shortage end.

This doc specifies the give verb: the one transfer that turns every
projection in the game into something a player can act on.

## Design pillars

1. **The shortage is real, and so is the ending of it.** A delivery
   writes into the *same* `Market` object `Quest.production_shortfall_
   quests_for` reads (`MarketStore.market_for(settlement_id)`), so the
   projection stops reporting the shortage because the shortage is over,
   not because a quest flag was set. Delete this whole module and the
   settlement's stock is exactly what it was — the house rule
   [quests.md](quests.md) states for itself, kept.
2. **Atomic, or it did not happen.** Goods leave the player's inventory
   and enter the market in one step, with payment resolved in the same
   step. A half-delivery that takes the rock and pays nothing is the
   kind of bug that makes a player stop trusting a verb forever.
3. **A poor village pays what it has, and remembers the rest.** The
   household pays out of its own real `Wallet` — the same finite purse
   [village_economy_balance.md](village_economy_balance.md)'s wages come
   out of. A village that cannot pay does not refuse the goods and does
   not conjure coins: it takes the delivery, pays what it holds, and
   carries the remainder as a **debt** the dialogue can speak to. Being
   owed by a village you saved is a better story than being handed gold
   that came from nowhere, and it keeps
   [economy.md](economy.md)'s one-faucet rule intact.
4. **Partial help is help.** Carrying two of the three rock a household
   needs is not a failed errand. The verb hands over what you have,
   reduces the shortfall by that much, and pays for that much. The
   shortage ends when it ends.
5. **You are paid at the village's own price.** What a unit is worth is
   `Market.price_for(item_id)`, the price the settlement's own scarcity
   already sets — so supplying something a village is desperate for pays
   better than supplying something it merely lacks, with no second
   pricing model invented for the player.

## Mechanism

### `ErrandDelivery` — pure, and the whole rule

`src/gameplay/errand_delivery.gd`, a pure `RefCounted` module with no
world access, in the spirit of `spell_cost.gd` and `village_wages.gd`.
Its inputs are the projection's own `missing` array, a plain
`{item_id: count}` of what the player carries, the household purse's
balance, and a price lookup `Callable`. Its output is the whole
transaction, decided before anything mutates:

```
{
  "given":   [{"item_id": "rock", "count": 3}, ...],   # what really moves
  "units":   3,                                        # total units given
  "value":   9,                                        # what it is worth, whole coins
  "paid":    9,                                        # what the purse can actually pay
  "debt":    0,                                        # value - paid, owed to the player
  "clears":  true,                                     # does the shortfall end
}
```

- **`deliverable_for(missing, carried)`** — per missing entry, the units
  the player could hand over: `min(need, carried)`. Entries the player
  carries none of are dropped, so an empty result means "nothing to give
  here" and is the verb's own availability test.
- **`settle(missing, carried, purse_balance, price_for)`** — the whole
  transaction above. `value` is summed per item as
  `round(price_for(item_id)) * count` with a floor of
  `MIN_COIN_PER_UNIT` (1) so a cheap good is never worth nothing;
  `paid = min(value, purse_balance)`; `debt = value - paid`.
- **`clears`** is true when every entry in `missing` is fully covered by
  the same `carried` — the projection's shortage really is over after
  this transfer, which the caller can then confirm by re-running the
  projection.

Every one of those is a pure assertion a test makes before the module
exists, per this repo's `CLAUDE.md`. `MIN_COIN_PER_UNIT` is a
test-pinned constant, not an eyeballed comment.

### The verb, at the villager's door

`World` offers **Give** as a real beat in the conversation window
whenever `DialogueContext` already reports `shortfall_covered_by_player`
*or* `ErrandDelivery.deliverable_for` is non-empty — the villager
already says they could use three rock, so the button belongs in the
same window the saying happens in. Choosing it:

1. removes the goods from `Player.inventory` (`Inventory.remove`),
2. adds them to `MarketStore.market_for(settlement_id)`
   (`Market.add_stock`) — the projection's own object,
3. pays `paid` out of the household's `Wallet` into the player's,
4. records the transfer as a real witnessed `Event` so
   [npc.md](npc.md)'s memory, rumour and recognition layers see it
   without any new bookkeeping, and a `debt` entry when one remains,
5. posts a message naming what moved and what it paid.

`QuestLog.reconcile` then finds the shortfall gone on its own next pass
and pays `Karma.QUEST_FULFILLED_REWARD` — which is now earned rather
than incidental, because the player is the reason it is gone.

### Refusals are sentences

Standing at the wrong door, carrying nothing, or carrying the wrong
thing produces a named reason rather than a dead button:
*"Mira needs rock; you carry none."* This is the same rule
[hud.md](hud.md) states for prompts and the overhaul applies to every
refusal in the game.

## Interaction with other docs

- [quests.md](quests.md) — the projection this gives hands to. Its
  "deleting every function in this file changes nothing about whether a
  settlement's market is actually short" thesis is what pillar 1 keeps.
- [village_economy_balance.md](village_economy_balance.md) — the purse
  the payment comes out of, and the one-faucet rule pillar 3 honours.
- [economy.md](economy.md) — `Market.price_for`'s scarcity pricing is
  the only price model here.
- [dialogue.md](dialogue.md) — the window the verb lives in, and the
  `covered_by_player` fact that already exists.
- [npc.md](npc.md) — the witnessed event a delivery writes, and the
  recognition/trust it feeds.
- [karma_and_luck.md](karma_and_luck.md) — `QuestLog.reconcile`'s
  existing reward, now causally earned.

## Status

- ✅ **`ErrandDelivery`, the whole transaction** (2026-09-20).
  `deliverable_for` / `settle` / `offer_from_frame`, pure and pinned by
  the properties they produce (`test_errand_delivery.gd`, 28: value
  conserved as `paid + debt == value` across purse balances, a purse
  never overdrawn, never more given than carried or needed, `clears`
  exactly when every input is covered, the pinned floor, and the offer's
  refusals naming who needs what).
- ✅ **The verb, at the villager's door** (2026-09-20).
  `ConversationWindow.open_for`'s fifth argument and its
  `give_requested` signal (`test_conversation_window.gd`, 18: the button
  names the count, an unmeetable offer is a sentence rather than a dead
  button, asking about the weather does not withdraw the offer, and
  giving withdraws it so it cannot be pressed twice).
- ✅ **The transfer** (2026-09-20).
  `EarthChunkManager.deliver_errand` (`test_earth_chunk_manager_errand.gd`,
  9: the goods leave the player and enter the settlement's own market, the
  household pays out of its own purse and is never overdrawn, a poor
  household still takes the goods and carries a debt, an offer the player
  can no longer meet moves only what is really there, the delivery is a
  real witnessed event, and the projection reports no shortage afterwards
  **because there is none**). The deal is re-settled from live inventory
  at the moment of the press, so a stale offer can never take goods that
  are gone.
- ⬜ The debt is recorded on the event but no dialogue topic speaks to it
  yet, and `NpcRecognition` does not yet read `errand_delivered` as its
  own memory kind. Both are named follow-ups, not silent gaps.
