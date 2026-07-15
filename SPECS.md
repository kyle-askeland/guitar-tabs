# TabStash — Project Spec

A website for creating, editing, and browsing guitar tabs. Built by one person (me),
used from both a computer and a phone browser, possibly shared openly by link (see §7),
optimized for low cost and low maintenance.

**Status:** Planning. Nothing in this doc is final — open questions are collected in §9.

---

## 1. Goals

- Create a new song (name it, then enter its tab via an interactive editor).
- Browse a list of previously created songs and open any of them.
- Edit and delete existing songs.
- Import songs from external sources instead of typing everything by hand
  (see **SPEC-IMPORT.md** for sources evaluated and decisions).
- Persist everything in a cheap AWS backend so songs survive across devices/browsers.
- Work well on desktop (where tabs get written) and on a phone (where tabs get read while playing).
- No login required; potentially usable by anyone with the link (§7).
- Side goals: get hands-on experience with **Flutter/Dart**; open-source the code.

### Non-goals (for now)

- Native mobile app. Flutter makes this a realistic **later** step from the same codebase
  (see §10), but v1 is web-only.
- User accounts / login flows.
- Audio playback or tab-to-sound rendering.

### Assumptions

- **6-string guitar only** — no 7-string, bass, or other instruments.
- **Song-list search is client-side and explicit** — the list is fetched once,
  and the Search button (never per-keystroke) filters it, so typing costs no
  Lambda invocations.
- **Connectivity required** — no offline mode (beyond the Phase 0 localStorage era).
- **Songs live forever unless explicitly deleted** — no expiry, no archiving.
- **Code should be as simple and efficient as possible** — this is a small personal
  tool; prefer the lean implementation over the flexible one.

---

## 2. Architecture Overview

```
Browser (Flutter Web app)
   │  HTTPS / JSON
   ▼
API Gateway (HTTP API)
   │
   ▼
Lambda (Node.js) ── CRUD handlers
   │
   ▼
DynamoDB (single table)
```

`flutter build web` produces plain static files, hosted on **S3 + CloudFront**.
All AWS resources are managed with **Terraform**.

### Why this stack

| Piece | Choice | Rationale |
|---|---|---|
| Frontend | Flutter (Dart), web target | Chosen to gain Flutter experience; one codebase can later add native mobile builds. |
| Routing | `go_router` | The standard Flutter routing package; handles web URLs (`/songs/:id`) properly. |
| State mgmt | Built-ins (`setState`, `ChangeNotifier`) | Keep it simple while learning; Riverpod/Provider only if it gets painful. |
| HTTP | `http` package | Plain JSON calls to the API; nothing fancier needed. |
| API | API Gateway HTTP API | Cheaper and simpler than REST API type; ~$1/million requests. |
| Compute | Lambda (Node.js) | Decided. Free tier: 1M requests/month forever; JSON-native, widest example coverage. |
| Database | DynamoDB on-demand | Free tier: 25 GB storage + generous read/write allowance. Effectively $0 for this use. |
| Infra-as-code | Terraform | My preference; whole stack (DynamoDB, Lambda, API GW, S3/CloudFront) in one `terraform apply`. |
| Access control | Anonymous ownership tokens (see §7) | No login; open read, creator-only writes. |
| Theme | Light/dark wood, painted not shipped | A `CustomPaint` grain texture — no image asset to download. |

**Estimated monthly cost: ~$0** (well within free tiers; CloudFront/S3 pennies at most).

### Flutter Web caveats (accepted trade-offs)

- Flutter web renders to canvas, not HTML. First load downloads a few MB of engine
  (cached afterward). Fine for this tool.
- Browser text selection / find-in-page don't work on tab content. Accepted:
  tabs are read and played from, not copied out.
- Tab rendering will be done with Flutter widgets using a monospace font (or
  `CustomPaint` if the grid needs finer control).

---

## 3. Data Model

### What is a tab, structurally?

A tab is a sequence of **columns** across 6 strings. Each column holds an optional
fret number (or technique symbol) per string. Songs are divided into **sections**
(Intro, Verse, Chorus...), each section holding one or more **lines** (a line = what
renders as one row of tab on screen, e.g. ~40 columns).

### Notation standard

The app follows standard guitar tab notation throughout (rendering, editing,
and import), so tabs look like every tab on the internet:

- **String order: high e on top, low E on bottom.** Rendered top→bottom as
  `e B G D A E` for standard tuning. (Note: the internal data model indexes
  strings 0 = low E; the renderer reverses the order for display.)
- **String labels** at the start of each line come from the song's tuning, so
  drop D renders `e B G D A D` labels automatically.
- **Empty positions are dashes** (`-`), never spaces: `e|---3---0---|`.
- **`0` means open string**; numbers are frets; digits in the same column across
  strings are played simultaneously (a chord).
- **Bar lines** are vertical pipes (`|`) spanning all six strings.
- Reading order is left to right; timing is not encoded (standard tab limitation —
  spacing loosely suggests rhythm).

**Standard technique symbols** (this is the target set; v1 can implement a subset):

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
| `PM` | palm mute (annotation above the staff) | `PM----` |

Example of the target rendering:

```
      Intro
e|-------0-------0---|-------0-------0---|
B|-----1-------1-----|-----1-------1-----|
G|---2-------2-------|---0-------0-------|
D|-------------------|-------------------|
A|-3-------3---------|-------------------|
E|-------------------|-2-------2---------|
```

### Song document (stored as a single DynamoDB item, JSON blob for the tab content)

```jsonc
{
  "songId": "uuid",
  "title": "Blackbird",
  "artist": "The Beatles",            // optional
  "tuning": ["E","A","D","G","B","E"], // low → high, default standard
  "capo": 0,
  "createdAt": "2026-07-08T00:00:00Z",
  "updatedAt": "2026-07-08T00:00:00Z",
  "ownerTokenHash": "sha256-of-creator-token", // ownership, see §7
  "sections": [
    {
      "name": "Intro",
      "lines": [
        {
          // sparse representation: only cells that have content
          // col = column index, str = string index (0 = low E), fret = "3", "h5", "x", etc.
          "cells": [
            { "col": 0, "str": 4, "fret": "3" },
            { "col": 2, "str": 3, "fret": "0" }
          ],
          "barlines": [8, 16, 24, 32],   // column indices where a | is drawn
          "chords":   [{ "col": 0, "name": "G" }],      // names above the staff
          "lyrics":   [{ "col": 0, "text": "hello" }],  // words below the staff
          "length": 40
        }
      ]
    }
  ]
}
```

Notes:
- `fret` is a **string**, not a number, so it can hold the standard notation
  symbols from §3: `x`, `5h7`, `7b9`, `5/7`, `<12>`, etc. The editor can start
  with plain numbers and grow into the full symbol set.
- Multi-character cells (`12`, `5h7`) are wider than one character when rendered;
  the renderer pads the other five strings with extra dashes in that column so
  everything stays vertically aligned (same rule tab notation always uses).
- In Dart these become plain model classes with `toJson`/`fromJson`.
- **Chords and lyrics are both anchored to a column**, so a chord name and the
  words sung under it line up with the notes they belong to. (Songs written
  before this carried one `lyric` string per line; it loads as a mark at
  column 0.)

### DynamoDB table

Single table `guitar-tabs`:

| Attribute | Example | Purpose |
|---|---|---|
| `PK` | `SONG#<uuid>` | Partition key |
| `SK` | `META` | Sort key (room to grow: revisions, etc.) |
| `title`, `artist`, `updatedAt` | — | Shown in the song list |
| `data` | JSON blob above | Full tab content |

Song list = a `Scan` (fine at this scale, < a few hundred songs). If it ever grows,
add a GSI with a constant partition key sorted by `updatedAt`.

---

## 4. API

| Method & Path | Purpose |
|---|---|
| `GET /songs` | List songs (id, title, artist, updatedAt only — not full tab data) |
| `POST /songs` | Create song, returns new `songId` |
| `GET /songs/{id}` | Fetch full song incl. tab data |
| `PUT /songs/{id}` | Replace song (editor saves the whole document — simplest model) |
| `DELETE /songs/{id}` | Delete song — **permanent hard delete** (owner-only per §7) |

Semantics:
- Whole-document saves keep the API and editor logic simple. Autosave with a short
  debounce (e.g. 2s after last edit) instead of a manual save button — or both.
- **Concurrent edits are last-write-wins.** Two devices sharing one token can
  clobber each other's autosaves; accepted for a personal tool, so it's a decision,
  not a surprise. DynamoDB point-in-time recovery (§7) is the safety net.
- Songs persist indefinitely — nothing expires or is archived; only an explicit
  `DELETE` removes a song, and it is immediate and permanent.

Write endpoints enforce the ownership model (§7), plus hard limits regardless:
max request body size, max songs in the table, max sections/lines per song.
Cheap insurance against abuse and runaway costs.

---

## 5. Frontend (Flutter)

### Screens / routes

1. **Song list** (`/`) — songs sorted by recently updated. Defaults to **"Mine"**
   (songs owned by this browser's token, filtered client-side) with an **"All"**
   toggle — so the home page isn't at the mercy of whoever else has the link.
   A search box filters titles and artists over both toggles, on submit only.
   "New Song" button immediately creates the (empty) song and lands in the
   editor at `/songs/{id}`; the timestamp title is renamed from there.
2. **Editor** (`/songs/:id`) — the core of the app.
3. **Play view** — read-only rendering of a song (bigger text, no cursor), the mode
   you'd actually use on a phone while holding a guitar. Could be a toggle within
   the editor screen rather than a separate route.
4. **Settings** (`/settings`) — light/dark toggle, plus the owner token (§7) for
   copying to another device, with a field to paste one in.

### Rendering rules (must match the notation standard in §3)

- Monospace font everywhere tab is displayed.
- Strings rendered high-e-on-top, labels derived from tuning (`e|`, `B|`, ... `E|`).
- Dashes for empty positions, pipes for bar lines, padding rule for
  multi-character cells (§3) — so what's on screen is character-for-character
  what a standard tab would look like anywhere else on the internet.
- No text export: pasting a tab **in** is the workflow that matters, and the
  button was dead weight (removed 2026-07).

### Editor: click-then-type grid (decided)

The editor is a clickable monospace grid: 6 rows (strings) × N columns, drawn per
the rendering rules above. UI details beyond that are **implementation free reign** —
the interaction sketches below are starting points, not requirements. The only hard
constraints:

1. Everything rendered must follow the §3 tab notation standard, so it looks like
   a normal tab.
2. Keep the code lean and efficient.

(Implemented 2026-07: lines render as a solid-line staff — six drawn string
lines with fret numbers in chips, chord names above, lyrics below, both
anchored to columns — instead of dash characters; phones input via a tappable
fretboard pad whose dots mirror the active column and whose four-fret window
fits a phone; tapping the chord row picks a chord and, given its base fret,
stamps the shape into the six strings below it; songs carry a free-text
notes/links field; and an "Import tab" action parses pasted text into the
data model. See SPEC-IMPORT.md for import sources beyond manual paste.)

Nothing is written to the store until **Save** is pressed — a full-width
button pinned under the editor, showing "Saved" once it is. The song list
refreshes the instant any save, rename, or delete lands, wherever it came from.

**Desktop (keyboard-first):**
- **Click a cell** → it becomes active (highlighted cursor).
- **Type a number** → fret goes in that cell. Two-digit frets handled by a brief
  typing window or by typing `1` then `2` within ~500ms.
- **Arrow keys** move the cursor — click once, then type/arrow through the whole line.
- Technique keys mirror the standard symbols: `x` mute, `h` hammer-on, `p` pull-off,
  `b` bend, `/` and `\` slides, `~` vibrato — typed inline after a fret number
  (e.g. `5`, `h`, `7` produces `5h7` in one cell).
- `|` inserts a bar line at the cursor column.
- `Backspace`/`Delete` to clear, `Space` to skip a column.
- Implemented with Flutter's `Focus` + keyboard event handling.

**Phone (touch):**
- Tap a cell to select it, then enter frets on a tappable fretboard rather than
  the OS keyboard: four frets at a time (five didn't fit), a position row to
  slide the window up the neck, an open-string column, and a row of technique
  symbols (h p b / \ ~ x |). Editing on the phone is expected to be occasional;
  the phone's main job is the play view.

**Both:**
- Buttons to add/remove columns, add a new line, add/rename sections.
- Horizontal scrolling within a line on narrow screens (never wrap mid-line).

Strumming helpers can come later; the chord stamp is done (§9.4).

---

## 6. Repository Layout, Deployment & Local Testing

Single monorepo, three main directories — one per concern:

```
guitar-tabs/
├── SPECS.md
├── README.md                # quickstart: how to run, test, deploy
├── Makefile                 # single entry point for all workflows (below)
├── frontend/                # Flutter app (created with `flutter create`)
│   ├── lib/
│   │   ├── models/          # Song, Section, Line, Cell + JSON serialization
│   │   ├── storage/         # abstract SongStore → LocalStore, ApiStore
│   │   ├── screens/         # song list, editor, play view
│   │   └── widgets/         # tab staff, fretboard pad, chord dialog, wood bg
│   ├── test/
│   └── pubspec.yaml
├── backend/                 # Lambda source (independent npm package)
│   ├── src/                 # handlers: one router or one file per route
│   ├── test/                # unit tests with mocked DynamoDB
│   └── package.json
└── infra/                   # Terraform, the only place AWS is defined
    ├── main.tf              # providers, backend config
    ├── dynamodb.tf
    ├── lambda.tf            # incl. archive_file zipping backend/ build output
    ├── apigateway.tf
    ├── frontend.tf          # S3 bucket + CloudFront distribution
    ├── variables.tf
    └── outputs.tf           # API URL, CloudFront domain → consumed by frontend build
```

### Workflows (all via `make`, so there's exactly one place to look)

| Command | What it does |
|---|---|
| `make run` | `flutter run -d chrome` — local dev, hot reload. Uses `LocalStore`, or `ApiStore` against the real API via `--dart-define=API_URL=...` |
| `make test` | Flutter tests + backend unit tests (`npm test`) |
| `make deploy-infra` | `terraform apply` in `infra/` — creates/updates DynamoDB, Lambda (zipped from `backend/`), API GW, S3, CloudFront |
| `make deploy-frontend` | `flutter build web` → `aws s3 sync` to the site bucket → CloudFront cache invalidation |
| `make deploy` | All of the above in order |

Notes:
- **Terraform owns infrastructure; a sync script owns frontend *content*.** The S3
  bucket and CloudFront distribution live in Terraform, but the built site files are
  uploaded with `aws s3 sync` — managing individual files in Terraform state is misery.
- **Lambda code deploys through Terraform** via `archive_file` (hash-based, so
  `terraform apply` only updates the function when `backend/` actually changed).
- **Terraform state:** S3 backend with native state locking — one tiny bootstrap
  bucket created once by hand. (Local state is simpler but dies with the laptop.)
- **Environments:** one (prod). If a dev stack is ever wanted, a `name_prefix`
  variable makes a second copy; not worth it on day one.

### Local testing strategy

- **Frontend:** `flutter run -d chrome` with `LocalStore` needs zero AWS — this is
  the Phase 0/1 daily loop. Widget/unit tests for models and tab-rendering logic
  (the dash-padding/alignment rules in §3 are very unit-testable).
- **Backend:** unit tests invoke handler functions directly with fake API Gateway
  events and a mocked DynamoDB client — no emulator needed. For integration,
  hit the real deployed stack (it's free tier; a `curl` smoke test in the Makefile
  beats maintaining DynamoDB Local in Docker for a project this size).

---

## 7. Access Model & Security

**Decided: open read + anonymous ownership** (no login, no accounts). Anyone with
the link can browse all songs and create their own; only the creator's browser can
edit or delete a song. Open-sourcing the code is independent of this — the GitHub
repo can be public regardless.

### How it works

- First visit, the app checks localStorage for an **owner token**; if absent it
  generates one (random UUID) and stores it. Invisible to the user — no login UX at all.
- `POST /songs` sends the token in a header; the Lambda stores a **hash** of it on
  the song item (hash, so a DB dump can't impersonate creators).
- `PUT`/`DELETE` require the matching token (403 otherwise); everyone can `GET` everything.
- UI hides Edit/Delete buttons on songs the browser doesn't own; the API is the
  real enforcement.

Accepted caveats:
- **The token is the identity.** Clearing browser data (or incognito, or a new
  browser) = losing edit rights to your songs — there's nothing to recover against.
  Mitigation: a settings page that shows the token for copy/paste onto another
  device. This doubles as cross-device identity: paste the laptop's token into the
  phone once, and both devices own the same songs.
- As AWS admin I can always fix/edit anything via the console regardless of tokens,
  so my own worst case is inconvenience, not data loss.
- Spam creation is still possible → hard limits (§4) + throttling (below).

### Baseline mitigations

- **API Gateway throttling** (e.g. 10 req/s, burst 20) — free, one Terraform setting.
- **Hard caps in Lambda**: max body size, max songs in table, max sections/lines per song.
- **DynamoDB point-in-time recovery** on, so vandalism/mistakes are restorable by
  me as AWS admin. Deletes are hard deletes (decided — no soft-delete flags, no
  expiry); PITR is the only undo, and only I can invoke it.
- **AWS billing alarm** (e.g. alert at $5/month) — first thing to set up.
- CloudFront in front of everything; no credentials of any kind in the frontend code
  (it's open source and it's a browser app — assume everything in it is public).

---

## 8. Build Phases

### Phase 0 — Flutter app with local persistence (learn Flutter without AWS friction)
- Flutter scaffold (web target), song list screen, basic editor grid.
- Persistence via `shared_preferences` (backed by browser localStorage) behind the
  `SongStore` interface. Note: localStorage works on any website, hosted or local —
  but it's per-browser/per-device, which is exactly why Phase 2 exists.
- **This de-risks the two unknowns separately:** Flutter first, AWS second.

### Phase 1 — Editor becomes genuinely usable
- Keyboard navigation (desktop), fretboard pad (touch), sections, multi-line,
  tuning/capo settings, delete/edit songs, read-only play view.
- Bar lines, core technique symbols (`h`, `p`, `/`, `\`, `x` first; bends,
  vibrato, harmonics after).

### Phase 2 — AWS backend
- Terraform stack in `infra/`: DynamoDB table, Lambda CRUD, API Gateway,
  throttling, billing alarm, point-in-time recovery.
- Implement the ownership model (§7) in the Lambda handlers; token generation +
  settings screen in the frontend.
- Implement `ApiStore` and swap it in for `LocalStore`. One-time migration of
  any local songs.

### Phase 3 — Deploy & polish
- `flutter build web` → S3 + CloudFront via `make deploy`, custom domain if desired.
- Autosave, phone-friendly play view polish, nice-to-haves from the backlog.

---

## 9. Open Questions

None block starting Phase 0. Remaining, all deferrable:

1. **Technique priority** — the standard symbol set is defined in §3; which subset
   matters most for the songs I actually play? (Determines Phase 1 ordering.
   Current guess: `h p / \ x` first.) Palm-mute annotations (`PM----` above the
   staff) are the one item needing extra rendering machinery — worth it early?
2. **Rhythm/timing** — bar lines are in scope (standard `|` notation). Anything
   beyond that (beat markers, `W H Q E S` duration letters above the staff) is a
   bigger jump — needed?
3. **Domain name** — custom domain, or is a CloudFront URL fine? (Phase 3 decision.)
4. ~~**Chord library**~~ — answered 2026-07: yes. One movable shape per quality,
   rooted on the low E string; the player supplies the base fret and the editor
   stamps the notes. Open chords are just base fret 0.

---

## 10. Future: native mobile app

Because the frontend is Flutter, the same codebase can later produce a real
installed phone app (better for reading tabs while playing — no browser chrome).
Notes for when/if that day comes:

- **Android:** build an APK and install it directly. Free.
- **iOS:** sideloading requires an Apple Developer membership ($99/yr) or
  re-signing a dev build every 7 days. Until then, "Add to Home Screen" on the
  web app is the workaround.
- The `SongStore`/API layer needs no changes — the app talks to the same AWS backend.
