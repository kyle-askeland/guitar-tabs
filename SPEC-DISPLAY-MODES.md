# TabStash — Line Display Modes Spec

Companion to SPECS.md. Covers letting a song mix full 6-string tab with a
plain chords-and-lyrics view, line by line, instead of forcing one rendering
for the whole song.

**Status:** Exploration. Nothing here is built yet. This resolves the open
question left in SPEC-IMPORT.md §2/§6.1 (chords-only sections currently
render six blank string lines under the chord/lyric text).

---

## 1. Motivation

Real lead sheets mix styles within one song: a fingerpicked intro or riff
gets real tab (it's specific and needs frets), but verses/choruses are often
just "strum these chords, sing these words" — no fret data at all. Example
(lyrics + chords, no staff):

```
    C                D                Em
And all the roads we have to walk are winding
    C                   D                 Em
And all the lights that lead us there are blinding
C              D
There are many things that I would
G       D      Em
Like to say to you
                 A
But I don't know how
```

Today every `Line` always renders the full six-string staff (§3 of SPECS.md),
even when it has no `cells` — so a chords-only section still shows six blank
string lines under the chord names and lyrics. That's the gap this spec
closes.

**Not a song-level toggle.** A whole-song "tab mode vs. chords mode" switch
would be wrong for the common case: one song, one fingerpicked intro line,
everything else chords-only. The mode has to live on the **line**, so a
single song can freely mix both.

---

## 2. Data model change

Add a `mode` field to `Line` (SPECS.md §3):

```jsonc
{
  "mode": "tab",     // "tab" (default) | "chords"
  "cells": [...],
  "barlines": [...],
  "chords": [...],
  "lyrics": [...],
  "length": 40
}
```

- `"tab"` — today's behavior: full six-string staff, chords above, lyrics
  below, all anchored to columns.
- `"chords"` — no staff at all. Just the chord row and lyric row, anchored
  to columns exactly as they are today (§3's "chords and lyrics are both
  anchored to a column" already gives correct alignment — nothing about that
  part changes).
- Missing `mode` on existing songs defaults to `"tab"` — no migration needed,
  every line created before this ships already has whatever `cells` it has.
- Switching a line from `tab` → `chords` doesn't delete its `cells`; it just
  stops rendering them, so switching back is lossless. Switching `chords` →
  `tab` reveals an empty staff ready for fret entry.

---

## 3. Rendering

- `chords` mode: render the chord-name row and lyric row exactly as `tab`
  mode does today, omit the six string lines and any bar lines entirely.
  Visually this is a plain chord sheet — chord names sitting directly above
  the lyric word/syllable they change on.
- `tab` mode: unchanged from today.
- Song-level header (title, artist, **tuning, capo**) keeps rendering above
  the song regardless of line mode — that's already global, not per-line,
  and matches "capo and stuff at the top" from the sample above (the
  vaclavblazej format in SPEC-IMPORT.md §2 has the same shape: a metadata
  header once, then a mix of chords-only and tab sections below it).

---

## 4. Editing

- Each line gets a mode toggle/chip (e.g. `[Tab]` / `[Chords]`) near the
  line's controls. Flipping to `chords` hides the staff and fretboard pad
  for that line; flipping to `tab` shows them again (§2 — lossless either
  way).
- In `chords` mode, editing is just: type the lyric text, tap a column above
  a word to place/move a chord (chord picker already exists per SPECS.md
  §5's chord stamp), and edit the lyric text. No fretboard pad needed since
  there's no staff to stamp into.

### Adding lines — two distinct actions

A single "add line" button that then asks for a mode is one tap too many for
the common case (typing a whole verse). Instead, a section's controls offer:

- **`+ Tab line`** — today's behavior, unchanged: one blank six-string staff
  line, fretboard pad on tap.
- **`+ Chords paragraph`** — a textarea for pasting/typing several lines of
  lyrics at once (a whole verse, not one row). Each newline becomes its own
  `chords`-mode `Line`, chord row empty, lyric row populated from the text.
  Chords then get tapped on afterward, one word at a time, across however
  many lines that produced. This mirrors how the vaclavblazej import format
  (SPEC-IMPORT.md §2) is already shaped — lyric block first, chords layered
  on after — and avoids re-doing "add line" once per lyric line.

### Default mode

- A **new, empty section** defaults its first line to `chords` mode — the
  faster path (paste lyrics, tap chords on top) is the common case; dropping
  into `tab` for a specific riff is the exception, done via the explicit
  `+ Tab line` action.
- A **new line added within an existing section** inherits the mode of the
  line above it, so a multi-line chords paragraph doesn't require re-toggling
  per line, and a section made of several tab lines stays in tab mode by
  default too.

### Mockups

Edit mode, one section of each mode in the same song:

```
┌ Intro ───────────────────────── [Tab] ⋮ ─┐
│ e|-------0-------0---|                   │
│ B|-----1-------1-----|   (fretboard pad  │
│ G|---2-------2-------|    below on tap)  │
│ ...                                      │
└───────────────────────────────────────────┘
┌ Verse ────────────────────── [Chords] ⋮ ─┐
│   C         D          Em                │
│ And all the roads we have to walk...     │  ← tap a word to place/edit chord
│   C            D            Em           │
│ And all the lights that lead us there... │
└───────────────────────────────────────────┘
[+ Tab line]   [+ Chords paragraph]
```

Play mode — mode chips and controls disappear; `tab` lines render as today,
`chords` lines render as a plain lead sheet, larger font, no staff, no bar
lines:

```
    C                D                Em
And all the roads we have to walk are winding
    C                   D                 Em
And all the lights that lead us there are blinding
```

---

## 5. Why line-level and not section-level

Sections are the more natural grouping (a whole Verse is usually one mode),
but line-level is strictly more flexible and costs nothing extra — a
section that's uniformly one mode just has every line set the same way.
Keeping the field on `Line` also matches where `cells`/`chords`/`lyrics`
already live, so no new nesting.

---

## 6. Open questions

1. Should the editor offer a "convert whole section" bulk action, or is
   per-line toggling always fine given sections are usually uniform anyway?
2. Interaction with the vaclavblazej importer (SPEC-IMPORT.md §2): its
   `[Fingerstyle]` blocks map to `tab` lines, everything else maps to
   `chords` lines — this spec is what makes that importer's output render
   correctly instead of with six blank string lines.
3. `+ Chords paragraph`'s textarea splits on newlines 1:1 into `Line`s —
   does blank-line spacing in pasted lyrics (common between verses) need to
   survive as an empty `chords` line, or get collapsed on paste?
