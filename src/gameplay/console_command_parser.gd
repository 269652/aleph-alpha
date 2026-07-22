extends RefCounted

## Parses a raw dev-console input line into a command name + argument list.
## Pure/no side effects -- DevConsole (the UI node) owns reading the input
## field and dispatching the parsed command; this just turns text into data.


## Splits `line` on whitespace into {command: String, args: Array[String]}.
## A leading "/" is optional and stripped either way; the command name is
## lowercased so "/DAY" and "/day" dispatch the same. Blank/whitespace-only
## input parses to an empty command with no args, rather than erroring --
## the caller decides what an unrecognized/empty command means.
func parse(line: String) -> Dictionary:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return {"command": "", "args": []}

	var parts := trimmed.split(" ", false)
	var command: String = parts[0].trim_prefix("/").to_lower()
	var args: Array = Array(parts.slice(1))
	return {"command": command, "args": args}
