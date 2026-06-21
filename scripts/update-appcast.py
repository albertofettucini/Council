#!/usr/bin/env python3
"""Prepend a new release <item> to Council's Sparkle appcast (appcast.xml).

Council serves its appcast from the repo itself (SUFeedURL =
raw.githubusercontent.com/albertofettucini/Council/main/appcast.xml), so the release workflow runs
this, then commits appcast.xml back to main.

`sparkle:version` (= the app's CFBundleVersion, which Sparkle compares to decide "is this newer?") is
derived from the marketing version as major*10000 + minor*100 + patch — strictly monotonic, and larger
than the old hand-written values (1.1.2 -> 10102 > 112), so existing users still get the update. The
EdDSA signature + byte length come from Sparkle's `sign_update` (run in the workflow).

Usage:
  update-appcast.py --version 1.1.3 --sparkle-version 10103 --min-os 14.0 \
    --url https://github.com/albertofettucini/Council/releases/download/v1.1.3/Council-1.1.3-macOS.zip \
    --signature 'BASE64==' --length 1234567 --appcast appcast.xml
"""

import argparse
import sys
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape, quoteattr

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
HEADER_COMMENT = (
    " Sparkle appcast for Council. Releases are produced by .github/workflows/release.yml\n"
    "     (push a vX.Y.Z tag); this file is regenerated and committed back to main each release.\n"
    "     Newest item first. No double hyphens inside this comment, XML forbids them. "
)


def s(el):
    return el.text.strip() if el is not None and el.text else ""


def parse_items(path):
    """Read existing <item>s into dicts, or [] if the file is missing/unreadable."""
    try:
        tree = ET.parse(path)
    except (ET.ParseError, FileNotFoundError, OSError) as e:
        print(f"update-appcast: no usable existing appcast ({e}); starting fresh", file=sys.stderr)
        return []
    channel = tree.getroot().find("channel")
    if channel is None:
        return []
    out = []
    for it in channel.findall("item"):
        enc = it.find("enclosure")
        out.append({
            "version": s(it.find("title")),
            "sparkle_version": s(it.find(f"{{{SPARKLE}}}version")),
            "short": s(it.find(f"{{{SPARKLE}}}shortVersionString")),
            "min_os": s(it.find(f"{{{SPARKLE}}}minimumSystemVersion")),
            "link": s(it.find("link")),
            "url": (enc.get("url") if enc is not None else "") or "",
            "signature": (enc.get(f"{{{SPARKLE}}}edSignature") if enc is not None else "") or "",
            "length": (enc.get("length") if enc is not None else "0") or "0",
        })
    return out


def render_item(it):
    return (
        "    <item>\n"
        f"      <title>{escape(it['version'])}</title>\n"
        f"      <sparkle:version>{escape(str(it['sparkle_version']))}</sparkle:version>\n"
        f"      <sparkle:shortVersionString>{escape(it['short'])}</sparkle:shortVersionString>\n"
        f"      <sparkle:minimumSystemVersion>{escape(it['min_os'])}</sparkle:minimumSystemVersion>\n"
        f"      <link>{escape(it['link'])}</link>\n"
        "      <enclosure\n"
        f"        url={quoteattr(it['url'])}\n"
        f"        sparkle:edSignature={quoteattr(it['signature'])}\n"
        f"        length={quoteattr(str(it['length']))}\n"
        '        type="application/octet-stream"/>\n'
        "    </item>"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--sparkle-version", required=True)
    ap.add_argument("--min-os", default="14.0")
    ap.add_argument("--url", required=True)
    ap.add_argument("--signature", required=True)
    ap.add_argument("--length", required=True)
    ap.add_argument("--appcast", default="appcast.xml")
    a = ap.parse_args()

    new = {
        "version": a.version,
        "sparkle_version": a.sparkle_version,
        "short": a.version,
        "min_os": a.min_os,
        "link": f"https://github.com/albertofettucini/Council/releases/tag/v{a.version}",
        "url": a.url,
        "signature": a.signature,
        "length": a.length,
    }

    # Keep history; drop any prior item for the SAME version so re-running a tag is idempotent.
    items = [it for it in parse_items(a.appcast) if it["short"] != a.version]
    items = [new] + items

    body = "\n".join(render_item(it) for it in items)
    doc = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f"<!--{HEADER_COMMENT}-->\n"
        f'<rss version="2.0" xmlns:sparkle="{SPARKLE}">\n'
        "  <channel>\n"
        "    <title>Council</title>\n"
        f"{body}\n"
        "  </channel>\n"
        "</rss>\n"
    )
    with open(a.appcast, "w", encoding="utf-8") as f:
        f.write(doc)
    print(f"update-appcast: wrote {a.appcast} with {len(items)} item(s) "
          f"(newest: {a.version} / sparkle:version {a.sparkle_version})", file=sys.stderr)


if __name__ == "__main__":
    main()
