"""milk.telegram backend.

  tg.py setup    one-time interactive login (run in a terminal)
  tg.py daemon   live: prints one JSON line per snapshot / chat history; reads JSON commands on stdin
  tg.py open <username-or-id>   open that chat in Telegram Desktop

stdin commands (one JSON object per line):
  {"cmd":"watch","id":123}            show chat 123: emits its history, keeps it fresh, marks it read
  {"cmd":"watch","id":null}           stop watching
  {"cmd":"send","id":123,"text":"hi"} send a message the user typed (the ONLY thing that ever sends)
  {"cmd":"audio","id":123,"msg":45}   download that voice message to the cache; emits its file path

Uses the user's own login on their own folder (default "Hermes"). Nothing is sent unless the user
typed it and pressed Send; chats are marked read only while the user has that chat open in the widget.
Secrets: ~/.config/omarchy/credentials/telegram-api.json and the session file, both 0600.
"""
import asyncio
import configparser
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
CRED = HOME / ".config/omarchy/credentials/telegram-api.json"
SESSION = HOME / ".local/share/milk-telegram/session"
CACHE = HOME / ".cache/milk-telegram/state.json"
AVATARS = HOME / ".cache/milk-telegram/avatars"
AUDIO = HOME / ".cache/milk-telegram/audio"
FOLDER = os.environ.get("MILK_TELEGRAM_FOLDER", "Hermes").strip().lower()


def load_cred():
    try:
        d = json.loads(CRED.read_text())
        return int(d["api_id"]), str(d["api_hash"])
    except (OSError, ValueError, KeyError):
        return None


def secure(path):
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def setup():
    from telethon.sync import TelegramClient
    print("Telegram login for the milk widget (read-only).\n"
          "Get api_id and api_hash at https://my.telegram.org -> API development tools.\n")
    cred = load_cred()
    if not cred:
        api_id = int(input("api_id: ").strip())
        import getpass
        api_hash = getpass.getpass("api_hash (hidden): ").strip()
        CRED.parent.mkdir(parents=True, exist_ok=True)
        CRED.write_text(json.dumps({"api_id": api_id, "api_hash": api_hash}))
        secure(CRED)
        cred = (api_id, api_hash)
    SESSION.parent.mkdir(parents=True, exist_ok=True)
    with TelegramClient(str(SESSION), *cred) as client:   # prompts for phone, code, 2FA
        me = client.get_me()
        print("\nLogged in as", me.first_name, "- done. You can close this window.")
    secure(str(SESSION) + ".session")


def folder_title(f):
    t = getattr(f, "title", None)
    return str(getattr(t, "text", t) or "")


def voice_info(msg):
    """(is_voice_or_audio, seconds) for a message."""
    if msg is None or not (msg.voice or msg.audio):
        return False, 0
    return True, int(getattr(msg.file, "duration", 0) or 0)


def preview(msg, limit=300, flat=True):
    if msg is None:
        return ""
    text = (msg.message or "").strip()
    if flat:
        text = text.replace("\n", " ")
    if text:
        return text[:limit]
    if msg.photo:
        return "[photo]"
    if msg.voice:
        return "[voice message]"
    if msg.document:
        return "[file]"
    if msg.media:
        return "[media]"
    return "[message]"


async def avatar(client, ent, did):
    """Cached profile photo path ('' if none). File name carries the photo id, so a new photo is re-downloaded."""
    photo = getattr(ent, "photo", None)
    pid = getattr(photo, "photo_id", None)
    if not pid:
        return ""
    path = AVATARS / f"{did}-{pid}.jpg"
    if not path.exists():
        try:
            AVATARS.mkdir(parents=True, exist_ok=True)
            got = await client.download_profile_photo(ent, file=str(path), download_big=False)
            if not got:
                return ""
        except Exception:
            return ""
    return str(path)


async def snapshot(client, errors=None):
    from telethon.tl.functions.messages import GetDialogFiltersRequest
    from telethon import utils
    res = await client(GetDialogFiltersRequest())
    filters = getattr(res, "filters", res)
    folder = None
    names = []
    for f in filters:
        title = folder_title(f)
        if title:
            names.append(title)
        if title.strip().lower() == FOLDER:
            folder = f
    if folder is None:
        return {"ok": False, "error": "no_folder", "folders": names, "updated": time.time()}
    include = {utils.get_peer_id(p) for p in list(folder.include_peers) + list(folder.pinned_peers)}
    exclude = {utils.get_peer_id(p) for p in folder.exclude_peers}
    chats = []
    async for d in client.iter_dialogs(limit=400):
        ent, did = d.entity, d.id
        if did in exclude:
            continue
        bot = bool(getattr(ent, "bot", False))
        user = d.is_user and not bot
        hit = (did in include
               or (getattr(folder, "bots", False) and bot)
               or (getattr(folder, "contacts", False) and user and getattr(ent, "contact", False))
               or (getattr(folder, "non_contacts", False) and user and not getattr(ent, "contact", False))
               or (getattr(folder, "groups", False) and d.is_group)
               or (getattr(folder, "broadcasts", False) and d.is_channel and not d.is_group))
        if not hit:
            continue
        if getattr(folder, "exclude_read", False) and not d.unread_count:
            continue
        m = d.message
        username = getattr(ent, "username", None)
        chats.append({
            "id": did,
            "name": utils.get_display_name(ent) or "Unknown",
            "username": username or "",
            "bot": bot,
            "text": preview(m),
            "out": bool(m.out) if m else False,
            "date": m.date.timestamp() if m and m.date else 0,
            "unread": d.unread_count,
            "pinned": bool(d.pinned),
            "mid": m.id if m else 0,
            "voice": voice_info(m)[0],
            "dur": voice_info(m)[1],
            "avatar": await avatar(client, ent, did),
        })
    chats.sort(key=lambda c: -c["date"])
    return {"ok": True, "folder": folder_title(folder), "chats": chats, "updated": time.time()}


async def history(client, chat_id):
    ent = await client.get_input_entity(chat_id)
    msgs = await client.get_messages(ent, limit=40)
    out = []
    for m in reversed(msgs):
        out.append({"id": m.id, "out": bool(m.out), "date": m.date.timestamp() if m.date else 0,
                    "text": preview(m, 4000, flat=False),
                    "voice": voice_info(m)[0], "dur": voice_info(m)[1]})
    return {"kind": "history", "id": chat_id, "messages": out, "updated": time.time()}


async def daemon():
    from telethon import TelegramClient, events
    cred = load_cred()
    if not cred or not Path(str(SESSION) + ".session").exists():
        emit({"ok": False, "error": "needs_login", "updated": time.time()})
        return 0
    client = TelegramClient(str(SESSION), *cred, receive_updates=True)
    await client.connect()
    if not await client.is_user_authorized():
        emit({"ok": False, "error": "needs_login", "updated": time.time()})
        return 0
    dirty = asyncio.Event()
    dirty.set()
    state = {"watch": None, "hist": ""}

    @client.on(events.UserUpdate)
    async def _typing(event):   # "typing…" / "recording…" from a bot while it works on a reply
        try:
            if event.typing or event.uploading or event.recording:
                emit({"kind": "typing", "id": event.chat_id, "on": True})
            elif event.cancel:
                emit({"kind": "typing", "id": event.chat_id, "on": False})
        except Exception:
            pass

    @client.on(events.NewMessage)
    @client.on(events.MessageRead)
    @client.on(events.MessageDeleted)
    @client.on(events.MessageEdited)
    async def _(event):
        dirty.set()

    async def push_history(mark_read):
        cid = state["watch"]
        if cid is None:
            return
        try:
            h = await history(client, cid)
            key = json.dumps(h["messages"], sort_keys=True)
            if key != state["hist"]:
                state["hist"] = key
                emit(h)
            if mark_read:
                await client.send_read_acknowledge(await client.get_input_entity(cid))
        except Exception as exc:
            emit({"kind": "error", "what": "history", "detail": type(exc).__name__})

    async def fetch_audio(cid, mid):
        """Download one voice message to the cache (once) and tell the widget where it is."""
        try:
            path = AUDIO / f"{cid}-{mid}.ogg"
            if not path.exists():
                AUDIO.mkdir(parents=True, exist_ok=True)
                ent = await client.get_input_entity(cid)
                msg = await client.get_messages(ent, ids=mid)
                got = await client.download_media(msg, file=str(path))
                if not got:
                    raise RuntimeError("no media")
            emit({"kind": "audio", "id": cid, "msg": mid, "path": str(path)})
        except Exception as exc:
            emit({"kind": "error", "what": "audio", "id": cid, "msg": mid, "detail": type(exc).__name__})

    async def commands():
        loop = asyncio.get_running_loop()
        reader = asyncio.StreamReader()
        try:
            await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
        except (OSError, ValueError):
            return   # no command pipe (run by hand): read-only snapshots still work
        while True:
            line = await reader.readline()
            if not line:
                return
            try:
                c = json.loads(line)
            except ValueError:
                continue
            if c.get("cmd") == "watch":
                state["watch"], state["hist"] = c.get("id"), ""
                await push_history(True)
                dirty.set()
            elif c.get("cmd") == "audio":
                asyncio.create_task(fetch_audio(c.get("id"), c.get("msg")))
            elif c.get("cmd") == "send" and str(c.get("text", "")).strip():
                try:
                    await client.send_message(await client.get_input_entity(c["id"]), str(c["text"]))
                    emit({"kind": "sent", "id": c["id"]})
                except Exception as exc:
                    emit({"kind": "error", "what": "send", "id": c.get("id"), "detail": type(exc).__name__})
                await push_history(True)
                dirty.set()

    cmd_task = asyncio.create_task(commands())
    last = ""
    last_beat = 0.0
    while True:
        try:
            await asyncio.wait_for(dirty.wait(), timeout=120)   # also re-checks every 2 min as a safety net
        except asyncio.TimeoutError:
            pass
        dirty.clear()
        await asyncio.sleep(0.4)   # coalesce bursts
        dirty.clear()
        try:
            snap = await snapshot(client)
            await push_history(True)
        except Exception as exc:   # network drop etc: tell the widget, then let it restart us
            emit({"ok": False, "error": "offline", "detail": type(exc).__name__, "updated": time.time()})
            cmd_task.cancel()
            return 1
        key = json.dumps(snap.get("chats"), sort_keys=True) + str(snap.get("error"))
        if key != last or time.time() - last_beat > 110:
            last, last_beat = key, time.time()
            try:
                CACHE.parent.mkdir(parents=True, exist_ok=True)
                CACHE.write_text(json.dumps(snap, ensure_ascii=False))
            except OSError:
                pass
            emit(snap)


def telegram_cmd():
    for exe in ("telegram-desktop", "Telegram", "telegram"):
        if found := shutil.which(exe):
            return [found]
    roots = [HOME / ".local/share/applications", Path("/usr/share/applications")]
    for root in roots:
        for entry in sorted(root.glob("*elegram*.desktop")):
            cp = configparser.ConfigParser(interpolation=None)
            try:
                cp.read(entry)
                args = [a for a in shlex.split(cp["Desktop Entry"]["Exec"]) if not a.startswith("%")]
                if args and (os.access(args[0], os.X_OK) or shutil.which(args[0])):
                    return [a for a in args if a != "--"]
            except (OSError, ValueError, KeyError, configparser.Error):
                continue
    return None


def open_chat(arg):
    arg = arg.strip().lstrip("@")
    if arg.isdigit() or (arg.startswith("-") and arg[1:].isdigit()):
        url = "tg://user?id=" + arg
    elif arg:
        url = "tg://resolve?domain=" + arg
    else:
        url = ""
    cmd = telegram_cmd()
    if cmd:
        subprocess.Popen(cmd + (["--", url] if url else []), start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        web = "https://t.me/" + arg if arg and not arg.isdigit() else "https://web.telegram.org/a/"
        subprocess.Popen(["xdg-open", web], start_new_session=True)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "setup":
        setup()
    elif mode == "daemon":
        sys.exit(asyncio.run(daemon()) or 0)
    elif mode == "open":
        open_chat(sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        print(__doc__)
