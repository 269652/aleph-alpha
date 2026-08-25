extends RefCounted

## One placed structure's own item stock -- a Storage building's real
## inventory (see docs/concept/timber_construction.md's "Storage, logistics,
## and the autonomous dependency chain" section). Same item_id -> int shape
## Market already proves at settlement scale (src/emergence/market.gd), reused
## here at building scale rather than inventing a third container design, per
## that section's own explicit instruction.
##
## Deliberately generic, not Storage-exclusive: this is "one placed
## structure's stock", so the same class also stands in for a production
## building's own accumulated-output queue (see StructureStockStore's own
## doc comment) -- there is exactly one stock shape in this codebase, used at
## two different roles.

var stock: Dictionary = {}   # item_id -> int


func stock_of(item_id: String) -> int:
	return stock.get(item_id, 0)


func add_stock(item_id: String, count: int) -> void:
	stock[item_id] = stock_of(item_id) + count


## Withdraws `count` of item_id. All-or-nothing -- fails (false, no
## mutation) if less than `count` is present, mirroring
## CraftingRecipeBook.craft's own all-or-nothing input consumption rather
## than silently withdrawing a partial amount.
func remove_stock(item_id: String, count: int) -> bool:
	if stock_of(item_id) < count:
		return false
	stock[item_id] = stock_of(item_id) - count
	return true


func to_dict() -> Dictionary:
	return {"stock": stock}


static func from_dict(d: Dictionary) -> RefCounted:
	var structure_stock = new()
	var restored_stock: Dictionary = d.get("stock", {})
	for item_id in restored_stock:
		structure_stock.stock[str(item_id)] = int(restored_stock[item_id])
	return structure_stock
