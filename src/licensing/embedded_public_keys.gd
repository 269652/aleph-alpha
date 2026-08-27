extends RefCounted

## Embedded public keys the shipped game verifies serials against (see
## docs/licensing.md). ONLY the public half ever belongs here -- the
## private key that SIGNS real serials must never be embedded, committed,
## or shipped anywhere near this repository. Generate it yourself, once,
## on a machine you control, and keep it somewhere that never touches git
## (see docs/licensing.md's "Operational security").
##
## Supports more than one entry for key rotation (docs/licensing.md's own
## section on it): a serial verifying against ANY listed key is accepted,
## so adding a new key here alongside an old one lets you rotate without
## invalidating already-issued serials signed under the old key.
##
## Key-swap resistance: this file alone is NOT the whole check.
## LicenseGate/SelfIntegrity's production path also verifies this exact
## list's fingerprint against KeyFingerprint.EXPECTED_FINGERPRINT_HEX (see
## key_fingerprint.gd) -- editing this list without ALSO updating that
## pinned fingerprint fails closed instead of silently accepting a
## swapped-in key. Whenever you deliberately change this list (a real key
## rotation, not tampering), recompute and update KeyFingerprint's pinned
## value in the same change.
const PUBLIC_KEY_PEMS: Array[String] = [
	"-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmLM0s14PkF9EQUC2ggYH\n78wnixJSrZ1w9T8ql0Qn3d2GVZIrZPDGAwU6OLFlUbzy3ms6G+KBUGooSJsKmGs1\nJ5UGGK8I0akJ13mW7d8DxdBmDH8LtyW6l3U64aOrc2XAkC2aj/+3SB3zE8FWm+Hk\n9VsrgnpZKWD1nKrKFotUv3G01ezbic4cAanYDahMW4wwyPitaKb8NjRT+EPcv0YQ\n2763GeDkLpktO4mI6sI/9nAusjIxcI2XrMF1Nqfv0ITdw+ggVYz4zozbAaYpazsF\nUdvnBVoa7cCiFAhxaUi6JwAJOY3wW/IJW2He81W3A2SNvKzrTkP3mfLTk3svWue9\nCQIDAQAB\n-----END PUBLIC KEY-----",
]
