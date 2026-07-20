# TabStash — Architecture

A website for creating, editing, and browsing guitar tabs. Flutter Web frontend,
Node.js Lambda + DynamoDB backend, all AWS resources managed with Terraform.
Built and used by one person, from both a computer and a phone browser.

This doc describes the system **as it currently exists in code** — the frontend
is the source of truth whenever code and doc disagree. For what's undecided or
not yet built, see [ROADMAP.md](ROADMAP.md).

## Goals & non-goals

- Create, edit, browse, and delete songs; persist them in a cheap AWS backend
  so they survive across devices/browsers.
- Work well on desktop (where tabs get written) and phone (where tabs get read
  while playing).
- No login. Anyone with the link can read; only the creator's browser can edit
  or delete (see [Access model](#access-model--security)).
- Lean code: no dead/speculative abstractions beyond `SongStore`. See
  [AGENTS.md](../AGENTS.md) for the full "prime directive."
- Non-goals: native mobile app (not ruled out later — see ROADMAP), user
  accounts, audio playback/tab-to-sound rendering.
- 6-string guitar only. No offline mode. Songs persist until explicitly
  deleted (no expiry/archiving).

## Stack overview

```
Browser (Flutter Web app)
   │  HTTPS / JSON
   ▼
API Gateway (HTTP API)
   │
   ▼
Lambda (Node.js) ── CRUD handler, single router
   │
   ▼
DynamoDB (single table, on-demand)
```

`flutter build web` produces static files hosted on **S3 + CloudFront**. All
AWS resources are defined in `infra/` with **Terraform**.

| Piece | Choice | Why |
|---|---|---|
| Frontend | Flutter (Dart), web target | One codebase could later add native mobile builds. |
| Routing | `go_router` | Handles web URLs (`/songs/:id`) properly. |
| State mgmt | Built-ins (`setState`) | No Riverpod/Provider — not needed at this size. |
| HTTP | `http` package | Plain JSON calls to the API. |
| API | API Gateway HTTP API | Cheaper/simpler than REST API type. |
| Compute | Lambda (Node.js 22) | Zero runtime deps — AWS SDK v3 is provided by the Lambda runtime. |
| Database | DynamoDB, `PAY_PER_REQUEST` | Effectively free at personal scale. |
| Infra-as-code | Terraform, S3 backend with native state locking | Whole stack in one `terraform apply`. |
| Access control | Anonymous ownership tokens | No login; open read, creator-only writes. |
| Theme | Light/dark wood, painted not shipped | `CustomPaint` grain texture (`wood_background.dart`) — no image asset. |

There is no cost-monitoring resource (billing alarm/budget) in `infra/` today.

## Data model

`frontend/lib/models/song.dart` is the canonical model; `toJson`/`fromJson`
round-trip through the API and through `LocalStore`.

```jsonc
{
  "songId": "uuid",
  "title": "Blackbird",
  "artist": "The Beatles",             // optional
  "tuning": ["E","A","D","G","B","E"], // low → high, default standard
  "beatsPerMeasure": 4,                // drives the measure/barline grid, default 4
  "notes": "Capo 3. Tutorial: https://...", // free text: capo, practice notes, links
  "createdAt": "2026-07-08T00:00:00Z",
  "updatedAt": "2026-07-08T00:00:00Z",
  "sections": [
    {
      "name": "Intro",
      "lines": [
        {
          "mode": "tab",                 // "tab" (full 6-string staff) | "chords" (no staff)
          "cells": [
            { "col": 0, "str": 4, "fret": "3" },
            { "col": 2, "str": 3, "fret": "0" }
          ],
          "barlines": [8, 16, 24],        // column indices where a | is drawn
          "chords": [{ "col": 0, "name": "G" }],
          "lyrics": [{ "col": 0, "text": "hello" }],
          "strums": [{ "col": 0, "dir": "D" }],  // "D" down / "U" up, rhythm row
          "length": 32
        }
      ]
    }
  ]
}
```

Notes on the shape:

- **No structured `capo` field.** Capo, practice reminders, and tutorial
  links all live in the song's freeform `notes` field (URLs in it render
  tappable — `notes_card.dart`). This superseded an earlier plan to give capo
  its own field.
- **`beatsPerMeasure` is how rhythm/timing is encoded**, not the plain "timing
  isn't encoded" limitation of paper tab. Every line is laid out on a measure
  grid (`measureCols = beatsPerMeasure * 2` columns per measure); default
  barlines and default line length are derived from it. Changing a song's
  `beatsPerMeasure` re-lays every line's cells/chords/lyrics/strums/barlines
  onto the new grid (`Line.remeasure`), warning first if the narrower grid
  would drop anything that no longer fits (`Line.remeasureLosses`).
- **`strums`** is a rhythm-only row (arrows above the chord row: `D` down,
  `U` up per column) — separate from `cells`, since strum direction isn't
  tied to any one string.
- **`mode` lives on `Line`, not `Song`**, so one song can mix a fingerpicked
  `tab`-mode intro with plain `chords`-mode (chord names + lyrics, no staff)
  verses. `chords` mode omits the six-string staff and barlines entirely.
- `fret` is always a **string**, holding technique notation (`x`, `5h7`,
  `7b9r7`, `<12>`, …), never parsed as a number.
- Multi-character cells widen their column so all six strings stay vertically
  aligned (same rule printed tab always uses) — `Line.columnWidths`.
- Chords and lyrics are anchored to a column each, independent of cells, so
  they line up with the notes they belong to even in `chords` mode.
- Legacy songs with one `lyric` string per line (pre-`LyricMark`) load as a
  mark at column 0 (`Line._lyricsFrom`).

### Notation standard

Followed throughout rendering, editing, and import so tabs look like every
tab on the internet:

- **String order: high e on top, low E on bottom** (`e B G D A E` for
  standard tuning). Internally strings are indexed 0 = low E; the renderer
  reverses for display.
- **Empty positions are dashes**, never spaces. **`0`** = open string.
  Digits in the same column across strings = a chord (played simultaneously).
- **Bar lines** are vertical pipes spanning all six strings.

Technique symbols, all implemented (`?` icon in the editor opens
`legend_dialog.dart`, which documents these):

| Symbol | Meaning | Example |
|---|---|---|
| `h` | hammer-on | `5h7` |
| `p` | pull-off | `7p5` |
| `b` | bend | `7b9` |
| `r` | bend release | `7b9r7` |
| `/` | slide up | `5/7` |
| `\` | slide down | `7\5` |
| `x` | muted / dead note | `x` |
| `~` | vibrato | `7~` |
| `t` | tapping | `12t` |
| `( )` | ghost/optional note | `(5)` |
| `< >` | natural harmonic | `<12>` |

`PM` (palm mute, annotated above the staff) is documented in the legend as
notation guidance but has **no backing data field or rendering** yet — see
ROADMAP.

`tab_staff.dart` draws hammer-on/pull-off as a slur arc and slides as a
diagonal (slope matches the typed `/` or `\`) over the fret-number chip.

### DynamoDB table

Single table `guitar-tabs` (name from `var.name_prefix`):

| Attribute | Example | Purpose |
|---|---|---|
| `PK` | `SONG#<uuid>` | Partition key |
| `SK` | `META` | Sort key (room to grow) |
| `title`, `artist`, `updatedAt`, `ownerTokenHash` | — | Projected for the list scan |
| `data` | JSON blob above | Full song document |

Song list = a `Scan` (fine at this scale). No GSI exists; would be the answer
if the table ever grows past a few hundred songs.

## API

Implemented in `backend/src/index.mjs`, a single router function.

| Method & Path | Purpose |
|---|---|
| `GET /songs` | List songs (id, title, artist, updatedAt, `mine`) — not full tab data |
| `POST /songs` | Create song (requires `x-owner-token`), returns the full document |
| `GET /songs/{id}` | Fetch full song incl. tab data, plus `mine` |
| `PUT /songs/{id}` | Replace song (owner only, 403 otherwise) |
| `DELETE /songs/{id}` | Permanent hard delete (owner only) |

Semantics:

- **Whole-document saves.** The editor's Save button PUTs the entire song;
  nothing is persisted until it's pressed (no autosave).
- **Last-write-wins.** No versioning/conflict detection — DynamoDB
  point-in-time recovery is the only safety net.
- Hard caps enforced server-side on every write, regardless of ownership:
  `MAX_BODY_BYTES = 128 KiB`, `MAX_SONGS = 500`, `MAX_SECTIONS = 50`,
  `MAX_LINES_PER_SECTION = 100`, `beatsPerMeasure` clamped to 1–32.
- `mine` is computed server-side per request by comparing the caller's
  `x-owner-token` (hashed) against the stored `ownerTokenHash` — never
  trusted from the client.

## Frontend

### Screens / routes (`lib/main.dart`, `go_router`)

1. **Song list** (`/`) — `song_list_screen.dart`. Fetched once, filtered
   client-side. **Mine / All** toggle (defaults to Mine); a search box
   filters titles/artists **on submit only**, not per keystroke (costs no API
   calls while typing). "New Song" creates a song immediately — no title
   prompt; the title defaults to a timestamp and gets renamed later via song
   settings — then pushes straight into the editor.
2. **Editor** (`/songs/:id`) — `editor_screen.dart`. The core of the app; see
   below.
3. **Play view** — a toggle within the editor screen (not a separate route).
   Read-only rendering with a bottom control bar: autoscroll (play/pause + a
   ± speed stepper, px/sec) and an independent ± zoom stepper. Both are
   session-only, not persisted. A brand-new song opens straight into edit
   mode; any existing song opens in play view first.
4. **Settings** (`/settings`) — light/dark toggle, and the owner token
   (copy/paste to transfer identity to another device).

### Storage abstraction (`lib/storage/`)

`SongStore` is the one deliberate abstraction (`song_store.dart`):
`LocalStore` (browser localStorage via `shared_preferences`, zero AWS) or
`ApiStore` (talks to the deployed API, owner token on every request), chosen
at compile time by `--dart-define=API_URL=...`. Both are wrapped by a
`_NotifyingStore` that bumps a `ValueNotifier` on every write, so the song
list refreshes instantly after any save/rename/delete from anywhere in the
app.

### Editor: click-then-type grid

`TabStaff` (`widgets/tab_staff.dart`) paints one line as a single
`CustomPaint`: six solid string lines, fret numbers in chips that knock out
the string line behind them, a strum-arrow row, a chord row, and a lyric
row — all in one painter with tap hit-testing (cheaper than a grid of
`GestureDetector`s).

**Desktop (keyboard-first):**
- Click a cell → cursor. Arrow keys move it (up/down = string, left/right =
  column); `Space` also advances.
- Typing a digit extends the current cell if it arrived within ~800ms of the
  last keystroke or right after a technique letter (`5` then `h` then `7` →
  `5h7`); otherwise it replaces the cell.
- Technique keys (`h p b r / \ ~ x`) append to the existing fret; `x` always
  replaces.
- `|` toggles a barline at the cursor column. `Backspace`/`Delete` clears.
- `Ctrl`/`Cmd`+`Z` undoes — works even with no cursor set.

**Phone (touch):** tapping a cell opens `FretboardPad`
(`widgets/fretboard_pad.dart`) — a 4-fret-wide window (jumps to whichever
fret has content), a position-shortcut row, an open-string column, and a
technique-symbol row. Tapping a fretted note again removes it.

**Both:**
- Tapping the chord row opens `ChordChoice` (`widgets/chord_dialog.dart`):
  pick a root + quality, get either the true open-position voicing (when one
  is taught) or a movable E-shape/A-shape barre chord at a steppable base
  fret (`models/chords.dart`). "Fill tab" stamps the resolved frets into that
  column (unplayed strings become an explicit `x`, not blank); "Name only"
  just labels the column.
- Tapping the strum row cycles none → down (`↓`) → up (`↑`) → none.
- `+ Tab line` appends a blank tab-mode line; `+ Chords paragraph` opens a
  multi-line textarea, one lyric line per pasted row, each becoming its own
  `chords`-mode line (chords tapped on afterward). A brand-new section
  defaults its first line to `chords` mode; a line inserted next to an
  existing one inherits that line's mode.
- Lines are reorderable (drag handle), duplicable, and insertable above.
- Nothing is written to the store until **Save** is pressed (full-width
  button, shows "Saved" once clean). Back navigation with unsaved changes
  prompts save/discard/cancel.
- **Undo**: a bounded (150-entry) in-memory snapshot stack, keyed off the
  single mutation funnel (`_touch()`) every edit path runs through. No redo.
- `?` icon opens the notation legend (`legend_dialog.dart`).

### Starting a new song

A brand-new song opens a dialog (`_startSongDialog`, reachable again later
from the menu as "Look up lyrics / paste tab"): look up lyrics by
artist/title, or paste text directly.

- **Lookup**: `models/lyrics_lookup.dart` calls **lyrics.ovh**
  (`api.lyrics.ovh/v1/<artist>/<title>`) for the actual lyrics, and its
  `/suggest` endpoint (a thin wrapper over Deezer search) for debounced
  search-as-you-type autocomplete as the user types artist/title — the
  autocomplete is what tolerates typos, since the lookup itself needs an
  exact match. A miss is a plain "no lyrics found" message, never an error
  state.
- Found lyrics populate one `chords`-mode line per paragraph line (blank
  lines survive as empty lines), appended to (or replacing, if the song is
  still untouched) the current content. There's no per-section/column
  alignment against existing chords — it's a flat append.
- **Paste**: `models/tab_import.dart`'s `parseTab` recognizes 6-line ASCII
  tab blocks, `[Section]`/`Verse:` headers (including inline chords on the
  header line, and trailing `[2x]`-style repeat markers), chord-name rows,
  and lyric rows — producing `tab`-mode lines where real fret data exists and
  `chords`-mode lines where it doesn't, in one pass (no separate "detect the
  format" step). If nothing tab-shaped parses, the whole paste is treated as
  plain lyrics instead of silently discarded.

## Repository layout

```
guitar-tabs/
├── README.md                # quickstart: how to run, test, deploy
├── AGENTS.md                 # contributor/agent guide + invariants
├── docs/
│   ├── ARCHITECTURE.md       # this file
│   └── ROADMAP.md            # open questions, build phases, future ideas
├── Makefile                  # single entry point for all workflows
├── frontend/                 # Flutter app (flutter create)
│   ├── lib/
│   │   ├── models/           # Song, Section, Line, chords, tab_import, lyrics_lookup
│   │   ├── storage/          # SongStore → LocalStore, ApiStore, owner_token, app_theme
│   │   ├── screens/          # song list, editor, settings
│   │   └── widgets/          # tab staff, fretboard pad, chord dialog, legend, notes, wood bg
│   ├── test/
│   └── pubspec.yaml
├── backend/                  # Lambda source, independent npm package, zero runtime deps
│   ├── src/index.mjs         # single router: all CRUD handlers
│   ├── test/                 # unit tests, mocked DynamoDB client
│   └── package.json
└── infra/                    # Terraform, the only place AWS is defined
    ├── main.tf                # providers, S3 backend, default tags
    ├── dynamodb.tf
    ├── lambda.tf              # incl. archive_file zipping backend/src
    ├── apigateway.tf
    ├── frontend.tf            # S3 bucket (OAC-only) + CloudFront distribution
    ├── variables.tf
    └── outputs.tf              # api_url, site_url, site_bucket, cloudfront_distribution_id
```

## Deployment & local testing

### Workflows (all via `make`)

| Command | What it does |
|---|---|
| `make run` | `flutter run -d chrome` — local dev. Uses `LocalStore`, or `ApiStore` against a real API via `make run API_URL=...` |
| `make test` | Backend unit tests (`npm test`) + Flutter tests |
| `make deploy-infra` | `terraform apply` in `infra/` |
| `make deploy-frontend` | `flutter build web` → `aws s3 sync` → CloudFront invalidation |
| `make deploy` | Both of the above, in order |
| `make smoke` | `curl`s the deployed API |

- **Terraform owns infrastructure; `aws s3 sync` owns frontend *content*** —
  the S3 bucket/CloudFront distribution are Terraform resources, but built
  site files are synced directly, not tracked in Terraform state.
- **Lambda code deploys through Terraform** via `archive_file` (hash-based —
  only updates the function when `backend/src` actually changed).
- **Terraform state**: S3 backend (`guitar-tabs-tfstate`, bootstrapped once by
  hand) with native state locking (`use_lockfile`).
- **Environments**: one (prod). `var.name_prefix` exists to stand up a second
  copy if ever needed.
- All taggable resources carry `Project`/`ManagedBy` tags (`main.tf`) so
  spend is isolable in Cost Explorer.

### Local testing strategy

- **Frontend**: `flutter run -d chrome` with `LocalStore` needs zero AWS.
  `flutter test` covers model JSON round-trips, notation/alignment rules,
  chord resolution, tab import parsing, and widget behavior
  (`frontend/test/*_test.dart`).
- **Backend**: `npm test` invokes the handler directly with fake API Gateway
  events and an injected mock DynamoDB client (`backend/test/handler.test.mjs`)
  — no emulator, no Docker.
- **Integration**: `make smoke` curls the real deployed API — free tier, no
  local stack to maintain.

## Access model & security

**Open read + anonymous ownership**, no login/accounts.

- First visit: `owner_token.dart` checks localStorage for a token; if
  absent, generates one (32 random hex chars via `Random.secure()`) and
  stores it — invisible to the user, no login UX.
- Every write sends it as `x-owner-token`; the Lambda stores its **SHA-256
  hash** on the item (`invalidSong`/`makeHandler` in `index.mjs`) — a DB dump
  can't impersonate creators.
- `GET` is open to everyone. `PUT`/`DELETE` require the matching token (403
  otherwise). The UI hides Edit/Delete on songs the browser doesn't own
  (`mine: false`), but the API is the real enforcement.
- The Settings screen shows the raw token for copy/paste onto another
  device — this doubles as cross-device identity transfer.
- Clearing browser data (or a new browser/incognito) loses edit rights to
  previously-created songs; there's no recovery path for that specific case.

### Baseline mitigations

- **API Gateway throttling**: 10 req/s steady, burst 20
  (`apigateway.tf` default route settings).
- **Hard caps in Lambda** (see [API](#api)) enforced on every write.
- **DynamoDB point-in-time recovery** on, with `prevent_destroy` — deletes
  are hard deletes by design; PITR is the only undo, and only via AWS
  console access.
- **S3 bucket is fully private** (all public access blocked); CloudFront
  reaches it only via Origin Access Control. No credentials of any kind ship
  in the frontend build.
- **No billing alarm/budget resource exists in `infra/`** today.
