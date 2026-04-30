# Reader — Playdate

A Lua e-reader app for the Playdate. Reads `.txt` and structured `.json` books from the device's Data directory. Built against Playdate SDK 3.0.5.

## Build & run

```sh
# Compile
/Users/daniel/Developer/PlaydateSDK/bin/pdc Source Reader.pdx

# Run in simulator
open -a "/Users/daniel/Developer/PlaydateSDK/bin/Playdate Simulator.app" Reader.pdx
```

The bundle ID is `com.ri604.reader` ([Source/pdxinfo](Source/pdxinfo)).

## Where books live

Books are **never bundled** in the .pdx — they're always read from the per-game Data directory. This keeps the bundle tiny and avoids duplicating libraries by both bundling and sideloading them. (Same pattern as the sibling `MP3Player` app.)

- **On hardware**: reboot into Data Disk mode and copy `.txt` or `.json` files into `/Data/com.ri604.reader/books/`.
- **On the simulator**: books live at `/Users/daniel/Developer/PlaydateSDK/Disk/Data/com.ri604.reader/books/`. Playdate merges the bundle and the Data directory at runtime, so `playdate.file.listFiles("books/")` finds them even though `books/` doesn't exist in the .pdx.

## Architecture

Single source file: [Source/main.lua](Source/main.lua). Pure Lua. Sections, top to bottom:

1. **File reading** — `readFile(path)` reads raw bytes; `readJsonFile(path)` reads and decodes JSON via the bare `json.decode()` global (NOT `playdate.json` — that's nil at runtime in SDK 3.0.5; the docs' `json.decode` shorthand is the actual API).
2. **Discovery** — `discoverBooks()` scans `books/` for `.txt` and `.json` files. JSON books get their title and author extracted from the file during discovery for display in the library.
3. **Pagination** — `paginateText(text)` splits text into pages that fit the display area (400×240 minus margins). Uses `gfx.getTextSizeForMaxWidth` to measure wrapped paragraph height. Handles paragraphs taller than a page by splitting on word boundaries.
4. **Book opening** — `openBook(book)` loads content. For JSON books with multiple chapters, shows a chapter list view; for single-chapter JSON or `.txt`, goes straight to the reader. `openChapter(idx)` paginates one chapter at a time.
5. **Drawing** — four views: `"library"` (book list), `"chapters"` (chapter list for multi-chapter books), `"reading"` (paginated text), and an empty-state screen. List views share a `drawScrollbar` helper.
6. **Input** — A opens/selects, B goes back (reading → chapters → library, or reading → library for single-chapter books). Left/right flips pages and auto-advances between chapters. Up/down navigates lists. Crank turns pages at 60° per page with accumulator reset on button flips.

## Supported formats

- **`.txt`** — plain UTF-8 text. Read via `playdate.file.open`/`read`. Each file becomes a single-chapter book titled by filename.
- **`.json`** — structured book format:
  ```json
  {
    "title": "Book Title",
    "author": "Author Name",
    "chapters": [
      { "title": "Chapter 1", "text": "Chapter text here..." }
    ]
  }
  ```
  Decoded via `json.decode()`. Multi-chapter books get a chapter list view. Single-chapter or flat `{ title, text }` books go straight to reading. Title and author are shown in the library and chapter header.
- **EPUB** — not practical natively (ZIP + XHTML + CSS, no SDK support). Use a companion converter to produce `.json` instead.

## Constraints worth remembering

- **Display is 400×240, 1-bit.** No anti-aliased text. Font choice matters more than usual; readability beats density.
- **Bold variant of the system font** is the established default for this device (see MP3Player). Stick with that until we ship a custom .fnt.
- **`json.decode()` is a bare global**, not `playdate.json.decode`. The stubs file is misleading. Confirmed by runtime test in SDK 3.0.5.
- **Data directory vs. bundle** — keep books out of the bundle. `listFiles` over a directory transparently merges both, so nothing in code needs to know the difference.
- **`getCrankChange()` accumulates across view transitions.** Drain it on entering the reader view (called in `openChapter`).
- **Don't bundle CoreLibs you don't use.** `main.lua` imports only `graphics`, `object`, `timer`.

## Implemented

- Library view listing `.txt` and `.json` books with scrolling and scroll indicator.
- JSON book discovery with title/author metadata extraction.
- Chapter list view for multi-chapter JSON books (title | author header).
- Reader view with word-wrap pagination, handling paragraphs longer than a page.
- Page navigation: left/right buttons, crank (60° per page).
- Auto-advance between chapters on page flip (forward and backward).
- Progress footer: page number, chapter indicator (for multi-chapter books), percentage, progress bar.
- B to go back through view hierarchy (reading → chapters → library).
- Empty-state screen pointing user at the Data directory.
- Bold system font globally.

## Next steps

- Persist last-read offset per book with `playdate.datastore`.
- Font size in the system menu.
- Subdirectories under `books/` as collections (matches how MP3Player treats `music/` subfolders as albums).
- Cache pagination across launches keyed by `(path, mtime, font, size)`.
- **Companion EPUB converter** — a Python script that converts EPUB to the JSON book format for transfer to Playdate.
- **WiFi book fetching** — download books from a local/remote HTTP server using `playdate.network.http` (available since OS 2.7). Flow: system menu "Download" → fetch book list from a configured URL → pick a book → stream it into `books/`. A companion script on the user's computer serves a directory of `.txt` or JSON book files. WiFi takes ~10s to connect and auto-powers off after 30s idle; up to 4 concurrent connections; 64KB read buffer (stream in chunks). A system permission dialog appears on first network access.
