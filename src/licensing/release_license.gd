extends RefCounted

## Whether a `license.txt` may be BUNDLED INTO a release package (see
## docs/licensing.md, "Bundling a license with a release", and
## tools/release/build_release.ps1's packaging step).
##
## Asked for directly: *"make it so that the license.txt is included in the
## release if it's still valid at the time of build"*. docs/licensing.md's
## own issued-serials table already records this being done by hand once --
## license_id 2, "bundled as the `license.txt` inside the first real
## Windows distributable build (2026-09), for a specific friend" -- so this
## automates a practice that already exists rather than inventing one.
##
## "Still valid" is SerialVerifier's own answer and nothing here
## re-implements it: signature against a registered public key, and not
## past its expiry. What this adds is the PACKAGING policy sitting on top
## of that answer, which is where the consequences are. A release is
## published once and downloaded by other people; a serial bundled into it
## cannot be taken back by a later patch.
##
## Pure and static -- dictionaries in, a dictionary out, no file I/O and no
## clock of its own. The build passes the time it is building at, the same
## way SerialVerifier.verify_code takes an explicit `current_unix_time` so
## expiry logic never depends on when a test happens to run.

const SECONDS_PER_DAY := 86400

## A license that is valid today and gone next week produces a release that
## stops working for whoever downloads it, days after publication, with
## nothing in the build output that ever said so. It still ships -- it IS
## valid -- but within this window the build says so out loud. A month is
## long enough that a release published today survives an ordinary patch
## cycle (pinned by test_the_warning_window_is_a_month).
const EXPIRY_WARNING_DAYS := 30

## The owner/developer serial: every one of the 64 product bits set, which
## `SerialCodec.decode_payload`'s `decode_u64` hands back as -1. It is the
## most valid license that exists and the single worst one to ship --
## docs/licensing.md's issued-serials table marks it "local testing only.
## Not for distribution."
##
## Worth refusing in code rather than in a habit: the folder a release is
## packaged from is exactly where a developer's own testing `license.txt`
## lives (see build_release.ps1's own note). Same defence-in-depth shape as
## that script's Assert-NoPrivateKeyAmong, which likewise guards a
## one-way mistake.
const OWNER_PRODUCT_MASK := -1

## `expires_in_days` for a license with no expiry at all -- distinct from
## 0, which is a license expiring within the next 24 hours.
const NEVER_EXPIRES := -1


## Whether `code` may be bundled, given SerialVerifier's `verdict` for it
## and the moment the build is happening at.
##
## Returns {"bundle": bool, "reason": String, "expires_in_days": int,
## "warn": bool}. An empty `code` is not an error -- it is simply a build
## with no license to bundle, which is every release before this existed.
static func bundle_decision(code: String, verdict: Dictionary, now_unix: int) -> Dictionary:
	if code.strip_edges().is_empty():
		return _no("no license file to bundle")
	if not bool(verdict.get("valid", false)):
		# The build console is a DEVELOPER surface, so naming the reason is
		# fine here. docs/licensing.md's "generic failure message" rule is
		# about not handing a would-be keygen author a debugging oracle in
		# the shipped UI -- your own release output is not that.
		return _no("not valid at build time: %s" % String(verdict.get("reason", "unknown")))
	if int(verdict.get("product_mask", 0)) == OWNER_PRODUCT_MASK:
		return _no("refusing the owner/developer key -- never for distribution")

	var expiry := int(verdict.get("expiry_unix", 0))
	if expiry == 0:
		return {"bundle": true, "reason": "", "expires_in_days": NEVER_EXPIRES, "warn": false}

	var days: int = int(floor(float(expiry - now_unix) / float(SECONDS_PER_DAY)))
	return {
		"bundle": true, "reason": "",
		"expires_in_days": days, "warn": days <= EXPIRY_WARNING_DAYS,
	}


## One line for the release console, so a build never bundles -- or quietly
## fails to bundle -- a license without saying which it did.
static func report_line(decision: Dictionary) -> String:
	if not bool(decision.get("bundle", false)):
		return "license.txt: not bundled (%s)" % String(decision.get("reason", ""))
	var days := int(decision.get("expires_in_days", NEVER_EXPIRES))
	if days == NEVER_EXPIRES:
		return "license.txt: bundled (never expires)"
	if bool(decision.get("warn", false)):
		return "license.txt: bundled, BUT EXPIRES IN %d DAYS -- this release stops working then" % days
	return "license.txt: bundled (expires in %d days)" % days


static func _no(reason: String) -> Dictionary:
	return {"bundle": false, "reason": reason, "expires_in_days": NEVER_EXPIRES, "warn": false}
