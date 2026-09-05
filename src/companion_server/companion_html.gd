extends RefCounted

## A one-line named wrapper around Godot's built-in String.xml_escape(true)
## -- not a reimplementation. Hand-rolling this is a real hazard (the "&"
## replacement must run BEFORE "<"/">"/'"' or every already-escaped entity
## gets double-escaped); the engine's own implementation already gets the
## ordering right, so this file exists only to give call sites a name that
## reads "escape this for HTML" rather than a bare, easy-to-miss-the-
## argument xml_escape(true) scattered across every view.

static func escape(s: String) -> String:
	return s.xml_escape(true)
