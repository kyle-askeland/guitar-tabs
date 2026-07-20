# TabStash — Roadmap

Forward-looking: what's undecided, what's deliberately deferred, and what was
considered and rejected. For how the app works today, see
[ARCHITECTURE.md](ARCHITECTURE.md), which is the current-state reference —
nothing here should be read as already built unless it says so.

## Build phases

Phases 0–3 from the original plan are all substantially done: local-only
Flutter app → usable editor (keyboard + touch input, sections, multi-line,
tuning/beats settings, play view) → AWS backend (Terraform stack, ownership
model, `ApiStore`) → deploy via `make deploy`. Nothing here blocks further
work; remaining polish is tracked as open questions below.

## Open questions

1. **Palm mute (`PM`) rendering.** The notation legend documents `PM----` as
   an annotation above the staff, but there's no backing data field or
   rendering for it yet (`ARCHITECTURE.md` → Notation standard). Worth
   deciding whether it's a per-column mark (like a strum) or a per-range
   annotation before building it.
2. **Bulk mode conversion.** Line display mode (`tab`/`chords`) toggles
   per-line only; there's no "convert this whole section" action. Sections
   are usually uniform in practice, so this may never be worth adding —
   revisit if per-line toggling proves tedious.
3. **Domain name.** Currently a bare CloudFront URL. Custom domain is a cheap
   Phase-3-style add whenever it's wanted (Route 53 + ACM cert + CloudFront
   alias).
4. **Lyrics-to-existing-tab alignment.** What shipped is a flat append: a
   lyrics.ovh (or pasted) result becomes one `chords`-mode line per paragraph
   line, appended to the song. A more ambitious per-section, chord-anchored
   alignment (matching each paragraph to the right existing section, preview
   before committing) was scoped but never built — the simpler version has
   been good enough so far. Revisit only if the flat-append behavior starts
   being annoying in practice.
5. **Native mobile app.** Because the frontend is Flutter, the same codebase
   could later produce an installed Android/iOS app — no changes needed to
   `SongStore`/API, since it talks to the same backend either way. Android:
   build an APK, install directly, free. iOS: sideloading needs an Apple
   Developer membership ($99/yr) or a 7-day re-sign cycle; until then,
   "Add to Home Screen" on the web app is the workaround. Not started.

## Import: further sources considered

The manual-paste flow and the lyrics.ovh lookup (both in
[ARCHITECTURE.md](ARCHITECTURE.md)) are what's built. A broader
"search-and-import from anywhere" vision was explored; here's what's still
open vs. settled:

- **Songsterr** — rejected outright, not deferred. Their ToS and `ai.txt`
  explicitly prohibit automated/AI-agent access to Guitar Pro downloads (a
  paid-only feature). Not revisiting unless their terms change.
- **Ultimate Guitar** (unofficial API) — rejected. ToS explicitly prohibits
  scraping; publishing a scraper against a named commercial competitor's
  database in an open-source repo is the highest-risk option evaluated.
- **Hooktheory API** — rejected for this use case. Official and legal, but
  only exposes chord-progression search, not per-song charts.
- **Chordie / e-Chords / AZChords** — rejected. No public API, same
  scrape-only situation as Ultimate Guitar with no upside.
- **OLGA** (the 1992–2006 archive) — defunct; a cautionary precedent (a 1998
  Harry Fox Agency complaint erased 34,000 tabs), not a lead.
- **jasonknoll/guitar-tabs** — genuinely clean rights (real MIT license,
  explicit "free to use" statement), but as of last check has exactly one
  song in it. Worth a periodic re-check if it ever grows.
- **A legal source for fret-accurate tab remains an open problem.** No
  cleanly-licensed source with real per-song fret data at meaningful scale
  currently exists.
