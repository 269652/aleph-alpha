extends RefCounted

## A single fishing attempt as a small state machine (see concept/fishing.md's
## "active minigame"), driving the pure FishingMinigame timing/rarity logic:
## cast → wait for a bite → a short reaction window → caught or missed. Stateful
## but engine-free (the caller advances it with real seconds and calls react()
## on the fish key), so it stays deterministic and unit-testable.

const FishingMinigame = preload("res://src/gameplay/fishing_minigame.gd")

const IDLE := "idle"
const WAITING := "waiting"  # line's out, no bite yet
const BITING := "biting"    # a fish is on -- react NOW
const CAUGHT := "caught"
const MISSED := "missed"

## How long the player has to react once a fish bites.
const BITE_WINDOW := 1.2

var _minigame := FishingMinigame.new()
var _phase := IDLE
var _seed := 0
var _bite_delay := 0.0
var _elapsed := 0.0
var _bite_elapsed := 0.0
var _rarity := ""


func phase() -> String:
	return _phase


func rarity() -> String:
	return _rarity


## True while a line is in the water waiting or biting (not idle/resolved).
func is_active() -> bool:
	return _phase == WAITING or _phase == BITING


## How long the current phase has run -- lets a caller animate a live phase
## (e.g. the bobber dipping while BITING) without tracking its own timer.
## 0.0 outside WAITING/BITING (idle or already resolved).
func phase_elapsed_seconds() -> float:
	match _phase:
		WAITING:
			return _elapsed
		BITING:
			return _bite_elapsed
		_:
			return 0.0


## Casts a line. `bait_quality` (0..1) biases toward a quicker bite.
func cast(seed_value: int, bait_quality: float) -> void:
	_seed = seed_value
	_bite_delay = _minigame.bite_delay(seed_value, bait_quality)
	_elapsed = 0.0
	_bite_elapsed = 0.0
	_rarity = ""
	_phase = WAITING


func advance(delta: float) -> void:
	match _phase:
		WAITING:
			_elapsed += delta
			if _elapsed >= _bite_delay:
				_phase = BITING
				_bite_elapsed = 0.0
		BITING:
			_bite_elapsed += delta
			if _bite_elapsed > BITE_WINDOW:
				_phase = MISSED


## The player reeled/reacted. During a bite this lands the fish; any other time
## (nothing biting yet, or already resolved) it's a miss.
func react() -> void:
	if _phase == BITING:
		_phase = CAUGHT
		_rarity = _minigame.fish_rarity(_seed)
	elif _phase == WAITING:
		_phase = MISSED
