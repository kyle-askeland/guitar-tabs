# TabStash — Import Spec

Companion to SPECS.md. Covers pulling songs in from external sources instead of
typing every one by hand. Binary tab formats and automated import are back in
scope as of 2026-07-14 — the earlier "paste ASCII only" restriction was about
UI quality (the old text-grid renderer, since replaced by the staff/fretboard
editor), not a lasting decision against import in general.

**Status:** Exploration. Nothing here is built yet except manual paste (§4),
which shipped earlier. Sources below are researched and evaluated but no
importer beyond paste currently exists in the code.

---

## 1. Sources evaluated

| Source | Data quality | Legal/ToS risk | Effort | Decision |
|---|---|---|---|---|
| Manual paste (existing) | Depends on what's pasted | None — user-driven, one song at a time | Done | **Keep** as universal fallback |
| [vaclavblazej/tabs](https://github.com/vaclavblazej/tabs) | Chords + lyrics, some fret data | Low, but no explicit license (see §2) | Medium — new parser needed | **Build first** (§2) |
| Songsterr | Real fret-accurate tab (huge catalog) | Medium — ToS not written for bulk reuse | High — binary GP parsing | **Worth it later** (§3) |
| Ultimate Guitar (unofficial) | Best catalog of any source | High — ToS explicitly prohibits scraping | Medium (many existing scrapers) | **Rejected** (§6) |
| Hooktheory API | Chord progressions only, no per-song charts | None (official API) | N/A — doesn't have the data | **Rejected** (§6) |
| Chordie / e-Chords / AZChords | Chords + lyrics | High — scrape-only, no API | Medium | **Rejected** (§6) |
| lyrics.ovh | Plain lyrics text only | Low — but unofficial/unreliable | Low | **Use** for lyrics-only lookup (§5) |
| Genius API | Metadata only — lyrics text not in the API | Low, but doesn't solve the problem | N/A | **Rejected** for lyrics (§5) |
| Musixmatch | Free tier caps at 30% preview | Low (official) | N/A — free tier unusable | **Rejected** for lyrics (§5) |

---

## 2. vaclavblazej/tabs bulk import (recommended first step)

An open collection of raw `.tab` files on GitHub, organized by directory:

| Directory | Count (2026-07-14) | Notes |
|---|---|---|
| `english/` | 61 | Primary target |
| `czech-slovak/` | 111 | Skip unless wanted — different language |
| `melodies/` | 10 | Standalone riffs/solos, no full song |
| `other/` | 16 | Misc, worth a look |
| `incomplete/` | 50 | Maintainer-flagged unfinished — skip |

Importing `english/` + `melodies/` + `other/` (~87 songs) stays well under the
backend's `MAX_SONGS = 500` cap (`backend/src/index.mjs`) alongside real user
songs.

### License — check before bulk-importing

The repo has **no LICENSE file**. The README invites pull requests ("I welcome
pull requests with new songs") and links a companion rendered site, which
signals the maintainer is fine with reuse — but that's not a legal grant.
Under default copyright, reuse rights are the maintainer's to give. Since this
project is meant to be open-sourced, recommend opening an issue / emailing the
maintainer to ask for explicit permission (or a license) before shipping a
bulk importer that copies their corpus wholesale into another public project.
This is a much smaller ask than it sounds — the maintainer already actively
wants the content reused (that's why the companion `tabs-web` site exists).

### Format mismatch — needs a new parser, not `parseTab` as-is

The `.tab` format is a **lead sheet**, not the same shape `tab_import.dart`'s
`parseTab` expects:

```
source video: https://youtube.com/...
capo: 7

[Intro] D D G A7  [2x]

[Chorus] D G E7 D
    Here comes the sun, doo da doo doo
    ...

[Fingerstyle]
[Intro & Verse]
e|-----2---0-2---------2-0---------|...
B|-----3-3-------3-----------3---0-|...
...
```

- A metadata header (`source`, `video`/`audio`, `capo`, `note`), then blank lines.
- Sections (`[Verse]`, `[Chorus]`, `[repeat Chorus]`) with chords either inline
  after the section name or on their own line above indented lyric text —
  **no fret data for most sections**, just chord names + lyrics.
- An optional trailing `[Fingerstyle]` block with real 6-string fret grids for
  specific riffs (intro, bridge, etc.) — this is the only part that maps
  cleanly onto `Cell`s the way `parseTab` already understands.

Practical implication: most imported sections become `Line`s with `chords`
and `lyrics` populated and **no cells at all**. Checked `tab_staff.dart:94` —
the chord/lyric rows already collapse to zero height when empty, but the
six-string staff area itself always renders, so a chords-only section would
currently show six blank string lines under the chords/lyrics text. Worth a
look before shipping the importer — either that's an acceptable rendering
(matches "this section has no tab, just the chord sheet") or the editor wants
a lighter-weight "lyrics only" line variant. **Open question, not blocking.**

### Proposed shape of the importer

- One-time/occasional offline script, not a live app feature — same pattern
  as the existing `frontend/tool/` scripts (`palette_shots.dart` etc.), or a
  new `backend/tool/` if it's easier in Node.
- Fetches raw files directly from `raw.githubusercontent.com/vaclavblazej/tabs/main/...`
  (no auth, confirmed working).
- New parser for this specific format (property header, `[Section]` + chords +
  lyrics, optional `[Fingerstyle]`), sharing primitives with `tab_import.dart`
  where the shapes overlap (chord-row/lyric-row column anchoring is the same
  problem already solved there).
- POSTs each resulting `Song` through the existing `POST /songs` API —
  no backend changes needed.

### Open question: who owns the imported songs?

- **(a) A fixed "import" token** the script holds → songs show up in "All"
  but no browser can Edit/Delete them via the UI (read-only reference set,
  matches that they're secondhand content, not something you personally
  vetted line-by-line).
- **(b) No special handling** → same as any song, editable by whoever holds
  that token. Simpler (script needs nothing beyond today's API) but means
  imported songs are indistinguishable from hand-entered ones.

Leaning (a), but worth deciding before the first run since it's awkward to
change after 87 songs already exist with one ownership model.

### Open question: one-time run or re-run later?

If the source repo gains songs over time, a re-run needs dedup (check
title+artist before creating — the backend has no natural unique key besides
`songId`). Not needed for a first pass.

---

## 3. Songsterr — worth it later, not first

**Search API — confirmed live and unauthenticated (2026-07-14):**

```
GET https://www.songsterr.com/api/songs?pattern=<query>
```

Returns JSON: `songId`, `artist`, `title`, `hasChords`, `tracks[]` (each with
`instrument`, `tuning`, a content `hash`, `views`). No API key. No published
rate limits — be polite, don't hammer it, but nothing suggests it's gated.

**The actual tab data is not in that JSON.** It ships as a **Guitar Pro binary
file** (`.gp3`–`.gp5`, or `.gpx`) attached per track/revision. The old,
commonly-referenced lookup path (`/a/ra/player/songrevision/{id}.xml` →
`guitarProTab > attachmentUrl`, from a 2014-era community library) no longer
resolves — Songsterr has changed their internals since. The current endpoint
would need to be rediscovered via the site's own network calls (browser
devtools on a real Songsterr player page); there's no current public
documentation for it.

**Turning the binary into your data model:** parse it with
[**alphaTab**](https://github.com/CoderLine/alphaTab) (MPL-2.0, works headless
in Node purely for parsing — no rendering required). It reads gp3–gp5, gpx,
and gp7, and exposes note-level beat/fret/string data through its low-level
API. This would be genuinely fret-accurate tab data — better than anything
else on this list — but it's real integration work: rediscovering the current
attachment URL, wiring up alphaTab in a Node import tool, and mapping its
beat/duration model down onto your column-based `Line` (Songsterr encodes
rhythm; your model doesn't — SPECS.md §3 "timing is not encoded" — so
durations get discarded/approximated during column spacing).

**Verdict:** strictly more capable than the vaclavblazej import (real fret
data, far bigger catalog, has chord-only songs too), but meaningfully more
engineering, and the binary-format work is exactly the kind of thing worth
doing once the vaclavblazej pipeline already exists to prove out the
POST-many-songs plumbing. Do vaclavblazej first, revisit this once alphaTab
integration earns its keep.

**Legal note:** unlike vaclavblazej/tabs, Songsterr's content isn't offered
for third-party reuse — the JSON search endpoint being open doesn't mean the
underlying tab content is. Same caution as Ultimate Guitar below, just with a
friendlier-looking unauthenticated endpoint bolted on. Worth a proper read of
their ToS before shipping this, not just before open-sourcing it.

---

## 4. Manual paste (existing, kept as universal fallback)

`frontend/lib/models/tab_import.dart`'s `parseTab` stays as-is: recognizes
6-line tab blocks, chord rows, lyric rows, and `[Section]` headers pasted
directly by the user. This remains the fallback for anything not automated —
a song from a site with no API, or a hand-typed correction to an imported one.

---

## 5. Lyrics-only lookup (chords already entered, just want the words)

A narrower, more common case than full-song import: the user has already
entered chords/tab (by hand or via §2/§3) and just wants the lyrics filled
in, not a whole new source of truth. This is a much smaller problem than
tab import — it's plain text, no frets, no chords to align, so it doesn't
need any of the heavier machinery above.

**Recommended: [lyrics.ovh](https://api.lyrics.ovh).**

```
GET https://api.lyrics.ovh/v1/<artist>/<title>
```

No auth, no key, no rate-limit doc. Verified live today (2026-07-14) —
`GET /v1/Oasis/Wonderwall` returned a real 200 with full plain-text lyrics.
Caveat: several current write-ups list it as a "dead API" and community
lyrics tools have been dropping it in favor of other sources — it clearly
still works right now, but has a reputation for being flaky/intermittently
down, so treat it as "try it, don't depend on it" rather than a guaranteed
service.

**Rejected alternatives:**
- **Genius API** — official, but a documented limitation: the API returns
  song metadata and a URL to the Genius webpage, **not the lyrics text
  itself**. Getting the actual words means scraping the HTML page, which is
  the same legal/technical shape as tab-site scraping (§6) — no better than
  lyrics.ovh, and adds an OAuth app-registration step for no benefit here.
- **Musixmatch** — official free tier exists, but caps responses at a **30%
  preview** of the lyrics; full text requires a paid commercial license.
  Unofficial reverse-engineered wrappers exist that bypass this, but that's
  the same unofficial-API risk pattern already rejected for Ultimate Guitar.

**Proposed UX:** since the song already has a title/artist on file, a
"Look up lyrics" button in the editor calls lyrics.ovh directly with those
fields (no retyping), and on success drops the plain text into the same
paste-lyrics flow that already exists — reusing `tab_import.dart`'s lyric-row
column-anchoring rather than building a second lyrics importer. On failure
(song not found, or the API being down), it's just the existing manual paste,
unchanged — no new failure mode introduced.

**Open problem, not yet solved:** `tab_import.dart` today anchors a lyric row
to columns directly under a specific 6-line tab block it just parsed — it
assumes the lyrics arrive one row at a time, aligned to a block that already
exists. A full lyrics.ovh response is the *whole song's* text as one blob,
usually without your section boundaries or column positions at all. Turning
that into per-line, per-column `LyricMark`s against sections/lines the user
already built is a real alignment problem (matching blob paragraphs to
`[Verse]`/`[Chorus]` sections by order or by repeated text, then distributing
words across whatever columns the existing chords/frets occupy). Simplest
starting point: don't try to auto-align at all — drop the fetched lyrics
into a plain text box next to the editor for the user to copy from
line-by-line, which is still strictly less typing than looking them up
externally, without solving general text alignment up front.

---

## 6. Rejected sources

- **Ultimate Guitar (unofficial mobile API).** The single best catalog of any
  option here, and mature scrapers exist ([Pilfer/ultimate-guitar-scraper](https://github.com/Pilfer/ultimate-guitar-scraper),
  [joncardasis/ultimate-api](https://github.com/joncardasis/ultimate-api)).
  Rejected because their [ToS](https://www.ultimate-guitar.com/about/tos.htm)
  explicitly prohibits probing/breaching the service, and shipping a scraper
  against a named commercial competitor's proprietary database in an
  open-source repo is the highest-risk option on this list — takedown/DMCA
  exposure lands on whoever published the code, not just whoever runs it.
  Revisit only if the importer is kept entirely private (never committed).
- **Hooktheory API.** Official, documented, OAuth-based — but it only exposes
  chord-progression trend search ("songs containing progression X"), not full
  per-song chord charts or tab data. Doesn't have what this needs.
- **Chordie / e-Chords / AZChords.** No public API on any of them — same
  scrape-only situation as Ultimate Guitar, smaller/less active communities,
  no upside over it.

---

## 7. Open questions

1. Does the tab-staff UI need a distinct "lyrics/chords only, no frets" line
   variant, or is six blank string lines under a chord sheet acceptable? (§2)
2. Ask the vaclavblazej/tabs maintainer for explicit reuse permission before
   the first bulk run, or scope it as an ask-first courtesy PR/issue? (§2)
3. Ownership model for bulk-imported songs — read-only reference set vs.
   editable like anything else? (§2)
4. Where does the import tooling live — `backend/tool/`, a new top-level
   `scripts/`, or alongside `frontend/tool/`?
5. Dedup strategy if the vaclavblazej importer is ever re-run against an
   updated source repo.
6. Songsterr's current (non-2014) attachment/revision endpoint — needs
   hands-on discovery via devtools before any alphaTab work starts.
7. Lyrics-to-section alignment (§5) — is a plain "here's the text, copy what
   you need" panel good enough for v1, or does auto-distributing words into
   existing sections/columns matter enough to build?
8. What happens when lyrics.ovh is down or the song isn't found — silent
   fallback to the existing manual-paste box, or an explicit error state?
