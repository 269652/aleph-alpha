# AGENTS.md

## Development process

Implement everything using strict Test-Driven Development (TDD): red first.

- Write a failing test before writing any implementation code. Run it and confirm it fails for the expected reason (red).
- Write the minimum code needed to make the test pass (green).
- Refactor only once the test is passing, keeping tests green throughout.
- Never write implementation code without a failing test driving it.
- Tuned values/thresholds must be tested functions or test-pinned constants, never eyeballed comments.

## Concept docs are the spec — keep them cross-aligned

`docs/concept/*.md` is the design source of truth and `docs/progress.md` is the
honest implementation ledger. Every mechanics change must stay aligned with both,
in BOTH directions:

- **Before implementing** a mechanic, read the relevant `docs/concept/*.md` file
  and build what it specifies. If no concept doc covers the mechanic, write or
  extend one first (grounded in the design pillars of neighboring docs) so the
  spec exists before the code.
- **After implementing**, update `docs/progress.md` (status legend ✅/🚧/⬜) to
  reflect exactly what is done, partial-with-known-gaps, or untouched — never
  overstate. If the implementation deliberately diverged from the concept doc,
  update the concept doc to match reality and note the divergence.
- New systems of any size get their own concept doc (see
  `docs/concept/ecosystem_dynamics.md` for the expected shape: design pillars,
  real-world grounding, mechanism spec, status list).
