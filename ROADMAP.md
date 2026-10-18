# Roadmap

**translator** is a keyboard-driven, offline translation dictionary for the terminal.
It is built for low-powered machines: vintage hardware, minimal Linux consoles and
single-board computers. It looks words up in local StarDict dictionaries
(`.ifo` / `.idx` / `.dict`) through [sdcv](https://github.com/Dushistov/sdcv) and
never touches the network.

## Goals and budgets

| Goal | Target |
| --- | --- |
| Runtime dependencies | Python standard library + `sdcv` binary only |
| Python | 3.8+ (still common on older distros and SBC images) |
| Cold start to first keypress | < 150 ms on a Raspberry Pi Zero class device |
| Resident memory | < 15 MB RSS (the interpreter is most of it) |
| Network | None, ever; nothing in the code imports a network module |
| Input | Keyboard only; works on a Linux virtual console with no X and no mouse |

## Key decisions

- **`curses` rather than Textual.** `curses` ships with Python, imports in a few
  milliseconds and runs on a bare VT100/Linux console. Textual pulls in `rich` and
  an async runtime, which takes hundreds of milliseconds to import and tens of MB of
  memory, and it expects a modern terminal emulator. Both conflict with the budgets above.
- **One `sdcv` subprocess per lookup, triggered on Enter.** sdcv memory-maps its
  indexes, so a single call is fast. We don't look up as the user types; each search
  runs when Enter is pressed. An in-process LRU cache makes repeated lookups free. A
  long-lived sdcv process is a later optimization, used only if measurements show it's needed.
- **Use JSON output when it's available.** `sdcv -n -j` (sdcv ≥ 0.5.2) returns structured
  results. If it isn't available, we fall back to parsing sdcv's plain-text output. Both
  paths produce the same data model.
- **The backend is an interface.** The UI depends only on `DictionaryBackend`. `SdcvBackend`
  and `MockBackend` both implement it, so the whole app runs on a dev machine without sdcv.
- **INI config (`configparser`).** It's in the standard library on every supported Python.
  `tomllib` only exists from Python 3.11 onward.

## Architecture

```
 keyboard ──► ui/tui.py (curses loop)
                 │  uses widgets: SearchBox · Viewport · StatusBar
                 │  maps keys via ui/keys.py
                 ▼
          dictionaries.py  DictionaryManager  (active pair, cycling)
                 │
                 ▼
          engine/base.py   DictionaryBackend  (interface + dataclasses)
             ┌───┴────────────┐
             ▼                ▼
     engine/sdcv.py     engine/mock.py
     subprocess → sdcv  in-memory fixture data
             │
             ▼
     engine/parser.py   JSON / plain-text → LookupResult
```

Data model (in `engine/base.py`):

- `Definition(dictionary, headword, body)`
- `LookupResult(query, exact: list[Definition], suggestions: list[str], error: str | None)`
- `DictionaryInfo(bookname, word_count, path)`

## File tree

```
translator/
├── pyproject.toml            # stdlib-only; console script `translator`
├── README.md
├── ROADMAP.md
├── src/translator/
│   ├── __init__.py
│   ├── __main__.py           # `python -m translator`
│   ├── app.py                # argparse, backend selection, wiring
│   ├── config.py             # INI config + defaults (~/.config/translator/config.ini)
│   ├── dictionaries.py       # DictionaryManager: pairs, cycling      (M4)
│   ├── engine/
│   │   ├── __init__.py       # get_backend(): sdcv if on PATH, else mock
│   │   ├── base.py           # DictionaryBackend ABC + dataclasses     (M1)
│   │   ├── errors.py         # SdcvNotFound, LookupTimeout, ...       (M1)
│   │   ├── mock.py           # MockBackend                            (M1)
│   │   ├── sdcv.py           # SdcvBackend: subprocess, timeout, cache (M2)
│   │   └── parser.py         # JSON + plain-text parsers              (M2)
│   └── ui/
│       ├── __init__.py
│       ├── keys.py           # key constants + keymap                 (M3)
│       ├── widgets.py        # SearchBox, Viewport, StatusBar          (M3)
│       └── tui.py            # curses main loop                       (M3)
└── tests/
    ├── fixtures/
    │   ├── sdcv_json/        # captured `sdcv -j` output
    │   ├── sdcv_text/        # captured plain-text output
    │   └── stardict/         # tiny real dictionary for integration tests
    ├── test_mock.py
    ├── test_parser.py
    ├── test_sdcv_backend.py  # subprocess faked; integration test skipped without sdcv
    ├── test_widgets.py       # pure logic (scrolling, line editing), no curses screen
    └── test_dictionaries.py
```

## Milestones

### Milestone 1: Local environment and architecture
- [ ] `pyproject.toml` with no runtime dependencies (`pytest` is dev-only)
- [ ] Package skeleton matching the file tree above
- [ ] `DictionaryBackend` ABC: `lookup(word, dictionaries=None) -> LookupResult`, `list_dictionaries() -> list[DictionaryInfo]`
- [ ] Dataclasses and the error hierarchy
- [ ] `MockBackend` with a small bilingual word set (EN↔ES), fake fuzzy suggestions (`difflib`), and configurable latency and failures for testing the UI
- [ ] `get_backend()` picks sdcv when `shutil.which("sdcv")` finds it, otherwise mock; `--backend` / `TRANSLATOR_BACKEND` override this
- [ ] `python -m translator --backend mock lookup hola` works with no UI (a CLI smoke test)

**Done when:** the tests pass on a machine without sdcv, and a one-shot lookup prints a result.

### Milestone 2: SDCV processing and parsing layer
- [ ] `SdcvBackend` calls `sdcv -n --utf8-output [-j] [-u BOOK]... [-2 DATA_DIR] -- WORD` through `subprocess.run` with an argument list (no shell) and a timeout
- [ ] Find out once at startup whether JSON output is supported (`sdcv --version`) and cache the answer
- [ ] JSON parser, and a plain-text parser for `-->dict` / `-->word` blocks, `Found N items, similar to …` and `Nothing similar to …`
- [ ] Split results into exact matches (headword equals the query, case-insensitive) and suggestions (sdcv's fuzzy headwords)
- [ ] Graceful errors: sdcv missing, timeout, non-zero exit with stderr, undecodable bytes (`errors="replace"`), empty query. All of these become `LookupResult.error` and are never raised into the UI.
- [ ] Clean up the body text: strip simple markup tags and normalize whitespace and tabs
- [ ] `functools.lru_cache`-style cache keyed on (word, active dictionaries)
- [ ] Unit tests against captured fixtures, plus an integration test that runs only when sdcv is installed

**Done when:** typing a misspelled word returns a list of suggestions instead of an error.

### Milestone 3: Keyboard-driven TUI
- [ ] Layout: a search line at the top, a scrollable definition viewport, and a status bar (active dictionary, match count, key hints)
- [ ] `SearchBox`: insert, backspace/delete, Left/Right, Home/End, Ctrl+U to clear the line
- [ ] `Viewport`: wrap to the terminal width, Up/Down, PgUp/PgDn, Home/End scrolling
- [ ] Suggestions panel: when there's no exact match, Tab/arrow keys select a suggestion and Enter looks it up
- [ ] Keys: **Enter** search · **Esc** clear · **↑/↓/PgUp/PgDn** scroll · **Ctrl+Q** quit
- [ ] Terminal handling:
  - `curses.raw()` so Ctrl+Q reaches the app instead of XON/XOFF flow control
  - set `ESCDELAY` to about 25 ms so Esc responds instantly
  - handle `KEY_RESIZE`
  - support monochrome terminals (colors are optional)
  - wrap everything in `curses.wrapper` so the terminal is always restored
- [ ] The widgets contain pure logic and are unit-tested without a real screen

**Done when:** the full search → read → clear → quit loop works on a Linux console (no X) and over SSH.

### Milestone 4: Multi-dictionary management
- [ ] Discover installed dictionaries through `list_dictionaries()` (`sdcv -l`)
- [ ] Define pairs in the config, for example `[pair:en-es] dictionaries = Babylon English-Spanish`, and auto-generate one pair per dictionary if none are defined
- [ ] `DictionaryManager`: active pair, `next()` / `prev()`, and a mode that searches every dictionary
- [ ] Hotkeys: **F2** / **Ctrl+N** next pair, **Ctrl+P** previous. Chosen so they don't clash with text editing.
- [ ] Switching pairs re-runs the current query, the status bar shows the active pair, and the last pair is remembered between runs
- [ ] Optional **Ctrl+R** swaps the direction of the current pair (EN→ES ⇄ ES→EN) when the config defines a reverse pair

**Done when:** one keypress flips between EN→ES and ES→EN and shows the new results.

## Later (not committed)
- A long-lived sdcv process to avoid the cost of starting one per lookup, if profiling on target hardware shows it's needed
- Lookup history (Alt+←/→)
- Packaging: a single-file zipapp (`python -m zipapp`) so installing is just copying a file
