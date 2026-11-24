#!/usr/bin/env python3
"""Fetch every feed in feeds.json concurrently and print merged headlines as JSON."""
import html, json, os, re, subprocess, sys, time, urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.expanduser("~/.cache/milk-news/items.json")
OG_CACHE = os.path.expanduser("~/.cache/milk-news/og.json")
UA = "Mozilla/5.0 (X11; Linux x86_64) milk-news/1.0"


def local(tag):
    return tag.rsplit("}", 1)[-1]


def parse_time(text):
    if not text:
        return 0
    text = text.strip()
    try:
        return parsedate_to_datetime(text).timestamp()
    except Exception:
        pass
    try:
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except Exception:
        return 0


def clean(text):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", text or ""))).strip()


TOPICS = [  # first match wins; falls back to the feed category
    ("🔒", r"vulnerabilit|zero-day|\bcve-|breach|\bhack(ed|ers?|ing)?\b|ransomware|malware|exploit|cyberattack|leak"),
    ("🤖", r"\bai\b|openai|anthropic|claude|chatgpt|gemini|llm|nvidia|artificial intelligence"),
    ("⚔️", r"\bwar\b|missile|airstrike|air strike|troops|invasion|invade|offensive|drone strike|frontline|military|ceasefire|hostage|hamas|hezbollah|houthi|idf|ukrain|russia|gaza|israel|iran|taiwan|nato|navy|army|bomb|shelling|rebels|\bstrikes?\b"),
    ("🌪️", r"earthquake|hurricane|typhoon|storm|flood|wildfire|tsunami|volcano|tornado|heatwave|drought|cyclone"),
    ("✊", r"protest|demonstrat|riot|rally|unrest|strike action"),
    ("🏛️", r"election|vote|parliament|congress|senate|president|prime minister|minister|government|tariff|sanction|court|trump|biden|summit|treaty|g20|\bun\b"),
    ("🛢️", r"\boil\b|opec|natural gas|crude|energy prices"),
    ("📈", r"stock|shares|market|wall street|nasdaq|s&p|dow\b|fed\b|inflation|interest rate|economy|gdp|earnings|bond|dollar|bitcoin|crypto|recession|jobs report"),
    ("🚀", r"\bspace|nasa|spacex|rocket|satellite|moon|mars\b|launch"),
    ("🩺", r"health|virus|outbreak|vaccine|disease|hospital|cancer|pandemic|ebola|measles|covid"),
    ("🐧", r"linux|kernel|arch\b|hyprland|omarchy|wayland|systemd|gnome|kde|mesa|btrfs|rust for linux|distro"),
    ("📦", r"release|v\d+\.\d+"),
    ("💻", r"software|chip|cpu|gpu|apple|google|microsoft|meta\b|amazon|startup|app\b|iphone|android|windows|open source"),
]
CATEGORY_EMOJI = {"World": "🌍", "Geo": "🌐", "Tech": "💻", "Markets": "📈", "Linux": "🐧"}
SEVERE = r"killed|ebola|explosives?|outbreak|dead\b|deaths?\b|deadly|massacre|explosion|blast|bombing|bombed|attack|invasion|invade|invades|missile|airstrike|nuclear|assassinat|coup|earthquake|tsunami|crash|collapse|plunge|plummet|crisis|devastat|hostages?|casualt|shot|shooting|terror|martial law|declares war|breaking news|zero-day|ransomware|outage"
SERIOUS = r"clash|strike|sanction|protest|ceasefire|troops|emergency|surge|soar|tumble|slump|warns?|threat|arrest|evacuat|riot|fire\b|flood|storm|breach|vulnerab|exploit|recession|tariff|resign|ousted|injur|wounded|talks|escalat|tension|shutdown|layoffs?|fined|lawsuit|ban(s|ned)?\b"
NEW_WAR = r"declares? war|war breaks? out|outbreak of war|launch(es|ed)? (a |an )?(\w+ )?(invasion|offensive|attack|strikes?|airstrikes?|assault)|invad(es|ed|ing)|(air|missile|drone)\s?strikes? (on|against|hit)|strikes? (on|against) (iran|israel|russia|ukraine|venezuela|china|taiwan|north korea|syria|yemen|lebanon|pakistan|india)|opens? fire|retaliat|first strikes?|war on\b|attack(s|ed)? (on )?(iran|israel|ukraine|russia|taiwan)"


def classify(title, cat):
    low = title.lower()
    emoji = CATEGORY_EMOJI.get(cat, "📰")
    for symbol, pattern in TOPICS:
        if re.search(pattern, low):
            emoji = symbol
            break
    score = 2 * len(set(re.findall(SEVERE, low))) + len(set(re.findall(SERIOUS, low)))
    if cat in ("Linux", "Tech"):
        score = score // 2  # tech "attack"/"crash" talk is rarely world-shaking
    fire = 3 if score >= 3 else 2 if score >= 1 else 1
    bomb = bool(re.search(NEW_WAR, low)) and cat in ("World", "Geo")
    if bomb:
        fire = 3
    return emoji, fire, bomb


JUNK = re.compile(r"Article URL:|Comments URL:|appeared first on|^Points:|^Read more", re.I)


def summarize(text, title, limit=150):
    """One plain-text line from a feed description; empty when it only repeats the title."""
    text = clean(text)
    if not text or JUNK.search(text):
        text = re.split(r"\s*The post .*? appeared first on", text)[0] if "appeared first on" in text else ""
    if len(text) < 25 or text.lower().startswith(title.lower()[:40]):
        return ""
    if len(text) > limit:
        text = text[:limit].rsplit(" ", 1)[0].rstrip(",;:.-") + "…"
    return text


def find_image(node):
    best, best_width = None, None
    html_blob = ""
    for child in node.iter():
        name = local(child.tag)
        url, width = None, 0
        if name in ("thumbnail", "content") and child.get("url"):
            kind = (child.get("type") or child.get("medium") or "image").lower()
            if "image" in kind or re.search(r"\.(jpe?g|png|webp)(\?|$)", child.get("url"), re.I):
                url = child.get("url")
                width = int(child.get("width") or 0) if (child.get("width") or "").isdigit() else 0
        elif name == "enclosure" and "image" in (child.get("type") or "") and child.get("url"):
            url = child.get("url")
        elif name in ("description", "summary", "encoded", "content") and child.text:
            html_blob += child.text
        if url:
            distance = abs(width - 300) if width else 150
            if best is None or distance < best_width:
                best, best_width = url, distance
    if not best:
        match = re.search(r'<img[^>]+src=["\']([^"\']+)', html.unescape(html_blob) if "&lt;img" in html_blob else html_blob)
        if match:
            best = match.group(1)
    if best and best.startswith("//"):
        best = "https:" + best
    return best if best and best.startswith("http") else None


def fetch(feed, default_limit):
    req = urllib.request.Request(feed["url"], headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=12) as response:
        root = ET.fromstring(response.read())
    items = []
    for node in root.iter():
        if local(node.tag) not in ("item", "entry"):
            continue
        fields = {}
        for child in node:
            name = local(child.tag)
            if name == "link":
                fields.setdefault("link", child.get("href") or (child.text or "").strip())
            elif name in ("title", "pubDate", "published", "updated", "date", "description", "summary"):
                fields.setdefault(name, child.text)
        title, link = clean(fields.get("title")), fields.get("link")
        if not title or not link:
            continue
        ts = parse_time(fields.get("pubDate") or fields.get("published") or fields.get("updated") or fields.get("date"))
        summary = summarize(fields.get("description") or fields.get("summary"), title) if feed.get("summary", True) else ""
        emoji, fire, bomb = classify(title, feed["cat"])
        items.append({"title": title, "link": link, "source": feed["source"], "cat": feed["cat"], "ts": ts,
                      "emoji": emoji, "fire": fire, "bomb": bomb, "summary": summary, "image": find_image(node)})
    items.sort(key=lambda item: item["ts"], reverse=True)
    return items[: feed.get("perFeed", default_limit)]


OG = re.compile(r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\'][^>]*>', re.I)
OG_URL = re.compile(r'content=["\']([^"\']+)', re.I)


def og_image(link):
    """Article's og:image, for feeds that carry no picture of their own."""
    req = urllib.request.Request(link, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=6) as response:
        head = response.read(150000).decode("utf-8", "ignore")
    for tag in OG.findall(head):
        match = OG_URL.search(tag)
        if match:
            url = html.unescape(match.group(1))
            if url.startswith("//"):
                url = "https:" + url
            return url if url.startswith("http") else None
    return None


def fill_images(items, limit=80):
    try:
        cache = json.load(open(OG_CACHE))
    except Exception:
        cache = {}
    missing = [item for item in items[:limit] if not item["image"] and item["link"] not in cache]

    def look(item):
        try:
            return item["link"], og_image(item["link"])
        except Exception:
            return item["link"], None

    with ThreadPoolExecutor(max_workers=10) as pool:
        for link, url in pool.map(look, missing):
            cache[link] = url
    for item in items:
        if not item["image"]:
            item["image"] = cache.get(item["link"])
    live = {item["link"] for item in items}
    os.makedirs(os.path.dirname(OG_CACHE), exist_ok=True)
    json.dump({k: v for k, v in cache.items() if k in live}, open(OG_CACHE, "w"))


STATE = os.path.expanduser("~/.cache/milk-news/notified.json")


def notify(items):
    """Desktop notification for each new 🔥🔥🔥 / 💣 story. The first run only records what exists."""
    first = not os.path.exists(STATE)
    try:
        seen = set(json.load(open(STATE)))
    except Exception:
        seen = set()
    cutoff = time.time() - 6 * 3600
    fresh = [i for i in items if (i["fire"] >= 3 or i["bomb"]) and i["link"] not in seen]
    for item in ([] if first else sorted(fresh, key=lambda i: i["ts"])[:5]):
        if item["ts"] and item["ts"] < cutoff:
            continue
        icon = fetch_icon(item.get("image"))
        title = ("💣 " if item["bomb"] else "") + "🔥🔥🔥  " + item["source"]
        body = item["emoji"] + " " + item["title"] + ("\n" + item["summary"] if item.get("summary") else "")
        cmd = ["notify-send", "-a", "News", "-u", "critical" if item["bomb"] else "normal", "-t", "20000"]
        if icon:
            cmd += ["-i", icon]
        try:
            subprocess.run(cmd + [title, body], timeout=5)
        except Exception:
            pass
    seen = (seen & {i["link"] for i in items}) | {i["link"] for i in (items if first else fresh)}
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    json.dump(sorted(seen), open(STATE, "w"))


def fetch_icon(url):
    if not url:
        return None
    path = os.path.expanduser("~/.cache/milk-news/icon-%x.img" % (hash(url) & 0xFFFFFFFF))
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=6) as response:
            open(path, "wb").write(response.read(2_000_000))
        return path
    except Exception:
        return None


def main():
    config = json.load(open(os.path.join(HERE, "feeds.json")))
    limit = config.get("perFeed", 12)
    items, failed = [], []

    def run(feed):
        try:
            return feed, fetch(feed, limit), None
        except Exception as error:
            return feed, [], str(error)

    with ThreadPoolExecutor(max_workers=8) as pool:
        for feed, got, error in pool.map(run, config["feeds"]):
            items += got
            if error:
                failed.append(feed["source"])
    seen, unique = set(), []
    for item in sorted(items, key=lambda item: item["ts"], reverse=True):
        if item["link"] not in seen:
            seen.add(item["link"])
            unique.append(item)
    fill_images(unique)
    notify(unique)
    out = {"updated": time.time(), "failed": failed, "items": unique}
    if unique:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        json.dump(out, open(CACHE, "w"))
    elif os.path.exists(CACHE):  # offline: serve the last good fetch
        out = json.load(open(CACHE))
        out["failed"] = ["offline"]
    json.dump(out, sys.stdout)


main()
