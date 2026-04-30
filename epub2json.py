#!/usr/bin/env python3
"""Convert an EPUB file to the Playdate Reader JSON format.

Usage:
    python3 epub2json.py book.epub              # writes book.json next to the epub
    python3 epub2json.py book.epub output.json   # writes to a specific path
"""

import json
import re
import sys
import warnings

import ebooklib
from ebooklib import epub
from bs4 import BeautifulSoup, XMLParsedAsHTMLWarning

warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)
warnings.filterwarnings("ignore", category=UserWarning, module="ebooklib")

SKIP_IDS = {"cvi", "exlibrispage", "tp", "cop", "ded", "toc", "BooXtream"}
SKIP_TITLES = {"contents", "cover", "title page", "copyright", "disclaimer"}

MIN_CHAPTER_LENGTH = 200

UNICODE_REPLACEMENTS = {
    "“": '"',    # left double curly quote
    "”": '"',    # right double curly quote
    "‘": "'",    # left single curly quote
    "’": "'",    # right single curly quote
    "—": "--",   # em-dash
    "–": "-",    # en-dash
    "…": "...",  # ellipsis
    " ": " ",    # non-breaking space
    "†": "*",    # dagger
    "‡": "**",   # double dagger
    "«": "<<",   # left guillemet
    "»": ">>",   # right guillemet
    "•": "-",    # bullet
}


def sanitize_for_playdate(text):
    for char, replacement in UNICODE_REPLACEMENTS.items():
        text = text.replace(char, replacement)
    # Replace any remaining non-ASCII with '?'
    return text.encode("ascii", errors="replace").decode("ascii")


def extract_text(html_content):
    soup = BeautifulSoup(html_content, "lxml")
    body = soup.find("body")
    if not body:
        return "", None

    title_tag = body.find(["h1", "h2", "h3"])
    title = title_tag.get_text(strip=True) if title_tag else None

    paragraphs = []
    for el in body.find_all(["p", "h1", "h2", "h3", "h4", "h5", "h6"]):
        text = " ".join(el.get_text(separator=" ").split())
        if text:
            paragraphs.append(text)

    return "\n\n".join(paragraphs), title


def format_chapter_title(raw_title):
    if not raw_title:
        return None
    raw_title = raw_title.strip()
    parts = re.split(r"(\d+)", raw_title, maxsplit=1)
    if len(parts) == 3:
        label, number, rest = parts
        label = label.strip().rstrip("-").strip()
        rest = rest.strip().lstrip("-").strip()
        if label.lower() in ("chapter", "ch", ""):
            result = f"Chapter {number}"
        else:
            result = f"{label.title()} {number}"
        if rest:
            result += f": {rest}"
        return result
    return raw_title.title()


def convert_epub(epub_path):
    book = epub.read_epub(epub_path)

    title_meta = book.get_metadata("DC", "title")
    title = title_meta[0][0] if title_meta else "Unknown Title"

    author_meta = book.get_metadata("DC", "creator")
    author = author_meta[0][0] if author_meta else None

    chapters = []
    spine_ids = [item_id for item_id, _ in book.spine]

    for item_id in spine_ids:
        if item_id in SKIP_IDS:
            continue

        item = book.get_item_with_id(item_id)
        if not item:
            continue

        text, raw_title = extract_text(item.get_content())
        if not text or len(text) < MIN_CHAPTER_LENGTH:
            continue

        if raw_title and raw_title.lower() in SKIP_TITLES:
            continue

        ch_title = format_chapter_title(raw_title) or f"Chapter {len(chapters) + 1}"
        chapters.append({
            "title": sanitize_for_playdate(ch_title),
            "text": sanitize_for_playdate(text),
        })

    return {
        "title": sanitize_for_playdate(title),
        "author": sanitize_for_playdate(author) if author else None,
        "chapters": chapters,
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        sys.exit(1)

    epub_path = sys.argv[1]
    if len(sys.argv) >= 3:
        out_path = sys.argv[2]
    else:
        out_path = re.sub(r"\.epub$", ".json", epub_path, flags=re.IGNORECASE)
        if out_path == epub_path:
            out_path = epub_path + ".json"

    result = convert_epub(epub_path)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"Title:    {result['title']}")
    if result["author"]:
        print(f"Author:   {result['author']}")
    print(f"Chapters: {len(result['chapters'])}")
    total_chars = sum(len(ch["text"]) for ch in result["chapters"])
    print(f"Total:    {total_chars:,} characters")
    print(f"Output:   {out_path}")


if __name__ == "__main__":
    main()
