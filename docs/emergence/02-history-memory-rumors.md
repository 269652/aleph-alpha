# History, Memory, Rumors, Legends, and Archaeology

## Purpose

Turn persistent simulation into persistent narrative. The world accumulates causally grounded history that becomes stories, quests, ruins, mysteries, legends, political grievances, family traditions, artifacts, festivals, and player mythology.

## Event graph

Every meaningful event is a node in a directed causal graph:

```text
Drought → Crop failure → Food shortage → Price increase → Migration → Population decline → Settlement abandonment
```

```text
Event {
  id, tick, type, location,
  actors[], causes[], consequences[], witnesses[], evidence[],
  importance, visibility, tags[]
}
```

Event importance is computed from affected population, duration, resource impact, geographic spread, deaths, institutional impact, player involvement, uniqueness, and downstream event count.

## Memory

NPC memory is a lossy projection of authoritative history. Store event reference, remembered actors/location/outcome, confidence, emotional salience, source type, recency, and distortion.

Source types include firsthand, witnessed, trusted testimony, stranger testimony, inference, written record, and rumor.

## Fact versus belief

Authoritative facts are never overwritten by beliefs.

```text
Fact: village burned during E201.
Belief: bandits burned it.
Confidence: 0.42
Source: merchant rumor.
```

This allows disagreement without corrupting simulation truth.

## Rumor propagation

Rumors travel through social networks. Transmission can change confidence, salience, specificity, and emotional framing. Distortion is bounded and influenced by trust, knowledge, emotion, political affiliation, incentives, and social distance.

Knowledge is geographically constrained by travel, trade, institutions, kinship, correspondence, and public announcements. Remote NPCs do not receive instantaneous global information.

## Records

Letters, ledgers, contracts, laws, diaries, maps, guild records, inscriptions, and era-appropriate media preserve higher-fidelity information. Records can be lost, copied, forged, damaged, or misinterpreted.

## Legends

A legend is a culturally persistent narrative produced by high-salience events plus repeated transmission. Track origin events, cultural owner, motifs, confidence, canonical and competing versions, and sacred/political importance.

## Archaeology

Events can leave persistent evidence: ruins, graves, battlefields, abandoned roads, collapsed mines, tools, altered landscapes, monuments, contaminated areas, and buried goods. Evidence references its causal event graph.

## Historical investigation

Players investigate using physical evidence, testimony, records, artifacts, environmental state, and genealogies. Players construct hypotheses and the system scores them against known evidence. Investigation should not require quest markers.

## Historical decay

Authoritative events remain internally available while NPC memory, records, monuments, legends, and physical evidence decay at different rates.

## Player legacy

Player actions enter the same event graph. Important actions can create monuments, family stories, institutions, named roads, artifacts, traditions, festivals, political claims, and legends. The player becomes part of history rather than receiving a separate achievement layer.
