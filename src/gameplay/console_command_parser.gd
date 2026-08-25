extends RefCounted

## Parses a raw dev-console input line into a command name + argument list.
## Pure/no side effects -- DevConsole (the UI node) owns reading the input
## field and dispatching the parsed command; this just turns text into data.


## Characters a real command line can begin with: "/", or the first character
## of a bare command name. Anything in front of the first of these is layout/
## IME junk and is never part of a command -- see _strip_leading_junk.
const COMMAND_START_CHARS := "/_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


## Splits `line` on whitespace into {command: String, args: Array[String]}.
## A leading "/" is optional and stripped either way; the command name is
## lowercased so "/DAY" and "/day" dispatch the same. Blank/whitespace-only
## input parses to an empty command with no args, rather than erroring --
## the caller decides what an unrecognized/empty command means.
func parse(line: String) -> Dictionary:
	var trimmed := _strip_leading_junk(line.strip_edges())
	if trimmed.is_empty():
		return {"command": "", "args": []}

	var parts := trimmed.split(" ", false)
	var command: String = parts[0].trim_prefix("/").to_lower()
	var args: Array = Array(parts.slice(1))
	return {"command": command, "args": args}


## Drops a LEADING run of characters that cannot start a command. The console
## toggle is bound by PHYSICAL keycode, and on a German keyboard the physical
## key left of "1" is the "^" DEAD key: Windows emits nothing when it is
## pressed, buffers it, and emits it with the NEXT keystroke -- i.e. after
## DevConsole.toggle() has already cleared and focused the input field, so the
## buffered "^" lands in it and the FIRST command of every session arrived as
## "^/spawn boar 2" and failed to parse.
##
## Only the leading run is dropped, and only up to the first letter, digit,
## underscore or "/". No legitimate command can be swallowed -- every command
## begins with "/" or a letter (a bare name is valid too, see `parse`) -- and
## punctuation anywhere else, a "/" inside an argument or a negative number,
## is left alone.
func _strip_leading_junk(text: String) -> String:
	var i := 0
	while i < text.length() and not COMMAND_START_CHARS.contains(text[i]):
		i += 1
	return text.substr(i)
