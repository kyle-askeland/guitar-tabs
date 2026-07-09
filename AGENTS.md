# AGENTS.md — repo guide for coding agents

Personal guitar-tab website: Flutter Web frontend, Node.js Lambda backend,
Terraform-managed AWS infra. Full design in [SPECS.md](SPECS.md) — read it before
making non-trivial changes; it is the source of truth for data model, notation
rules, API semantics, and the access model.

## Prime directive: lean code

**Code must be as simple and efficient as possible.** This is a small personal
tool, not a product:

- No dead, redundant, or speculative code. If nothing calls it, delete it.
- No abstractions "for later" — the one deliberate abstraction is `SongStore`
  (local vs. API persistence); don't add layers beyond that.
- Prefer the standard library and already-present dependencies over new ones.
  Every new dependency needs a reason the stdlib can't cover.
- Whole-document saves, last-write-wins, hard deletes — keep the simple
  semantics; don't add versioning/soft-delete/caching machinery.

## Layout

| Dir | What | Toolchain |
|---|---|---|
| `frontend/` | Flutter Web app (models, storage, screens, widgets) | Dart / Flutter |
| `backend/` | Lambda source — single router in `src/index.mjs`, zero runtime deps (AWS SDK v3 is provided by the Lambda runtime) | Node 22, `node:test` |
| `infra/` | Terraform — the only place AWS is defined | Terraform ≥ 1.10 |

## Workflows

Everything goes through the [Makefile](Makefile): `make run`, `make test`,
`make deploy-infra`, `make deploy-frontend`, `make deploy`. Don't invent
parallel scripts; extend the Makefile if a new workflow is needed.

## Invariants to preserve

- **Tab notation** (SPECS §3): high-e-on-top rendering, dashes never spaces,
  string labels from tuning, multi-char cells pad sibling strings with dashes.
  `frontend/lib/models/tab_text.dart` is the single implementation of these
  rules — grid display, play view, and text export all go through it.
- **Data model**: strings indexed 0 = low E internally; renderer reverses.
  `fret` is a string (holds `x`, `5h7`, `<12>`, …), never parsed as a number.
- **Ownership** (SPECS §7): `x-owner-token` header, SHA-256 hash stored on the
  item; GET is open, PUT/DELETE require the matching token (403 otherwise).
- **Hard caps** live in the Lambda (body size, song count, sections/lines) —
  keep them enforced on every write path.
- **Terraform owns infrastructure; `aws s3 sync` owns frontend content.**
  Never manage site files in Terraform state.
- No credentials or secrets anywhere in `frontend/` — it ships to browsers.

## Testing

- `backend/`: `npm test` — handler invoked directly with fake API GW events,
  DynamoDB mocked by injection. No emulators, no Docker.
- `frontend/`: `flutter test` — model JSON round-trips and ASCII-rendering
  rules are the high-value tests.
- Integration: `make smoke` curls the deployed API (free tier, no local stack).
