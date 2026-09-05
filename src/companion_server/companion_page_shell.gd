extends RefCounted

## Tiny shared HTML wrapper (nav + minimal inline style) so the three Tier 1
## views read as one site instead of three unrelated pages. No branches, no
## state -- exercised indirectly by every view's own tests rather than
## given a dedicated test file of its own.

static func wrap(title: String, body_html: String) -> String:
	return """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>%s -- Companion</title>
<style>
body { font-family: sans-serif; margin: 2em; background: #faf8f4; color: #222; }
nav a { margin-right: 1em; }
table { border-collapse: collapse; width: 100%%; }
td, th { padding: 0.3em 0.6em; border-bottom: 1px solid #ddd; text-align: left; }
</style>
</head>
<body>
<nav>
<a href="/">Character Sheet</a>
<a href="/items">Item Catalog</a>
<a href="/companions">Companions</a>
</nav>
<h1>%s</h1>
%s
</body>
</html>""" % [title, title, body_html]
