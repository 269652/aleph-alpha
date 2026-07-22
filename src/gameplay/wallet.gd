extends RefCounted

## Pure currency balance: never negative, never mutated on failed spends.

var balance: int = 0


## Increases the balance. Negative amounts are clamped to a no-op.
func add(amount: int) -> void:
	if amount <= 0:
		return
	balance += amount


## Decreases the balance if affordable. Returns false and leaves the
## balance unchanged if amount exceeds it.
func spend(amount: int) -> bool:
	if amount > balance:
		return false
	balance -= amount
	return true


## Non-mutating check for whether spend(amount) would succeed.
func can_afford(amount: int) -> bool:
	return amount <= balance
