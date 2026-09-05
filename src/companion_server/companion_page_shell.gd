extends RefCounted

## Shared HTML wrapper (nav + style) so the three Tier 1 views read as one
## site instead of three unrelated pages -- self-contained on purpose: no
## external font/CDN request, since Tier 1's "zero network, ever" pillar
## (docs/concept/companion_server.md) covers what the page itself loads,
## not just what companion_server.gd calls out to. No branches, no state
## beyond the title->emoji lookup -- exercised indirectly by every view's
## own tests (each asserts its real content survives the wrap) rather than
## given a dedicated test file of its own.

## title -> a small decorative touch, nothing load-bearing: an unrecognised
## title (there is none today; every view passes one of these three) still
## renders a complete page via the "🌿" default.
const _EMOJI := {
	"Character Sheet": "🎒",
	"Item Catalog": "📦",
	"Companions": "🐾",
}


static func wrap(title: String, body_html: String) -> String:
	var emoji: String = _EMOJI.get(title, "🌿")
	return """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>%s %s -- Companion</title>
<style>
:root {
	color-scheme: light dark;
	--ink: #2b2418;
	--paper: #faf3e6;
	--card: #fffdf8;
	--accent: #c8791f;
	--accent-dark: #8a4f10;
	--row-alt: #f6ecd9;
	--shadow: 0 10px 30px -12px rgba(60, 40, 10, 0.35);
}
@media (prefers-color-scheme: dark) {
	:root {
		--ink: #f1e9d8;
		--paper: #221c14;
		--card: #2c2419;
		--accent: #e0973a;
		--accent-dark: #f2b46a;
		--row-alt: #33291b;
		--shadow: 0 10px 30px -12px rgba(0, 0, 0, 0.6);
	}
}
* { box-sizing: border-box; }
body {
	font-family: -apple-system, "Segoe UI", system-ui, sans-serif;
	margin: 0;
	padding: 2.5em 1.5em;
	min-height: 100vh;
	background: var(--paper);
	background-image:
		radial-gradient(circle at 15%% 0%%, rgba(200, 121, 31, 0.10), transparent 45%%),
		radial-gradient(circle at 100%% 100%%, rgba(63, 122, 78, 0.12), transparent 45%%);
	color: var(--ink);
	display: flex;
	justify-content: center;
}
.page {
	width: 100%%;
	max-width: 46em;
	animation: rise 0.45s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}
@keyframes rise {
	from { opacity: 0; transform: translateY(10px); }
	to { opacity: 1; transform: translateY(0); }
}
nav { display: flex; gap: 0.6em; margin-bottom: 1.4em; flex-wrap: wrap; }
nav a {
	text-decoration: none;
	color: var(--accent-dark);
	background: var(--card);
	padding: 0.5em 1.1em;
	border-radius: 999px;
	font-size: 0.9em;
	font-weight: 600;
	box-shadow: 0 2px 6px -2px rgba(60, 40, 10, 0.25);
	transition: transform 0.15s ease, box-shadow 0.15s ease, background 0.15s ease, color 0.15s ease;
}
nav a:hover {
	transform: translateY(-2px) scale(1.04);
	box-shadow: var(--shadow);
	background: var(--accent);
	color: #fff;
}
.card {
	background: var(--card);
	border-radius: 20px;
	padding: 1.8em 2em 2.2em;
	box-shadow: var(--shadow);
}
.portrait {
	display: block;
	margin: 0 auto 1.2em;
	width: 100%%;
	max-width: 360px;
	height: auto;
	border-radius: 14px;
	box-shadow: var(--shadow);
	image-rendering: pixelated;
}
h1 { margin: 0 0 0.6em; font-size: 1.6em; display: flex; align-items: center; gap: 0.35em; }
h1 .emoji { display: inline-block; animation: bounce 2.2s ease-in-out infinite; }
@keyframes bounce {
	0%%, 100%% { transform: translateY(0) rotate(0deg); }
	50%% { transform: translateY(-4px) rotate(-6deg); }
}
h2 {
	font-size: 1.05em;
	color: var(--accent-dark);
	margin: 1.4em 0 0.5em;
	border-bottom: 2px solid var(--row-alt);
	padding-bottom: 0.3em;
}
p { line-height: 1.6; }
ul { padding-left: 1.2em; line-height: 1.7; }
li { transition: transform 0.15s ease; }
li:hover { transform: translateX(3px); }
table {
	border-collapse: separate;
	border-spacing: 0;
	width: 100%%;
	margin-top: 0.4em;
	border-radius: 12px;
	overflow: hidden;
	box-shadow: 0 0 0 1px var(--row-alt);
}
th {
	background: var(--accent);
	color: #fff;
	text-align: left;
	padding: 0.6em 0.8em;
	font-size: 0.85em;
	text-transform: uppercase;
	letter-spacing: 0.03em;
}
td { padding: 0.5em 0.8em; border-top: 1px solid var(--row-alt); font-size: 0.95em; transition: background 0.15s ease; }
tr:nth-child(even) td { background: var(--row-alt); }
tr:hover td { background: var(--accent); color: #fff; }
</style>
</head>
<body>
<div class="page">
<nav>
<a href="/">Character Sheet</a>
<a href="/items">Item Catalog</a>
<a href="/companions">Companions</a>
</nav>
<div class="card">
<h1><span class="emoji">%s</span> %s</h1>
%s
</div>
</div>
</body>
</html>""" % [emoji, title, emoji, title, body_html]
