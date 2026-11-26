"""StageView: Videoseiten für Kunden auf videos.stagecraft.media (Befehl `stageview` auf VPS 2).

Ein Projekt ist ein Link wie ein Pixieset Link: Übersicht mit allen Videos, pro Video eine Seite mit Player,
Kommentaren an der Stelle im Video, Status Freigabe und Download. Videos liegen im Google Drive, abgespielt wird
über Mux (Mux holt das Original selbst aus dem Drive, passthrough "drive:<id>").

Läuft nur auf VPS 2 als Linux User hermes, schreibt direkt nach /var/www/videos (nginx). TESS, Alfred und
Claude Code (per ssh) nutzen denselben Befehl. Alles Wichtige steht in der SKILL.md daneben.

Daten (nur auf VPS 2, ~/.hermes/data/stageview/):
  projekte/<schluessel>.json  ein Projekt (titel, kunde, firma, kunde_ordner, dreh, hinweis, videos), seit 22.11.2026 dazu
                              quellen (gewählte Drive Ordner), drive_weg (nicht mehr im Drive, ausgeblendet) und entfernt
                              (von Hand von der Seite genommen, kommt nie von selbst zurück). Jedes Video merkt seinen Ordner, seit 25.11.2026 auch
                              datei (Name im Drive), md5 (Prüfsumme der Fassung bei Mux), vorher (frühere Drive Dateien nach
                              einer neuen Fassung) und fassung_offen (Mux Asset der neuen Fassung, solange es noch läuft)
  codes.json                  schluessel → Code des Links (6 Zeichen, ersetzt das Passwort, ändert sich nie)
  nummern.json                pro Code: Video → feste Nummer für /<code>/<nr> (wird nie neu vergeben)
Schlüssel: Mux in ~/.hermes/stageview.env (MUX_TOKEN_ID, MUX_TOKEN_SECRET), Team Schlüssel für Kommentare in
~/.hermes/videos-api.env. Google Drive über das Konto des Agents ($HERMES_HOME/google_token.json).
"""
import argparse
import base64
import fcntl
import hashlib
import html
import json
import math
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HIER = Path(__file__).resolve().parent
SEITE = HIER / "seite"
HAUS = Path("/home/hermes/.hermes") if Path("/home/hermes/.hermes").exists() else Path.home() / ".hermes"
DATEN = Path(os.environ.get("STAGEVIEW_DATEN", HAUS / "data" / "stageview"))
WEB = Path(os.environ.get("STAGEVIEW_WEB", "/var/www/videos"))
OS_PFAD = Path(os.environ.get("STAGEVIEW_OS", Path.home() / "workspace" / "stagecraft-os"))
SKILLS = OS_PFAD / "plugins" / "stagecraft-team" / "skills"
API = os.environ.get("STAGEVIEW_API", "http://127.0.0.1:8652/api")
BASIS_URL = "https://videos.stagecraft.media"
DRIVE_DL = "https://drive.usercontent.google.com/download?id={}&export=download&confirm=t"
LOGO_VORSCHAU = "vorschau-stagecraft.png"
# Tab Icon und App Icon (seit 16.11.2026, Ole wählte Entwurf 02.04: das Stagecraft A als Play Pfeil auf Waldgrün im Verlauf)
ICON_DATEIEN = ("icon.svg", "icon-32.png", "apple-touch-icon.png", "favicon.ico")


def icon_kopf():
    """Link Zeilen für Tab Icon und App Icon, mit Stand im Link, damit ein neues Icon sofort ankommt."""
    v = hashlib.sha1((SEITE / "icon.svg").read_bytes()).hexdigest()[:8]
    return "\n".join([f'<link rel="icon" href="/favicon.ico?v={v}" sizes="32x32">',
                      f'<link rel="icon" href="/icon.svg?v={v}" type="image/svg+xml">',
                      f'<link rel="apple-touch-icon" href="/apple-touch-icon.png?v={v}">'])
VIDEO_ENDUNGEN = (".mp4", ".mov", ".m4v", ".webm")


# ---------------------------------------------------------------- kleine Helfer
def fehler(text, code=1):
    print(f"FEHLER: {text}", file=sys.stderr)
    sys.exit(code)


def lesen_json(pfad, standard):
    try:
        return json.loads(Path(pfad).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return standard


def schreiben(pfad, inhalt):
    """Atomar schreiben (erst Hilfsdatei, dann umbenennen), damit nginx nie eine halbe Datei ausliefert."""
    pfad = Path(pfad)
    pfad.parent.mkdir(parents=True, exist_ok=True)
    tmp = pfad.with_name(f".{pfad.name}.{os.getpid()}.tmp")
    if isinstance(inhalt, bytes):
        tmp.write_bytes(inhalt)
    else:
        tmp.write_text(inhalt, encoding="utf-8")
    os.replace(tmp, pfad)
    # Webdateien immer für nginx lesbar, egal welche umask die Shell hat (14.11.2026: mit umask 077 lieferten alle Seiten 403)
    if str(pfad).startswith(str(WEB)):
        os.chmod(pfad, 0o644)
        ordner = pfad.parent
        while str(ordner).startswith(str(WEB)) and ordner != WEB.parent:
            os.chmod(ordner, 0o755)
            if ordner == WEB:
                break
            ordner = ordner.parent


def schreiben_json(pfad, daten):
    schreiben(pfad, json.dumps(daten, ensure_ascii=False, indent=2) + "\n")


class Sperre:
    """Nur ein stageview gleichzeitig ändert Daten und Seiten (TESS, Alfred und Claude können parallel laufen)."""
    def __enter__(self):
        DATEN.mkdir(parents=True, exist_ok=True)
        self.f = open(DATEN / ".sperre", "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def slug(text):
    t = (text or "").lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")


def drive_id(text):
    """Drive ID aus Link oder ID."""
    text = (text or "").strip()
    m = re.search(r"/(?:d|folders)/([A-Za-z0-9_-]{15,})", text) or re.search(r"[?&]id=([A-Za-z0-9_-]{15,})", text)
    if m:
        return m.group(1)
    if re.fullmatch(r"[A-Za-z0-9_-]{15,}", text):
        return text
    fehler(f"keine Drive ID erkannt: {text}")


def env_datei(pfad):
    werte = {}
    try:
        for zeile in Path(pfad).read_text().splitlines():
            if "=" in zeile and not zeile.strip().startswith("#"):
                k, v = zeile.split("=", 1)
                werte[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return werte


def dauer_text(s):
    s = int(round(s or 0))
    return f"{s // 60}:{s % 60:02d}"


def mb(b):
    if not b:
        return ""
    return f"{b / 1e9:.1f} GB".replace(".", ",") if b >= 1e9 else f"{round(b / 1e6)} MB"


# ---------------------------------------------------------------- Mux
def mux_schluessel():
    env = {**env_datei(HAUS / "stageview.env"), **{k: os.environ[k] for k in ("MUX_TOKEN_ID", "MUX_TOKEN_SECRET") if os.environ.get(k)}}
    if not env.get("MUX_TOKEN_ID") or not env.get("MUX_TOKEN_SECRET"):
        fehler("Mux Schlüssel fehlt (~/.hermes/stageview.env mit MUX_TOKEN_ID und MUX_TOKEN_SECRET)")
    return base64.b64encode(f"{env['MUX_TOKEN_ID']}:{env['MUX_TOKEN_SECRET']}".encode()).decode()


def mux(pfad, methode="GET", daten=None):
    req = urllib.request.Request("https://api.mux.com" + pfad, method=methode,
                                 data=json.dumps(daten).encode() if daten is not None else None,
                                 headers={"Authorization": "Basic " + mux_schluessel(), "Content-Type": "application/json"})
    try:
        body = urllib.request.urlopen(req, timeout=40).read()
        return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as e:
        fehler(f"Mux {methode} {pfad}: {e.code} {e.read().decode()[:300]}")


def asset_rang(a):
    """Fertig vor in Arbeit, dann das neueste. Seit 25.11.2026 ohne Stufe: eine neue Fassung aus dem Drive gewinnt auch in 1080p
    gegen eine ältere 4K Fassung. Hochstufen auf 4K bleibt gleich, die 4K Fassung ist dort immer die neuere."""
    return (a.get("status") == "ready", int(a.get("created_at") or 0))


def mux_assets(alle=False):
    """Alle Mux Assets, nach Drive ID (passthrough drive:<id>). Gibt es mehrere zu einem Video (4K nach dem Umstieg, neue Fassung),
    gilt das beste nach asset_rang. alle=True: pro Drive ID die ganze Liste, das beste zuerst."""
    seite, karte = 1, {}
    while True:
        daten = mux(f"/video/v1/assets?limit=100&page={seite}")["data"]
        for a in daten:
            p = str(a.get("passthrough") or "")
            if p.startswith("drive:"):
                karte.setdefault(p[6:], []).append(a)
        if len(daten) < 100:
            break
        seite += 1
    for liste in karte.values():
        liste.sort(key=asset_rang, reverse=True)
    return karte if alle else {k: v[0] for k, v in karte.items()}


def mux_anlegen(did):
    """Mux holt das Original selbst aus dem Drive (Datei muss per Link freigegeben sein).
    Seit 14.11.2026 bis 4K (Ole: höhere Qualitätsstufen anbieten). Mux kodiert nie über das Original hinaus, Basic bleibt ohne Kodierkosten,
    Speicher und Auslieferung werden nach der echten Auflösung abgerechnet. Der Player wählt automatisch nur so viel, wie in die Fläche passt"""
    body = {"inputs": [{"url": DRIVE_DL.format(did)}], "playback_policies": ["public"], "video_quality": "basic",
            "max_resolution_tier": "2160p", "passthrough": "drive:" + did}
    return mux("/video/v1/assets", "POST", body)["data"]


# ---------------------------------------------------------------- Lippensynchron (seit 16.11.2026)
# Ole: „die Tonspur ist komplett versetzt“ (Clemens, Diener statt CEO). Gemessen: Mux ignoriert Edit Lists in MP4/MOV. Exporte aus
# DaVinci Resolve (H.264) verschieben das Bild per Edit List um 0,2 s (Media Time 2560 bei 1/12800) und den Ton um 2112 Samples.
# Bei Mux lag das Bild dadurch 0,22 s zu spät, der Ton 0,04 s, also rund 0,18 s auseinander, an jedem Schnitt gleich. Bereinigt
# (ffmpeg ohne Neukodieren, Edit List in die Zeitstempel übernommen, -use_editlist 0) lagen Bild und Ton bei Mux 0,006 s auseinander.
# Darum: vor jedem Upload nur den Kopf der Datei lesen, und wenn die Edit Lists Bild und Ton um mehr als 40 ms verschieben,
# die Datei auf VPS 2 laden, bereinigen und direkt zu Mux hochladen (passthrough bleibt drive:<id>, die Seite merkt keinen Unterschied).
VERSATZ_GRENZE = 0.04


def edit_versatz(did):
    """Sekunden, um die Edit Lists das Bild gegenüber dem Ton verschieben (0, wenn keine). Liest per ffprobe nur den Dateikopf."""
    url = f"https://www.googleapis.com/drive/v3/files/{did}?alt=media&supportsAllDrives=true"
    r = subprocess.run(["ffprobe", "-v", "trace", "-headers", f"Authorization: Bearer {drive_token()}\r\n",
                        "-show_entries", "stream=index,codec_type,time_base", "-of", "json", url],
                       capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        raise RuntimeError("ffprobe: " + (r.stderr.strip().splitlines() or ["?"])[-1][:200])
    arten = {s["index"]: (s["codec_type"], s.get("time_base", "1/1")) for s in json.loads(r.stdout or "{}").get("streams", [])}
    versatz = {}
    for m in re.finditer(r"Processing st: (\d+), edit list \d+ - media time: (-?\d+)", r.stderr):
        art, tb = arten.get(int(m.group(1)), (None, "1/1"))
        if art in ("video", "audio") and art not in versatz:
            z, n = tb.split("/")
            versatz[art] = max(0, int(m.group(2))) * int(z) / int(n)
    return round(versatz.get("video", 0) - versatz.get("audio", 0), 3) if "video" in versatz else 0.0


def mux_bereinigt(did):
    """Drive Datei laden, mit ffmpeg ohne Neukodieren neu verpacken (Edit Lists in den Zeitstempeln, keine Edit List mehr) und per
    Direct Upload zu Mux, mit denselben Einstellungen wie mux_anlegen. Die Kopie auf VPS 2 wird danach immer gelöscht."""
    from googleapiclient.http import MediaIoBaseDownload
    ordner = Path(tempfile.mkdtemp(prefix="sv-sync-"))
    try:
        quelle, sauber = ordner / "quelle", ordner / "sauber.mp4"
        with open(quelle, "wb") as f:
            d, fertig = MediaIoBaseDownload(f, drive().files().get_media(fileId=did, supportsAllDrives=True), chunksize=32 * 1024 * 1024), False
            while not fertig:
                _, fertig = d.next_chunk()
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(quelle), "-map", "0:v:0", "-map", "0:a?", "-c", "copy", "-use_editlist", "0",
                            "-movflags", "+faststart+negative_cts_offsets", str(sauber)], capture_output=True, text=True, timeout=1800)
        if r.returncode != 0:
            raise RuntimeError("ffmpeg: " + r.stderr.strip()[-200:])
        quelle.unlink()
        u = mux("/video/v1/uploads", "POST", {"cors_origin": "*", "new_asset_settings": {
            "playback_policies": ["public"], "video_quality": "basic", "max_resolution_tier": "2160p", "passthrough": "drive:" + did}})["data"]
        r = subprocess.run(["curl", "-s", "-f", "-o", "/dev/null", "-X", "PUT", "-T", str(sauber), u["url"]], capture_output=True, text=True, timeout=3600)
        if r.returncode != 0:
            raise RuntimeError("Upload zu Mux fehlgeschlagen")
        for _ in range(60):
            x = mux(f"/video/v1/uploads/{u['id']}")["data"]
            if x.get("asset_id"):
                return mux(f"/video/v1/assets/{x['asset_id']}")["data"]
            time.sleep(2)
        raise RuntimeError("Mux hat aus dem Upload kein Video gemacht")
    finally:
        shutil.rmtree(ordner, ignore_errors=True)


def mux_neu(did, titel=""):
    """Neues Mux Asset für ein Drive Video: normal per Link, bei verschobenen Edit Lists bereinigt (siehe oben)."""
    try:
        v = edit_versatz(did)
    except Exception as e:
        print(f"  Hinweis: Versatz von {titel or did} nicht geprüft ({str(e)[:120]}), geht normal zu Mux", flush=True)
        v = 0.0
    if abs(v) > VERSATZ_GRENZE:
        print(f"  {titel or did}: Bild und Ton per Edit List {v:+.2f} s verschoben, Mux ignoriert das, geht bereinigt zu Mux", flush=True)
        return mux_bereinigt(did)
    return mux_anlegen(did)


def mux_warten(ids, minuten):
    """Wartet, bis die Assets fertig sind. Gibt die noch nicht fertigen zurück."""
    ende = time.time() + minuten * 60
    offen = set(ids)
    while offen and time.time() < ende:
        for i in list(offen):
            a = mux(f"/video/v1/assets/{i}")["data"]
            if a["status"] == "ready":
                offen.discard(i)
                print(f"  Mux fertig: {a.get('passthrough')} ({dauer_text(a.get('duration'))})", flush=True)
            elif a["status"] == "errored":
                offen.discard(i)
                print(f"  Mux FEHLER: {a.get('passthrough')} {(a.get('errors') or {}).get('messages')}", flush=True)
        if offen:
            fort = []
            for i in offen:
                pr = (mux(f"/video/v1/assets/{i}")["data"].get("progress") or {})
                fort.append(f"{pr.get('state', '?')} {pr.get('progress', 0):.0f} %")
            print(f"  warte auf Mux: {', '.join(fort)}", flush=True)
            time.sleep(20)
    return offen


# ---------------------------------------------------------------- Google Drive (Konto des Agents)
_drive = None


def drive():
    global _drive
    if _drive:
        return _drive
    try:
        from google.auth.transport.requests import Request
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build
    except ImportError:
        fehler("Google Bibliotheken fehlen, stageview über den Befehl auf VPS 2 starten (nicht direkt mit python)")
    haus = Path(os.environ.get("HERMES_HOME") or HAUS)
    token = haus / "google_token.json"
    if not token.exists():
        token = HAUS / "google_token.json"
    cr = Credentials.from_authorized_user_file(str(token))
    if not cr.valid:
        cr.refresh(Request())
    _drive = build("drive", "v3", credentials=cr, cache_discovery=False)
    _drive.anmeldung = cr
    return _drive


def drive_token():
    """Zugriffstoken des Agents, z.B. damit ffprobe nur den Kopf einer Drive Datei liest."""
    cr = drive().anmeldung
    if not cr.valid:
        from google.auth.transport.requests import Request
        cr.refresh(Request())
    return cr.token


ALLE = {"supportsAllDrives": True}
FELDER = "id,name,mimeType,size,md5Checksum,createdTime,modifiedTime,parents,driveId,webViewLink,videoMediaMetadata(width,height,durationMillis)"


def drive_datei(did):
    try:
        return drive().files().get(fileId=did, fields=FELDER, **ALLE).execute()
    except Exception as e:  # z.B. falscher Link oder das Konto des Agents sieht die Datei nicht
        if "404" in str(e) or "403" in str(e) or "notFound" in str(e):
            fehler(f"Drive Datei nicht gefunden oder kein Zugriff ({did}). Link prüfen, der Ordner muss für das Google Konto des Agents sichtbar sein")
        raise


def drive_kinder(ordner):
    dateien, token = [], None
    while True:
        r = drive().files().list(q=f"'{ordner}' in parents and trashed = false", fields=f"nextPageToken,files({FELDER})",
                                 includeItemsFromAllDrives=True, supportsAllDrives=True, corpora="allDrives",
                                 orderBy="folder,name", pageSize=200, pageToken=token).execute()
        dateien += r.get("files", [])
        token = r.get("nextPageToken")
        if not token:
            return dateien


def ist_ordner(f):
    return f["mimeType"] == "application/vnd.google-apps.folder"


def ist_video(f):
    return f["mimeType"].startswith("video/") or f["name"].lower().endswith(VIDEO_ENDUNGEN)


# Darstellung der Kategorien auf der Seite (seit 17.11.2026, Ole: „als normale Einstellung Design 1, Design 2 für Sonder Cases,
# wenn wir wirklich ein YouTube Video mit Shorts als Output haben“)
DARSTELLUNGEN = ("abschnitte", "youtube")

# Ordner, die beim Durchsuchen von Unterordnern nie mitkommen (Animations Elemente, Rohmaterial, Projektdateien), seit 17.11.2026
ORDNER_AUSLASSEN = re.compile(r"^(elemente|assets?|rohmaterial|raw|footage|projektdateien|archiv)$", re.I)


def drive_videos(ordner, tief=False):
    """Videos in einem Ordner, mit tief=True auch in Unterordnern (ohne Ordner wie ELEMENTE, siehe ORDNER_AUSLASSEN)."""
    return [f for f, _ in drive_videos_pfad(ordner, tief)]


def drive_videos_pfad(ordner, tief=True, pfad=()):
    """Videos mit dem Pfad der Unterordner, in denen sie liegen (Tupel der Ordnernamen, leer = direkt im Ordner)."""
    raus = []
    for f in drive_kinder(ordner):
        if ist_ordner(f):
            if tief and not ORDNER_AUSLASSEN.match(f["name"].strip()):
                raus += drive_videos_pfad(f["id"], True, pfad + (f["name"],))
        elif ist_video(f):
            raus.append((f, pfad))
    return raus


def gruppe_aus_ordner(name):
    """Kategorie aus einem Unterordner: „Video 1 - Baby Boomer“ wird „Baby Boomer“, „02 ENERGIEAUSWEIS“ wird „ENERGIEAUSWEIS“."""
    n = re.sub(r"^(video\s*\d+\s*[-–:.]\s*|\d+[\s._-]+)", "", (name or "").strip(), flags=re.I).strip()
    return n or (name or "").strip()


def ist_quer(f):
    m = f.get("videoMediaMetadata") or {}
    return int(m.get("width") or 0) > int(m.get("height") or 0)


def link_freigeben(did):
    """Mux und der Download Knopf brauchen „Jeder mit dem Link: Betrachter“. Setzt das nur, wenn es fehlt."""
    perms = drive().permissions().list(fileId=did, fields="permissions(type,role)", **ALLE).execute().get("permissions", [])
    if any(p["type"] == "anyone" for p in perms):
        return False
    drive().permissions().create(fileId=did, body={"type": "anyone", "role": "reader"}, **ALLE).execute()
    return True


def titel_aus_dateiname(name, alle_namen=()):
    """„CoMakler in onOffice.v1.mp4“ → „CoMakler in onOffice“. Gibt es mehrere Fassungen, bleibt „v2“ sichtbar."""
    basis = re.sub(r"\.(mp4|mov|m4v|webm)$", "", name, flags=re.I)
    ohne = re.sub(r"[ ._-]+[vV]\d+$", "", basis).strip()
    gleiche = [n for n in alle_namen if re.sub(r"[ ._-]+[vV]\d+(\.\w+)?$", "", re.sub(r"\.(mp4|mov|m4v|webm)$", "", n, flags=re.I)).strip() == ohne]
    if len(gleiche) > 1:
        m = re.search(r"[vV](\d+)$", basis)
        return f"{ohne} v{m.group(1)}" if m else ohne
    return ohne.replace("_", " ")


# ---------------------------------------------------------------- Kunden und Content Brain
def kunden():
    """Einträge aus kunden.json (Drive Export Ordner pro Kunde), egal ob als Liste oder unter "kunden" (Liste oder nach Namen)."""
    d = lesen_json(SKILLS / "kunden-videos-hochladen-und-planen" / "kunden.json", [])
    d = d.get("kunden", d) if isinstance(d, dict) else d
    return [x for x in (d.values() if isinstance(d, dict) else d) if isinstance(x, dict)]


def kunde_finden(text):
    """Kunde über Ordnername (justus-vogelsang), Kunden ID (SC-003) oder Namen (Justus). Zuerst die eigenen StageView Kunden
    (im Dashboard angelegt oder umbenannt), dann das Kundenregister im Content Brain."""
    t = slug(text)
    for k in kunden_datei().get("kunden", []):
        if t and t in (k["id"], slug(k["name"])):
            reg_k = next((r for r in register_kunden() if r["ordner"] == k["id"]), {})
            kv = next((x for x in kunden() if reg_k and x.get("kunde_id") == reg_k.get("id")), {})
            return {"ordner": k["id"], "id": reg_k.get("id") or k["id"], "name": k["name"], "firma": k.get("firma") or "",
                    "drive_export": kv.get("drive_export")}
    reg = lesen_json(SKILLS / "stagecraft-content-brain" / "kunden-register.json", {})
    eintraege = reg.get("kunden", reg) if isinstance(reg, dict) else reg
    t = slug(text)
    for k in eintraege if isinstance(eintraege, list) else []:
        namen = [k.get("ordner", ""), k.get("id", ""), k.get("name", "")] + list(k.get("frueher") or [])
        if any(t and (t == slug(n) or t in slug(n).split("-")) for n in namen):
            kv = next((x for x in kunden() if x.get("kunde_id") == k.get("id")), {})
            return {"ordner": k.get("ordner"), "id": k.get("id"), "name": k.get("name"), "firma": k.get("firma") or "",
                    "drive_export": kv.get("drive_export")}
    k = next((x for x in kunden_liste() if t in (x["id"], slug(x["name"]))), None)  # z.B. Stagecraft, nur an Links
    if k:
        return {"ordner": k["id"], "id": k["id"], "name": k["name"], "firma": k["firma"], "drive_export": None}
    fehler(f"Kunde nicht gefunden: {text} (stageview kunden)")


# ---------------------------------------------------------------- StageView Kunden (seit 14.11.2026, Admin Dashboard)
# Eigene Liste in data/stageview/kunden.json: {"kunden": [{"id", "name", "firma"}], "ausgeblendet": [ordner aus dem Register]}.
# Dazu kommen die Kunden aus dem Kundenregister im Content Brain (nie dort schreiben). Ein eigener Eintrag mit derselben id
# überschreibt den aus dem Register (umbenannt), ausgeblendete zeigt StageView nicht. Gleiche Logik in server/videos_api.py
def kunden_datei():
    d = lesen_json(DATEN / "kunden.json", {})
    return {"kunden": d.get("kunden", []), "ausgeblendet": d.get("ausgeblendet", [])}


def register_kunden():
    reg = lesen_json(SKILLS / "stagecraft-content-brain" / "kunden-register.json", {})
    e = reg.get("kunden", reg) if isinstance(reg, dict) else reg
    return [k for k in (e if isinstance(e, list) else []) if isinstance(k, dict) and k.get("ordner") and k.get("name")]


def gehoert_zu(p, k):
    return p.get("kunde_ordner") == k["id"] or (not p.get("kunde_ordner") and (p.get("kunde") or "") == k["name"])


def kunden_liste():
    d = kunden_datei()
    raus = [{"id": k["id"], "name": k["name"], "firma": k.get("firma") or "", "quelle": "stageview"} for k in d["kunden"]]
    ids = {k["id"] for k in raus}
    for k in register_kunden():
        if k["ordner"] not in ids and k["ordner"] not in d["ausgeblendet"]:
            raus.append({"id": k["ordner"], "name": k["name"], "firma": k.get("firma") or "", "quelle": "content-brain"})
            ids.add(k["ordner"])
    projekte = alle_projekte()
    for p in projekte.values():  # Kunden, die nur an einem Link hängen (z.B. Stagecraft selbst)
        if not any(gehoert_zu(p, k) for k in raus):
            kid = p.get("kunde_ordner") or slug(p.get("kunde") or "") or "ohne-kunde"
            if kid not in ids:
                raus.append({"id": kid, "name": p.get("kunde") or "Ohne Kunde", "firma": "", "quelle": "link"})  # Firma gehört zum Link
                ids.add(kid)
    for k in raus:
        k["links"] = sum(1 for p in projekte.values() if gehoert_zu(p, k))
    return sorted(raus, key=lambda k: k["name"].lower())


def kunde_aus_liste(kid):
    return next((k for k in kunden_liste() if k["id"] == kid), None) or fehler(f"Kunde nicht gefunden: {kid} (stageview kunden)")


def b_kunden(a):
    for k in kunden_liste():
        quelle = {"stageview": "StageView", "content-brain": "Content Brain", "link": "nur am Link"}[k["quelle"]]
        print(f"{k['id']:<24} {k['name']}{' · ' + k['firma'] if k['firma'] else ''}  ({k['links']} Link{'' if k['links'] == 1 else 's'}, {quelle})")


def b_kunde_neu(a):
    name = a.name.strip()
    if not name:
        fehler("Name fehlt")
    with Sperre():
        d = kunden_datei()
        reg = {k["ordner"]: k for k in register_kunden()}
        treffer = next((k for k in kunden_liste() if slug(k["name"]) == slug(name)), None)
        if treffer:
            fehler(f"„{treffer['name']}“ gibt es schon")
        weg = next((o for o in d["ausgeblendet"] if slug(reg.get(o, {}).get("name", "")) == slug(name)), None)
        if weg:  # ein ausgeblendeter Kunde aus dem Content Brain kommt einfach zurück
            d["ausgeblendet"].remove(weg)
            kid = weg
        else:
            kid, n = slug(name) or "kunde", 2
            while kid in {k["id"] for k in kunden_liste()} or kid in reg:
                kid, n = f"{slug(name)}-{n}", n + 1
            d["kunden"].append({"id": kid, "name": name, "firma": (a.firma or "").strip(), "angelegt": datetime.now(timezone.utc).isoformat(timespec="seconds")})
        schreiben_json(DATEN / "kunden.json", d)
    print(f"Kunde angelegt: {kid}")


def b_kunde_aendern(a):
    with Sperre():
        k = kunde_aus_liste(a.id)
        alt = dict(k)
        name = (a.name if a.name is not None else k["name"]).strip() or k["name"]
        firma = (a.firma if a.firma is not None else k["firma"]).strip()
        d = kunden_datei()
        eigen = next((x for x in d["kunden"] if x["id"] == k["id"]), None)
        if eigen:
            eigen.update(name=name, firma=firma)
        else:  # Kunde aus dem Content Brain oder nur am Link: eigener Eintrag mit derselben id gewinnt
            d["kunden"].append({"id": k["id"], "name": name, "firma": firma, "angelegt": datetime.now(timezone.utc).isoformat(timespec="seconds")})
        schreiben_json(DATEN / "kunden.json", d)
        geaendert = []
        for s_, p in alle_projekte().items():
            if gehoert_zu(p, alt):
                p.update(kunde=name, kunde_ordner=k["id"])
                if a.firma is not None:
                    p["firma"] = firma
                schreiben_json(projekt_datei(s_), p)
                geaendert.append(s_)
        for s_ in geaendert:
            melden(bauen(s_))
    print(f"Kunde geändert: {name}{' · ' + firma if firma else ''} ({len(geaendert)} Links neu gebaut)")


def b_kunde_weg(a):
    with Sperre():
        k = kunde_aus_liste(a.id)
        if k["links"]:
            fehler(f"{k['name']} hat noch {k['links']} Link{'s' if k['links'] != 1 else ''}. Erst einem anderen Kunden zuteilen, dann löschen")
        d = kunden_datei()
        d["kunden"] = [x for x in d["kunden"] if x["id"] != k["id"]]
        if k["id"] in {r["ordner"] for r in register_kunden()} and k["id"] not in d["ausgeblendet"]:
            d["ausgeblendet"].append(k["id"])  # im Content Brain bleibt der Kunde
        schreiben_json(DATEN / "kunden.json", d)
    print(f"{k['name']} ist aus StageView raus" + (" (im Content Brain bleibt der Kunde)" if k["quelle"] == "content-brain" else ""))


def os_aktualisieren():
    """Content Brain auf VPS 2 auf den neuesten Stand holen, nur wenn dort nichts offen ist."""
    try:
        if subprocess.run(["git", "-C", str(OS_PFAD), "status", "--porcelain"], capture_output=True, text=True, timeout=20).stdout.strip():
            return
        subprocess.run(["git", "-C", str(OS_PFAD), "pull", "--ff-only", "-q"], capture_output=True, timeout=60)
    except Exception:
        pass


def kopf(datei):
    m = re.match(r"---\n(.*?)\n---", datei.read_text(encoding="utf-8"), re.S)
    werte = {}
    for zeile in (m.group(1).splitlines() if m else []):
        if ":" in zeile:
            k, v = zeile.split(":", 1)
            werte[k.strip()] = v.strip().strip('"')
    return werte


def posting_zeit(text):
    m = re.search(r"(\d{2})\.(\d{2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?", text or "")
    if not m:
        return None
    t, mo, j, h, mi = m.groups()
    return f"{j}-{mo}-{t}T{int(h or 0):02d}:{mi or '00'}"


def content_days(kunde_ordner):
    """Content Days eines Kunden aus den Transkripten (Feld content_day, z.B. "COMAKLER CONTENT DAY OKTOBER 26 (Dreh 23.10.2026)")."""
    tage = {}
    for datei in sorted((SKILLS / "stagecraft-content-brain" / "kunden" / kunde_ordner / "transkripte").glob("*.md")):
        k = kopf(datei)
        cd, link = k.get("content_day", ""), k.get("drive", "")
        m = re.search(r"CONTENT DAY\s+([A-Za-zÄÖÜäöü]+)", cd, re.I)
        did = re.search(r"/d/([A-Za-z0-9_-]+)", link)
        if not m or not did:
            continue
        name = m.group(1).capitalize()
        d = re.search(r"(\d{2})\.(\d{2})\.(\d{4})", cd)
        g = tage.setdefault(name, {"name": name, "dreh": f"{d.group(3)}-{d.group(2)}-{d.group(1)}" if d else None, "videos": [],
                                   "kunde": k.get("kunde", "")})
        g["videos"].append({"drive": did.group(1), "titel": k.get("video") or datei.stem, "format": k.get("format", ""),
                            "posting": posting_zeit(k.get("posting"))})
    return tage


# ---------------------------------------------------------------- Projekte
def projekt_datei(schluessel):
    return DATEN / "projekte" / f"{schluessel}.json"


def alle_projekte():
    return {p.stem: lesen_json(p, {}) for p in sorted((DATEN / "projekte").glob("*.json"))}


def code_fuer(schluessel, anlegen=True):
    codes = lesen_json(DATEN / "codes.json", {})
    if schluessel not in codes and anlegen:
        vorhanden = set(codes.values())
        while True:
            c = "".join(secrets.choice("abcdefghjkmnpqrstuvwxyz23456789") for _ in range(6))
            if c not in vorhanden:
                break
        codes[schluessel] = c
        schreiben_json(DATEN / "codes.json", codes)
    return codes.get(schluessel)


def schluessel_fuer(text):
    """Projekt über Code (xyz789), Schlüssel oder Link finden (auch der Link auf ein Video, …/xyz789/3)."""
    t = text.strip()
    if "stagecraft.media" in t:
        teile = [x for x in t.split("stagecraft.media", 1)[1].split("?")[0].split("#")[0].split("/") if x]
        t = teile[0] if teile else ""
    codes = lesen_json(DATEN / "codes.json", {})
    if projekt_datei(t).exists():
        return t
    for s, c in codes.items():
        if c == t and projekt_datei(s).exists():
            return s
    fehler(f"Projekt nicht gefunden: {text} (stageview liste)")


def videos_aufnehmen(projekt, eintraege):
    """Neue Videos ans Projekt hängen (doppelte Drive IDs werden übersprungen)."""
    da = {v.get("drive") for v in projekt["videos"]}
    neu = 0
    for e in eintraege:
        if e.get("drive") and e["drive"] not in da:
            projekt["videos"].append({k: v for k, v in e.items() if v not in (None, "")})
            da.add(e["drive"])
            neu += 1
    # Ausdrücklich dazu genommen: gilt nicht mehr als ausgeblendet oder von Hand entfernt
    if projekt.get("drive_weg"):
        projekt["drive_weg"] = [w for w in projekt["drive_weg"] if w.get("drive") not in da] or None
    if projekt.get("entfernt"):
        projekt["entfernt"] = [d for d in projekt["entfernt"] if d not in da] or None
    for feld in ("drive_weg", "entfernt"):
        if feld in projekt and not projekt[feld]:
            del projekt[feld]
    return neu


def nach_mux(projekt, warten):
    """Fehlende Videos des Projekts zu Mux bringen (vorher Link Freigabe im Drive sicherstellen)."""
    assets = mux_assets()
    angelegt = []
    for v in projekt["videos"]:
        did = v.get("drive")
        if not did:
            continue
        a = assets.get(did)
        if a and a.get("status") in ("ready", "preparing"):
            if a["status"] == "preparing":
                angelegt.append(a["id"])
            continue
        try:
            if link_freigeben(did):
                print(f"  Drive Link freigegeben: {v.get('titel')}")
        except Exception as e:
            print(f"  Hinweis: Freigabe für {v.get('titel')} nicht geprüft ({str(e)[:120]})")
        neu = mux_neu(did, v.get('titel'))
        angelegt.append(neu["id"])
        print(f"  zu Mux: {v.get('titel')}", flush=True)
    if angelegt and warten:
        offen = mux_warten(angelegt, warten)
        if offen:
            print(f"  {len(offen)} Video(s) noch in Arbeit bei Mux, später `stageview bauen` (kommen dann von selbst dazu)")


# ---------------------------------------------------------------- Seiten bauen
def logo_symbol():
    def symbol(datei, sid, ausschnitt=None):
        svg = (SEITE / datei).read_text(encoding="utf-8")
        m = re.search(r'<svg[^>]*viewBox="([^"]+)"[^>]*>(.*)</svg>', svg, re.S)
        innen = m.group(2).replace('xlink:href="#', 'href="#').replace('fill="white"', 'fill="currentColor"')
        return f'<symbol id="{sid}" viewBox="{ausschnitt or m.group(1)}">{innen.strip()}</symbol>'
    # „Made by Stagecraft“: Ausschnitt auf die Schrift zugeschnitten (gemessen x 150 bis 543, y 15 bis 105)
    return ('<svg width="0" height="0" style="position:absolute" aria-hidden="true">'
            + symbol("stageview.svg", "stageview-logo") + symbol("made-by-stagecraft.svg", "madeby-logo", "150 15 393 90") + "</svg>")


def seite_bauen():
    s = (SEITE / "projekt.html").read_text(encoding="utf-8")
    s = s.replace("/*ICONS*/{}", (SEITE / "icons.json").read_text(encoding="utf-8").strip())
    s = s.replace("<!--LOGO-->", logo_symbol())
    version = hashlib.sha1(s.encode()).hexdigest()[:10]
    return s.replace("/*VERSION*/''", repr(version)), version


def admin_bauen():
    """Admin Dashboard /admin (seit 14.11.2026): feste Seite ohne Daten, alles kommt nach dem Anmelden über /api/admin/."""
    s = (SEITE / "admin.html").read_text(encoding="utf-8")
    s = s.replace("/*ICONS*/{}", (SEITE / "icons.json").read_text(encoding="utf-8").strip()).replace("<!--LOGO-->", logo_symbol())
    s = s.replace("<!--ICON-->", icon_kopf())
    # Profilbilder für die Anmeldung wie beim Aufgaben Dashboard: von dessen Seite auf demselben Server (keine Kopie im Repo)
    bilder = {}
    for zugang, datei in (("tess", "ole.jpg"), ("alfred", "jonas.jpg"), ("caspar", "caspar.jpg"), ("niklas", "niklas.jpg")):
        try:
            bilder[zugang] = "data:image/jpeg;base64," + base64.b64encode((Path("/var/www/aufgaben/bilder") / datei).read_bytes()).decode()
        except OSError:
            pass  # ohne Bild zeigt der Kreis den Anfangsbuchstaben
    s = s.replace("/*BILDER*/{}", json.dumps(bilder))
    ziel = WEB / "admin" / "index.html"
    if not ziel.exists() or ziel.read_text(encoding="utf-8") != s:
        schreiben(ziel, s)


def vorschaubild(v):
    """Linkvorschau im Format des Videos: Querformat 1200 breit, Hochformat 1280 hoch. (url, breite, höhe)"""
    t = min(2, (v.get("dauer") or 4) / 2)
    ar = v.get("seitenverhaeltnis") or 0.5625
    b = 1200 if ar >= 1 else round(1280 * ar)
    return f"https://image.mux.com/{v['playback_id']}/thumbnail.jpg?width={b}&time={t:g}", b, round(b / ar)


def kopf_html(titel, beschreibung, bild, url, breite=1200, hoehe=630):
    e = lambda s: html.escape(str(s), quote=True)
    return "\n".join([
        f"<title>{e(titel)}</title>", f'<meta name="description" content="{e(beschreibung)}">',
        '<meta property="og:site_name" content="StageView">', '<meta property="og:type" content="website">',
        f'<meta property="og:title" content="{e(titel)}">', f'<meta property="og:description" content="{e(beschreibung)}">',
        f'<meta property="og:url" content="{e(url)}">', f'<meta property="og:image" content="{e(bild)}">',
        f'<meta property="og:image:width" content="{breite}">', f'<meta property="og:image:height" content="{hoehe}">',
        f'<meta property="og:image:alt" content="{e(titel)}">', '<meta name="twitter:card" content="summary_large_image">',
        f'<meta name="twitter:title" content="{e(titel)}">', f'<meta name="twitter:description" content="{e(beschreibung)}">',
        f'<meta name="twitter:image" content="{e(bild)}">', '<meta name="theme-color" content="#121211">', icon_kopf(),
    ])


def seitenverhaeltnis(text):
    try:
        b, h = (float(x) for x in text.split(":"))
        return round(b / h, 4)
    except Exception:
        return 0.5625


# Übliche Bildraten: Mux meldet manchmal krumme Werte (29,98 statt 29,97), die auf die Norm gerundet werden
FPS_NORM = (23.976, 24, 25, 29.97, 30, 47.952, 48, 50, 59.94, 60, 100, 119.88, 120)


def bildrate(asset):
    """Bildrate eines Mux Assets (seit 23.11.2026 für bildgenaue Kommentare und Marker), auf die Norm gerundet. None, wenn unbekannt.
    Jedes Video hat seine eigene, ein Link darf 25, 30 und 60 Bilder gemischt enthalten."""
    werte = [asset.get("max_stored_frame_rate")] + [t.get("max_frame_rate") for t in asset.get("tracks") or [] if t.get("type") == "video"]
    for w in werte:
        try:
            f = float(w)
        except (TypeError, ValueError):
            continue
        if 1 <= f <= 240:
            norm = min(FPS_NORM, key=lambda s: abs(s - f))
            return norm if abs(norm - f) < 0.3 else round(f, 3)
    return None


def projekt_bauen(schluessel, projekt, assets, seite, version, stand):
    """Schreibt /var/www/videos/<code>/: projekt.json, index.html (Projekt) und <nr>/index.html pro Video."""
    code = code_fuer(schluessel)
    nummern = lesen_json(DATEN / "nummern.json", {})
    feste = nummern.setdefault(code, {})
    eintraege, vergeben, fehlt = [], set(), []
    # Kategorien (seit 17.11.2026): Reihenfolge aus „gruppen“ im Projekt, sonst wie sie zuerst vorkommen. Videos ohne Kategorie
    # kommen zuerst, dann jede Kategorie für sich, darin wie bisher nach Posting Datum und Reihenfolge im Projekt
    gruppen = [g for g in projekt.get("gruppen") or [] if g]
    for v in projekt["videos"]:
        if v.get("gruppe") and v["gruppe"] not in gruppen:
            gruppen.append(v["gruppe"])
    rang = lambda v: gruppen.index(v["gruppe"]) + 1 if v.get("gruppe") in gruppen else 0
    reihe = sorted(enumerate(projekt["videos"]), key=lambda iv: (rang(iv[1]), iv[1].get("posting") or "9999", iv[0]))
    groessen_neu = False
    for _, v in reihe:
        if v.get("drive"):
            a = assets.get(v["drive"])
            if not a or a.get("status") != "ready":  # neue Datei (neue Fassung) noch bei Mux: bis dahin die bisherige
                a = next((assets[x] for x in reversed(v.get("vorher") or []) if (assets.get(x) or {}).get("status") == "ready"), a)
            if not a or a.get("status") != "ready":
                fehlt.append(v.get("titel") or v["drive"])
                continue
            pid = next((p["id"] for p in a.get("playback_ids", []) if p.get("policy") == "public"), None)
            if not pid:
                fehlt.append(v.get("titel"))
                continue
            if not v.get("groesse"):
                try:
                    v["groesse"] = int(drive_datei(v["drive"]).get("size") or 0) or None
                    groessen_neu = True
                except Exception:
                    pass
            schl = v["drive"]
            daten = {"playback_id": pid, "dauer": round(a.get("duration") or 0, 1), "fps": bildrate(a),
                     "seitenverhaeltnis": seitenverhaeltnis(a.get("aspect_ratio", "9:16")), "groesse": v.get("groesse"),
                     "download": DRIVE_DL.format(v["drive"]), "drive": f"https://drive.google.com/file/d/{v['drive']}/view"}
        else:  # feste Videos ohne Drive (z.B. öffentliche Mux Beispielvideos auf Vorschau Seiten), eigene id hält Kommentare fest
            schl = v.get("id") or v["playback_id"]
            daten = {k: v.get(k) for k in ("playback_id", "dauer", "seitenverhaeltnis", "groesse", "download", "drive")}
        if schl not in feste:
            feste[schl] = max(feste.values(), default=0) + 1
        s, n = v.get("slug") or slug(v.get("titel")) or "video", 2
        while s in vergeben:
            s, n = f"{slug(v.get('titel'))}-{n}", n + 1
        vergeben.add(s)
        eintraege.append({"id": schl, "nr": feste[schl], "slug": s, "titel": v.get("titel") or "Video",
                          "format": v.get("format", ""), "posting": v.get("posting"), **daten,
                          **({"gruppe": v["gruppe"]} if v.get("gruppe") else {})})
    schreiben_json(DATEN / "nummern.json", nummern)
    if groessen_neu:
        schreiben_json(projekt_datei(schluessel), projekt)
    pj = {"stand": stand, "titel": projekt["titel"], "kunde": projekt.get("kunde", ""), "firma": projekt.get("firma", ""),
          "dreh": projekt.get("dreh"), "videos": eintraege, "seite": version}
    if projekt.get("hinweis"):
        pj["hinweis"] = projekt["hinweis"]
    benutzt = [g for g in gruppen if any(e.get("gruppe") == g for e in eintraege)]
    if benutzt:
        pj["gruppen"] = benutzt
    if projekt.get("darstellung") == "youtube":
        pj["darstellung"] = "youtube"
    ordner = WEB / code
    schreiben_json(ordner / "projekt.json", pj)
    wer = " · ".join(x for x in (pj["kunde"], pj["firma"]) if x)
    logo_v = hashlib.sha1((SEITE / LOGO_VORSCHAU).read_bytes()).hexdigest()[:8]
    bild = vorschaubild(eintraege[0]) if len(eintraege) == 1 else (f"{BASIS_URL}/{LOGO_VORSCHAU}?v={logo_v}", 1200, 630)
    anzahl = "1 Video" if len(eintraege) == 1 else f"{len(eintraege)} Videos"
    schreiben(ordner / "index.html", seite.replace("<!--KOPF-->", kopf_html(pj["titel"], " · ".join(x for x in (wer, anzahl) if x),
                                                                          bild[0], f"{BASIS_URL}/{code}", *bild[1:])))
    for alt in ordner.iterdir():
        if alt.is_dir() and alt.name.isdigit():
            shutil.rmtree(alt)
    for v in eintraege:
        url, b, h = vorschaubild(v)
        k = kopf_html(f"{v['titel']} · {pj['titel']}", " · ".join(x for x in (wer, dauer_text(v.get("dauer"))) if x),
                      url, f"{BASIS_URL}/{code}/{v['nr']}", b, h)
        schreiben(ordner / str(v["nr"]) / "index.html", seite.replace("<!--KOPF-->", k))
    return code, len(eintraege), fehlt


def bauen(nur=None, assets=None):
    """Alle Projekte (oder nur eins) neu bauen. Gibt {schluessel: (code, anzahl, fehlt)} zurück."""
    seite, version = seite_bauen()
    assets = assets if assets is not None else mux_assets()
    stand = datetime.now(timezone.utc).isoformat(timespec="seconds")
    for datei in ("logo.svg", LOGO_VORSCHAU) + ICON_DATEIEN:
        quelle = (SEITE / datei).read_bytes()
        ziel = WEB / datei
        if not ziel.exists() or ziel.read_bytes() != quelle:
            schreiben(ziel, quelle)
    admin_bauen()
    raus = {}
    for s, p in alle_projekte().items():
        if nur and s != nur:
            continue
        raus[s] = projekt_bauen(s, p, assets, seite, version, stand)
    return raus


def melden(ergebnis):
    for s, (code, n, fehlt) in ergebnis.items():
        print(f"  {s}: {n} {'Video' if n == 1 else 'Videos'} → {BASIS_URL}/{code}")
        if fehlt:
            print(f"    noch nicht bei Mux fertig: {', '.join(fehlt)}")


# ---------------------------------------------------------------- Kommentare (als Team, Abzeichen Stagecraft)
def api(code, pfad="", methode="GET", daten=None):
    team = env_datei(HAUS / "videos-api.env").get("VIDEOS_TEAM_KEY", "")
    if not team:
        fehler("Team Schlüssel fehlt (~/.hermes/videos-api.env)")
    autor = "stageview-" + hashlib.sha1(("stageview" + team).encode()).hexdigest()[:24]
    req = urllib.request.Request(f"{API}/{code}/{pfad}", method=methode, data=json.dumps(daten).encode() if daten is not None else None,
                                 headers={"Content-Type": "application/json", "X-Team": team, "X-Autor": autor})
    try:
        return json.load(urllib.request.urlopen(req, timeout=20))
    except urllib.error.HTTPError as e:
        fehler(f"Kommentar Dienst: {e.code} {e.read().decode()[:200]}")


def projekt_json(code):
    return lesen_json(WEB / code / "projekt.json", None) or fehler(f"keine Seite für {code}")


STATUS = {"zur-freigabe": "Zur Freigabe", "aenderung": "Änderung gewünscht", "freigegeben": "Freigegeben"}


# ---------------------------------------------------------------- Karten für die TESS App (seit 16.11.2026)
# Ole: eigene Karten für StageView Anfragen bei TESS und Alfred. Mit --karte gibt stageview den fertigen ```karte Block aus,
# der Agent übernimmt ihn unverändert. So stimmen Vorschaubilder, Zahlen und Links immer (Aussehen: TESS_APP StageViewCards.swift)
def karte_drucken(daten):
    print("```karte\n" + json.dumps(daten, ensure_ascii=False, separators=(",", ":")) + "\n```")


def mux_bild(v, breite, hoehe):
    t = min(2, float(v.get("dauer") or 4) / 2)
    return f"https://image.mux.com/{v['playback_id']}/thumbnail.jpg?width={breite}&height={hoehe}&fit_mode=smartcrop&time={t:g}"


def kurzdatum(iso):
    return f"{iso[8:10]}.{iso[5:7]}." if iso and len(iso) >= 10 else ""


def ist_hoch(v):
    return float(v.get("seitenverhaeltnis") or 1.7778) < 1


def stand_von(code):
    """Freigabe und Kommentare eines Links, leer, wenn der Kommentar Dienst gerade nicht antwortet."""
    try:
        return api(code)
    except SystemExit:
        return {"kommentare": [], "status": {}}


def link_karte(p, code, mit_videos):
    """Eintrag für die stageview Karte und, falls gewünscht, die Videos darunter."""
    vids = lesen_json(WEB / code / "projekt.json", {}).get("videos", []) if code else []
    d = stand_von(code) if code else {"kommentare": [], "status": {}}
    offen = {}
    for k in d.get("kommentare") or []:
        if not k.get("antwort_auf") and not k.get("erledigt"):
            offen[k["video"]] = offen.get(k["video"], 0) + 1
    werte = [((d.get("status") or {}).get(v["id"]) or {}).get("wert", "zur-freigabe") for v in vids]
    hoch = sum(ist_hoch(v) for v in vids) * 2 > len(vids)
    bilder = [mux_bild(v, 180, 320) for v in vids[:4]] if hoch and len(vids) > 1 else [mux_bild(vids[0], 640, 360)] if vids else []
    eintrag = {"titel": p.get("titel") or "", "kunde": p.get("kunde") or "", "link": f"{BASIS_URL}/{code}", "bilder": bilder,
               "format": "hoch" if hoch else "quer", "videos": len(vids), "freigegeben": werte.count("freigegeben"),
               "aenderung": werte.count("aenderung"), "offen": sum(offen.values()), "datum": kurzdatum(p.get("angelegt"))}
    videos = [{"nr": v["nr"], "titel": v["titel"], "link": f"{BASIS_URL}/{code}/{v['nr']}",
               "bild": mux_bild(v, 90, 160) if ist_hoch(v) else mux_bild(v, 160, 90), "format": "hoch" if ist_hoch(v) else "quer",
               "status": w, "offen": offen.get(v["id"], 0)} for v, w in zip(vids, werte)] if mit_videos and len(vids) > 1 else []
    return eintrag, videos


def kommentar_karte(eintraege, video, link, als="", neu=False, vorschau=False):
    karte = {"art": "kommentare", "video": video, "link": link, "eintraege": eintraege}
    if als:
        karte["zusatz"] = f"als {als}"
    if neu:
        karte["neu"] = True
    if vorschau:
        karte["vorschau"] = True
    return karte


def notiz(zeit, text, name, link, video=""):
    e = {"zeit": dauer_text(zeit) if zeit is not None else "", "text": text, "name": name,
         "link": link + (f"?t={int(zeit)}" if zeit is not None else "")}
    if video:
        e["video"] = video
    return e


def zeit_lesen(text, dauer=None):
    """Stelle im Video: 1:08, 68, 68,5 oder 1:02:03 → Sekunden. Leer, null oder "-" → None (Kommentar ohne Stelle)."""
    if text is None or str(text).strip().lower() in ("", "-", "null", "none", "ohne"):
        return None
    t = str(text).strip().replace(",", ".")
    if not re.fullmatch(r"\d+(:\d{1,2}){0,2}(\.\d+)?", t):
        fehler(f"Zeit {text!r}: bitte als 1:08 oder 68 angeben")
    z = 0.0
    for teil in t.split(":"):
        z = z * 60 + float(teil)
    if dauer and z > float(dauer) + 0.5:
        fehler(f"{text} liegt hinter dem Ende des Videos ({dauer_text(float(dauer))})")
    return z


def video_aus(projekt, nr=None):
    """Projekt und Video aus Code, Schlüssel oder Link. Ohne nr gilt die Nummer aus dem Link (…/xyz789/3)."""
    if nr is None and "stagecraft.media" in projekt:
        teile = [x for x in projekt.split("stagecraft.media", 1)[1].split("?")[0].split("/") if x]
        nr = teile[1] if len(teile) > 1 else None
    code = code_fuer(schluessel_fuer(projekt), False) or fehler(f"{projekt} hat noch keinen Link")
    pj = projekt_json(code)
    if nr is None and len(pj["videos"]) == 1:
        nr = pj["videos"][0]["nr"]
    v = next((x for x in pj["videos"] if str(x["nr"]) == str(nr)), None)
    if not v:
        fehler(f"Welches Video? Nummer angeben, im Projekt sind: {', '.join(str(x['nr']) + ' ' + x['titel'] for x in pj['videos'])}")
    return code, pj, v


# ---------------------------------------------------------------- Kontext für Feedback (seit 16.11.2026)
# Ole: TESS und Alfred sollen Feedback aus dem Team (z.B. Jonas schreibt seine Punkte als Nachricht) selbst an die richtigen
# Stellen im Video setzen, so wie Claude es am 16.11. beim Vlog KW47 gemacht hat. `stageview kontext` liefert dafür alles, was man
# ohne das Video anzusehen braucht: Transkript mit Zeiten (Mux Spracherkennung, ohne Aufpreis), Schnitte, Lautheit pro Abschnitt
# und Bildbögen mit der Zeit in jedem Bild. Das Video wird nie gespeichert, ffmpeg liest die kleinste Stufe direkt von Mux.
KONTEXT = DATEN / "kontext"
SCHRIFT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def asset_fuer(v):
    """Das Mux Asset, das die Seite gerade abspielt (über die Playback ID im projekt.json)."""
    seite = 1
    while True:
        daten = mux(f"/video/v1/assets?limit=100&page={seite}")["data"]
        for a in daten:
            if any(p.get("id") == v.get("playback_id") for p in a.get("playback_ids") or []):
                return mux(f"/video/v1/assets/{a['id']}")["data"]
        if len(daten) < 100:
            break
        seite += 1
    fehler("Video nicht bei Mux gefunden (läuft es auf der Seite? sonst erst `stageview bauen`)")


def vtt_zeit(s):
    z = 0.0
    for teil in s.strip().split(":"):
        z = z * 60 + float(teil)
    return z


def vtt_lesen(text):
    stuecke = []
    for block in re.split(r"\n\s*\n", text.replace("\r", "")):
        zeilen = block.strip().split("\n")
        for i, z in enumerate(zeilen):
            m = re.match(r"([\d:.]+)\s*-->\s*([\d:.]+)", z)
            if m:
                inhalt = html.unescape(re.sub(r"<[^>]+>", "", " ".join(zeilen[i + 1:]))).strip()
                if inhalt:
                    stuecke.append({"von": round(vtt_zeit(m.group(1)), 2), "bis": round(vtt_zeit(m.group(2)), 2), "text": inhalt})
                break
    return stuecke


def woerter_kleben(stuecke):
    """Mux bricht seine Zeilen hart nach etwa 80 Zeichen um, auch mitten im Wort ("reing" | "egangen"). Ein Wort wird wieder
    zusammengesetzt, wenn die Zeile davor voll war und beide Teile sonst nirgends im Transkript als eigenes Wort vorkommen."""
    def wort(w):
        return re.sub(r"\W", "", w).casefold()
    zahl = {}
    for s in stuecke:
        for w in s["text"].split():
            zahl[wort(w)] = zahl.get(wort(w), 0) + 1
    stuecke = [dict(s) for s in stuecke]
    for a, b in zip(stuecke, stuecke[1:]):
        wa, wb = a["text"].split(), b["text"].split()
        if len(a["text"]) < 70 or not wa or not wb or not wa[-1][-1].isalpha() or not wb[0][0].islower():
            continue
        if zahl.get(wort(wa[-1])) == 1 and zahl.get(wort(wb[0])) == 1:
            a["text"], b["text"] = " ".join(wa[:-1] + [wa[-1] + wb[0]]), " ".join(wb[1:])
    return [s for s in stuecke if s["text"]]


def saetze(stuecke):
    """Mux liefert kurze Untertitel Stücke. Für den Kontext zu Sätzen zusammengefasst: Satzende, Pause über 1,5 s oder spätestens nach 15 s."""
    aus, cur = [], None
    for s in woerter_kleben(stuecke):
        if cur and (s["von"] - cur["bis"] > 1.5 or cur["bis"] - cur["von"] > 15):
            aus.append(cur)
            cur = None
        if cur is None:
            cur = dict(s)
        else:
            cur["bis"], cur["text"] = s["bis"], cur["text"] + " " + s["text"]
        if re.search(r"[.!?…][\"'»«“”)]*$", cur["text"]):
            aus.append(cur)
            cur = None
    if cur:
        aus.append(cur)
    return aus


def transkript_datei(v):
    return DATEN / "transkripte" / f"{v['id']}.json"


def transkript_anfragen(v, sprache):
    """Startet bei Mux die Spracherkennung für die Tonspur (falls noch keine läuft). Gibt (Asset, Textspur) zurück."""
    asset = asset_fuer(v)
    spuren = asset.get("tracks") or []
    t = next((x for x in spuren if x.get("type") == "text" and x.get("text_source") == "generated_vod"
              and x.get("language_code") == sprache and x.get("status") != "errored"), None)
    if not t:
        audio = next((x for x in spuren if x.get("type") == "audio"), None) or fehler("Das Video hat keine Tonspur")
        t = mux(f"/video/v1/assets/{asset['id']}/tracks/{audio['id']}/generate-subtitles", "POST",
                {"generated_subtitles": [{"language_code": sprache, "name": "StageView Transkript", "passthrough": "stageview-transkript"}]})["data"][0]
        print("  Mux schreibt das Transkript (Spracherkennung, ohne Aufpreis) …", flush=True)
    return asset, t


def transkript_abholen(v, asset, t, sprache, bis_wann):
    """Wartet bis bis_wann auf die Spracherkennung, speichert das Transkript bei uns und nimmt die Spur bei Mux wieder weg.
    None, wenn Mux noch nicht fertig ist (dann einfach gleich noch einmal aufrufen, die Spur läuft weiter)."""
    while t.get("status") != "ready":
        if t.get("status") == "errored":
            fehler(f"Mux konnte kein Transkript erstellen ({t.get('errors') or t.get('status')})")
        if time.time() > bis_wann:
            return None
        time.sleep(6)
        t = next((x for x in mux(f"/video/v1/assets/{asset['id']}")["data"].get("tracks") or [] if x.get("id") == t["id"]), None) \
            or fehler("Die Transkript Spur ist bei Mux verschwunden, bitte noch einmal")
    pid = asset["playback_ids"][0]["id"]
    vtt = urllib.request.urlopen(f"https://stream.mux.com/{pid}/text/{t['id']}.vtt", timeout=30).read().decode("utf-8")
    daten = {"video": v["id"], "titel": v.get("titel"), "sprache": sprache, "quelle": "Mux Spracherkennung",
             "erstellt": datetime.now(timezone.utc).isoformat(timespec="seconds"), "stuecke": vtt_lesen(vtt)}
    schreiben_json(transkript_datei(v), daten)
    # Spur bei Mux wieder entfernen: sonst bietet der iPhone Player im Vollbild den Kunden plötzlich Untertitel an.
    # Das Transkript liegt jetzt bei uns, die Seite bleibt, wie sie ist
    try:
        mux(f"/video/v1/assets/{asset['id']}/tracks/{t['id']}", "DELETE")
    except SystemExit:
        print("  Hinweis: Transkript Spur bei Mux nicht entfernt, beim nächsten `stageview transkript` noch einmal", flush=True)
    return daten


def transkript_holen(v, sprache="de", warten=150, neu=False):
    alt = lesen_json(transkript_datei(v), None)
    if alt and not neu and alt.get("sprache") == sprache:
        return alt
    asset, t = transkript_anfragen(v, sprache)
    return transkript_abholen(v, asset, t, sprache, time.time() + warten)


def metadaten_lesen(pfad, schluessel):
    """Ausgabe von ffmpeg metadata=print / ametadata=print: (Zeit, Wert) pro Bild bzw. Messung."""
    werte, t = [], None
    try:
        zeilen = Path(pfad).read_text().splitlines()
    except FileNotFoundError:
        return werte
    for z in zeilen:
        if z.startswith("frame:"):
            m = re.search(r"pts_time:(-?[\d.]+)", z)
            t = float(m.group(1)) if m else None
        elif z.startswith(schluessel + "=") and t is not None:
            werte.append((round(t, 2), round(float(z.split("=", 1)[1]), 1)))
    return werte


def video_analyse(v, ordner, abstand):
    """Ein ffmpeg Durchlauf über die kleinste Stufe direkt von Mux (das Video wird nicht gespeichert, 9 Minuten Video etwa 35 s):
    Schnitte (Szenenwechsel), Lautheit nach EBU R128 (Momentanwert alle 0,1 s) und Bildbögen mit der Zeit in jedem Bild."""
    ordner.mkdir(parents=True, exist_ok=True)
    for alt in list(ordner.glob("bogen-*.jpg")) + [ordner / "schnitte.txt", ordner / "lautheit.txt"]:
        alt.unlink(missing_ok=True)
    ar = float(v.get("seitenverhaeltnis") or 16 / 9)
    if ar >= 1:
        w, h, spalten, reihen = 384, int(round(384 / ar / 2) * 2), 5, 6
    else:
        w, h, spalten, reihen = int(round(320 * ar / 2) * 2), 320, 8, 3
    (ordner / "zeit.txt").write_text("%{eif:trunc(t/60):d}:%{eif:mod(t,60):d:2}")
    fc = (f"[0:v:0]split=2[a][b];[a]select=gt(scene\\,0.3),metadata=print:file=schnitte.txt,nullsink;"
          f"[b]fps=1/{abstand},scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=0x191918,"
          f"drawtext=fontfile={SCHRIFT}:textfile=zeit.txt:x=8:y=8:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=5,"
          f"tile={spalten}x{reihen}:padding=4:color=0x191918[bild];"
          f"[0:a:0]ebur128=metadata=1,ametadata=print:key=lavfi.r128.M:file=lautheit.txt,anullsink")
    quelle = f"https://stream.mux.com/{v['playback_id']}.m3u8?max_resolution=270p"
    befehl = ["nice", "-n", "10", "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-threads", "2",
              "-i", quelle, "-filter_complex", fc, "-map", "[bild]", "-fps_mode", "passthrough", "bogen-%d.jpg"]
    try:
        r = subprocess.run(befehl, cwd=ordner, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        fehler("ffmpeg hat zu lange gebraucht (über 15 Minuten)")
    if r.returncode != 0 and "ebur128" in fc and "a:0" in r.stderr:
        # Video ohne Ton: noch einmal ohne Lautheit
        befehl[befehl.index("-filter_complex") + 1] = fc.split(";[0:a:0]")[0]
        r = subprocess.run(befehl, cwd=ordner, capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        fehler(f"ffmpeg: {r.stderr.strip()[-400:]}")
    schnitte = [t for t, _ in metadaten_lesen(ordner / "schnitte.txt", "lavfi.scene_score")]
    lautheit = metadaten_lesen(ordner / "lautheit.txt", "lavfi.r128.M")
    pro_bogen = spalten * reihen
    dauer = float(v.get("dauer") or (lautheit[-1][0] if lautheit else 0))
    bilder = int(dauer // abstand) + 1
    boegen = []
    for i in range(1, len(list(ordner.glob("bogen-*.jpg"))) + 1):
        erstes, letztes = (i - 1) * pro_bogen, min(i * pro_bogen, bilder) - 1
        boegen.append({"datei": f"bogen-{i}.jpg", "von": erstes * abstand, "bis": letztes * abstand})
    for weg in ("schnitte.txt", "lautheit.txt", "zeit.txt"):
        (ordner / weg).unlink(missing_ok=True)
    ana = {"playback_id": v["playback_id"], "dauer": dauer, "abstand": abstand, "boegen": boegen, "schnitte": schnitte,
           "lautheit": lautheit, "erstellt": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    schreiben_json(ordner / "analyse.json", ana)
    return ana


def analyse_holen(code, v, abstand=None, neu=False):
    ordner = KONTEXT / f"{code}-{v['nr']}"
    alt = lesen_json(ordner / "analyse.json", None)
    if alt and not neu and alt.get("playback_id") == v["playback_id"] and (not abstand or alt.get("abstand") == abstand):
        return ordner, alt
    if not abstand:
        abstand = max(1, min(30, math.ceil(float(v.get("dauer") or 60) / 150)))
    print(f"  schaue das Video durch (Schnitte, Lautheit, ein Bild alle {abstand} s) …", flush=True)
    return ordner, video_analyse(v, ordner, abstand)


def lufs(werte, von=0.0, bis=None):
    """Integrierte Lautheit nach EBU R128 über einen Bereich: Momentanwerte (400 ms, alle 100 ms) mit absolutem (−70) und
    relativem Gate (−10 LU). Für das ganze Video derselbe Wert, den ffmpeg als Integrated misst."""
    e = [10 ** (m / 10) for t, m in werte if t >= von + 0.4 and (bis is None or t <= bis) and m > -70]
    if not e:
        return None
    grenze = 10 * math.log10(sum(e) / len(e)) - 10
    e = [x for x in e if 10 * math.log10(x) > grenze]
    return 10 * math.log10(sum(e) / len(e))


def lufs_text(wert):
    return "still" if wert is None else f"{wert:.1f} LUFS".replace(".", ",")


def abschnitte_aus(dauer, schnitte, min_laenge=6.0):
    """Abschnitte aus den Schnitten, sehr kurze Einstellungen (unter 6 s) gehören zum nächsten Abschnitt."""
    teile, von = [], 0.0
    for g in [t for t in schnitte if 0.5 < t < dauer - 0.5] + [dauer]:
        if g - von >= min_laenge or g == dauer:
            teile.append([von, g])
            von = g
    if len(teile) > 1 and teile[-1][1] - teile[-1][0] < min_laenge:
        rest = teile.pop()
        teile[-1][1] = rest[1]
    return teile or [[0.0, dauer]]


def kontext_text(code, v, ordner, ana, tr, kommentare):
    dauer = float(v.get("dauer") or ana["dauer"])
    werte, gesamt = ana["lautheit"], lufs(ana["lautheit"])
    stuecke = tr["stuecke"] if tr else []
    alle_saetze = saetze(stuecke)
    z = [f"# Kontext: {v['titel']} (Video {v['nr']}, {dauer_text(dauer)})",
         f"Link: {BASIS_URL}/{code}/{v['nr']}",
         f"Lautheit gesamt: {lufs_text(gesamt)} integriert (EBU R128). Für Social Media peilen wir meist -14 LUFS an",
         ("Transkript: Mux Spracherkennung, Namen, Fachwörter und Englisch können falsch geschrieben sein, Zeiten stimmen"
          if tr else "Transkript: Mux ist noch nicht fertig. In 1 bis 2 Minuten denselben Befehl noch einmal, der Rest ist dann sofort da"),
         f"Bildbögen: ein Bild alle {ana['abstand']} s, die Zeit steht oben links in jedem Bild. Mit dem Bild Werkzeug ansehen:"]
    z += [f"  {ordner}/{b['datei']}  ({dauer_text(b['von'])} bis {dauer_text(b['bis'])})" for b in ana["boegen"]]
    z += ["", "## Ablauf",
          "Abschnitte aus den Schnitten mit Lautheit, darunter das Gesprochene mit Startzeit. Schnitte = weitere harte Schnitte im Abschnitt"]
    for von, bis in abschnitte_aus(dauer, ana["schnitte"]):
        laenge = max(bis - von, 0.1)
        sprache = sum(max(0, min(s["bis"], bis) - max(s["von"], von)) for s in stuecke) / laenge
        wert = lufs(werte, von, bis)
        hinweis = ""
        if wert is not None and gesamt is not None:
            hinweis = " · deutlich leiser als der Rest" if wert < gesamt - 6 else " · deutlich lauter als der Rest" if wert > gesamt + 3 else ""
        innen = [t for t in ana["schnitte"] if von + 0.5 < t < bis - 0.5]
        art = "Sprache" if sprache >= 0.25 else "ohne Sprache (Musik, B Roll)" if tr else "Ton"
        z.append(f"\n{dauer_text(von)} bis {dauer_text(bis)} · {art} · {lufs_text(wert)}{hinweis}"
                 + (f" · Schnitte {' '.join(dauer_text(t) for t in innen)}" if innen else ""))
        z += [f"  {dauer_text(s['von'])}  {s['text']}" for s in alle_saetze if von <= s["von"] < bis]
    z += ["", "## Kommentare an diesem Video"]
    eigene = [k for k in kommentare if k["video"] == v["id"] and not k.get("antwort_auf")]
    z += [f"  [{k['id']}] {dauer_text(k['zeit']) if k.get('zeit') is not None else 'ohne Stelle'}  {k['name']}"
          f"{' (Stagecraft)' if k.get('rolle') == 'team' else ''}: {k['text']}{'  ✓ erledigt' if k.get('erledigt') else ''}" for k in eigene] or ["  noch keine"]
    return "\n".join(z) + "\n"


# ---------------------------------------------------------------- Befehle
def b_liste(a):
    """Alle Links, das neueste zuerst. --kunde Justus nur seine, --neueste 1 nur der letzte, --videos mit jedem Video Link und Drive Datei
    (16.11.2026, Ole: TESS und Alfred sollen auf „den neuesten Link“ oder „alle Links von Justus“ sofort antworten können)."""
    codes = lesen_json(DATEN / "codes.json", {})
    projekte = alle_projekte()
    if a.kunde:
        k = kunde_finden(a.kunde)
        projekte = {s: p for s, p in projekte.items() if gehoert_zu(p, {"id": k["ordner"], "name": k["name"]})}
        if not projekte:
            print(f"Für {k['name']} gibt es noch keinen StageView Link.")
            return
    reihe = sorted(projekte.items(), key=lambda sp: sp[1].get("angelegt") or "", reverse=True)[:a.neueste or None]
    if getattr(a, "karte", False):
        teile = [link_karte(p, codes.get(s, ""), a.videos and len(reihe) == 1) for s, p in reihe[:8]]
        karte = {"art": "stageview", "eintraege": [e for e, _ in teile]}
        if len(teile) == 1 and teile[0][1]:
            karte["videos"] = teile[0][1]
        if a.kunde and len(teile) > 1:
            karte["zusatz"] = reihe[0][1].get("kunde") or ""
        return karte_drucken(karte)
    for s, p in reihe:
        code = codes.get(s, "")
        datum = (p.get("angelegt") or "")[:10]
        datum = f", angelegt {datum[8:10]}.{datum[5:7]}.{datum[:4]}" if datum else ""
        print(f"{code or '------'}  {BASIS_URL}/{code}  {p.get('titel')} · {p.get('kunde')}  ({len(p.get('videos', []))} {'Video' if len(p.get('videos', [])) == 1 else 'Videos'}{datum})  [{s}]")
        if a.videos and code:
            for v in lesen_json(WEB / code / "projekt.json", {}).get("videos", []):
                print(f"     {v['nr']:>3}  {BASIS_URL}/{code}/{v['nr']}  {v['titel']}" + (f"  [{v['gruppe']}]" if v.get("gruppe") else "")
                      + (f"  (Drive: {v['drive']})" if v.get("drive") else ""))


def b_zeigen(a):
    s = schluessel_fuer(a.projekt)
    p = lesen_json(projekt_datei(s), {})
    code = code_fuer(s, False)
    pj = lesen_json(WEB / code / "projekt.json", {}) if code else {}
    nr = {v["id"]: v["nr"] for v in pj.get("videos", [])}
    print(f"{p.get('titel')} · {p.get('kunde')} {('· ' + p['firma']) if p.get('firma') else ''}\nLink: {BASIS_URL}/{code}\nSchlüssel: {s}")
    for v in p.get("videos", []):
        k = v.get("drive") or v.get("id") or v.get("playback_id")
        print(f"  {str(nr.get(k, '-')):>3}  {v.get('titel')}  {('[' + v['gruppe'] + ']  ') if v.get('gruppe') else ''}{v.get('posting') or ''}  {'(noch nicht online)' if k not in nr else BASIS_URL + '/' + code + '/' + str(nr[k])}")


def projekt_anlegen(schluessel, kopfdaten, eintraege, warten):
    with Sperre():
        if projekt_datei(schluessel).exists():
            p = lesen_json(projekt_datei(schluessel), {})
            neu = videos_aufnehmen(p, eintraege)
            print(f"Projekt gibt es schon ({schluessel}), {neu} neue Videos dazu")
        else:
            p = {**{k: v for k, v in kopfdaten.items() if v not in (None, "")}, "videos": [],
                 "angelegt": datetime.now(timezone.utc).isoformat(timespec="seconds")}
            videos_aufnehmen(p, eintraege)
            print(f"Neues Projekt {schluessel} mit {len(p['videos'])} Videos")
        schreiben_json(projekt_datei(schluessel), p)
        print(f"Link: {BASIS_URL}/{code_fuer(schluessel)} (Videos erscheinen, sobald Mux fertig ist)", flush=True)
    nach_mux(p, warten)
    with Sperre():
        melden(bauen(schluessel))


def eintraege_aus(args):
    eintraege = []
    for q in getattr(args, "quelle", None) or []:  # Ordner oder Video, stageview schaut selbst nach (für das Dashboard)
        f = drive_datei(drive_id(q))
        if ist_ordner(f):
            args.ordner = (args.ordner or []) + [f["id"]]
        elif ist_video(f):
            args.video = (args.video or []) + [f["id"]]
        else:
            fehler(f"„{f.get('name')}“ ist weder Ordner noch Video")
    # Kategorien aus Unterordnern (seit 17.11.2026, Ole: „den Unterordner übernehmen, wenn da Videos drin sind“): jeder Ordner
    # direkt unter dem gewählten wird eine Kategorie, alles darunter (EXPORT/Reels …) gehört mit hinein. Videos direkt im Ordner
    # bleiben ohne Kategorie. In jeder Kategorie Querformat (YouTube Video) zuerst, dann nach Ordner und Name
    nach_ordnern = getattr(args, "gruppen_aus_ordnern", False)
    for o in args.ordner or []:
        paare = drive_videos_pfad(drive_id(o), bool(args.unterordner or nach_ordnern))
        namen = [f["name"] for f, _ in paare]
        for f, pfad in sorted(paare, key=lambda x: (x[1][:1], not ist_quer(x[0]), [t.lower() for t in x[1]], x[0]["name"].lower())):
            e = {"drive": f["id"], "titel": titel_aus_dateiname(f["name"], namen), "groesse": int(f.get("size") or 0) or None,
                 "ordner": (f.get("parents") or [None])[0], "datei": f["name"], "md5": f.get("md5Checksum")}
            if nach_ordnern and pfad:
                e["gruppe"] = gruppe_aus_ordner(pfad[0])
            eintraege.append(e)
    for v in args.video or []:
        f = drive_datei(drive_id(v))
        eintraege.append({"drive": f["id"], "titel": titel_aus_dateiname(f["name"]), "groesse": int(f.get("size") or 0) or None,
                          "ordner": (f.get("parents") or [None])[0], "datei": f["name"], "md5": f.get("md5Checksum")})
    if getattr(args, "gruppe", None):  # feste Kategorie für alles, was dieser Aufruf dazu nimmt
        for e in eintraege:
            e["gruppe"] = args.gruppe.strip()
    return eintraege


def b_neu(a):
    eintraege = eintraege_aus(a)
    if not eintraege:
        fehler("keine Videos gefunden (--ordner oder --video angeben)")
    k = kunde_finden(a.kunde) if a.kunde else {"name": "Stagecraft", "firma": "", "ordner": "stagecraft"}
    titel = a.titel
    schluessel = a.schluessel or f"{k['ordner']}-{slug(titel)}"
    projekt_anlegen(schluessel, {"titel": titel, "kunde": a.anzeige or k["name"], "firma": a.firma if a.firma is not None else k.get("firma", ""),
                                 "kunde_ordner": k["ordner"], "dreh": a.dreh, "hinweis": a.hinweis,
                                 "darstellung": "youtube" if a.darstellung == "youtube" else None,
                                 "quellen": quellen_aus(a)}, eintraege, a.warten)


def quellen_aus(a):
    """Die gewählten Drive Ordner, damit „Drive abgleichen“ später neue Videos darin findet (seit 22.11.2026)."""
    tief = bool(a.unterordner or getattr(a, "gruppen_aus_ordnern", False))
    raus = []
    for o in a.ordner or []:
        oid = drive_id(o)
        if oid and oid not in {q["ordner"] for q in raus}:
            raus.append({"ordner": oid, "tief": tief, "gruppen": bool(getattr(a, "gruppen_aus_ordnern", False))})
    return raus or None


def b_content_day(a):
    os_aktualisieren()
    k = kunde_finden(a.kunde)
    tage = content_days(k["ordner"])
    if not tage:
        fehler(f"keine Content Days in den Transkripten von {k['ordner']} (Feld content_day fehlt)")
    if a.name:
        tag = tage.get(a.name.capitalize()) or fehler(f"Content Day {a.name} nicht gefunden, da sind: {', '.join(tage)}")
    else:
        tag = max(tage.values(), key=lambda t: t["dreh"] or "")
    titel = f"Content Day {tag['name']}"
    name, firma = k["name"], k.get("firma", "")
    m = re.match(r"^(.*?)\s*\((.*)\)$", tag.get("kunde") or "")  # Transkripte schreiben "Justus Vogelsang (CoMakler)", schöner als das Register
    if m:
        name, firma = m.groups()
    print(f"{name}: {titel} (Dreh {tag['dreh'] or 'unbekannt'}), {len(tag['videos'])} Videos aus dem Content Brain")
    projekt_anlegen(f"{k['ordner']}-{slug(titel)}", {"titel": titel, "kunde": name, "firma": firma,
                                                      "kunde_ordner": k["ordner"], "dreh": tag["dreh"]}, tag["videos"], a.warten)


def b_dazu(a):
    s = schluessel_fuer(a.projekt)
    eintraege = eintraege_aus(a)
    if a.titel and len(eintraege) == 1:
        eintraege[0]["titel"] = a.titel
    with Sperre():  # neue Ordner als Quelle dazu, damit der Drive Abgleich auch dort nach neuen Videos sieht
        p = lesen_json(projekt_datei(s), {})
        da = {q["ordner"] for q in p.get("quellen") or []}
        neu = [q for q in quellen_aus(a) or [] if q["ordner"] not in da]
        if neu:
            p["quellen"] = (p.get("quellen") or []) + neu
            schreiben_json(projekt_datei(s), p)
    projekt_anlegen(s, p, eintraege, a.warten)


ALLGEMEINE_ORDNER = re.compile(r"^(export|exports|final|finals|fertig|videos?|reels?|schnitt|cuts?|output|render)$", re.I)


def b_vorbereiten(a):
    """Für „Neuer Link“ im Dashboard (Ole, 16.11.2026): Drive Link einfügen, die Videos gehen sofort zu Mux, während Titel und Kunde
    noch eingetragen werden. Legt kein Projekt an. `neu` mit denselben Quellen nimmt die fertigen Assets danach einfach mit.
    Meldet sich in Zeilen „@ {json}“, die die API fürs Dashboard liest. Nimmt nach --aufheben Minuten niemand die neu angelegten
    Videos in einen Link, löscht es sie bei Mux wieder (Fenster zu, Seite zu), damit nichts Speicher kostet."""
    start = time.time()

    def melde(**d):
        print("@ " + json.dumps(d, ensure_ascii=False), flush=True)

    melde(phase="drive")
    vids, name, unter, tief = [], None, 0, False
    for q in a.quelle or []:
        f = drive_datei(drive_id(q))
        if ist_ordner(f):
            alle = drive_videos(f["id"], True)
            direkt = [x for x in alle if f["id"] in (x.get("parents") or [])]
            nimm = alle if (a.unterordner or not direkt) else direkt
            tief = tief or nimm is alle and len(alle) > len(direkt)
            unter += 0 if nimm is alle else len(alle) - len(direkt)
            if not name:  # Titelvorschlag: der Ordner, bei „Export“ und ähnlichen der Ordner darüber
                name = f["name"]
                if ALLGEMEINE_ORDNER.match(name.strip()) and f.get("parents"):
                    try:
                        name = drive_datei(f["parents"][0]).get("name") or name
                    except (SystemExit, Exception):
                        pass
            namen = [x["name"] for x in nimm]
            vids += [(x, titel_aus_dateiname(x["name"], namen)) for x in sorted(nimm, key=lambda x: x["name"].lower())]
        elif ist_video(f):
            name = name or titel_aus_dateiname(f["name"])
            vids.append((f, titel_aus_dateiname(f["name"])))
        else:
            fehler(f"„{f.get('name')}“ ist weder Ordner noch Video")
    if not vids:
        fehler("In dem Ordner sind keine Videos")
    melde(phase="gefunden", name=name, tief=tief, unterordner=unter,
          videos=[{"drive": f["id"], "titel": t, "groesse": int(f.get("size") or 0)} for f, t in vids])

    assets, meine, neu = mux_assets(), {}, []
    for f, t in vids:
        did, x = f["id"], assets.get(f["id"])
        if x and x.get("status") in ("ready", "preparing"):
            meine[did] = x["id"]
            continue
        try:
            link_freigeben(did)
        except Exception as e:
            print(f"Hinweis: Freigabe für {t} nicht geprüft ({str(e)[:120]})", flush=True)
        n = mux_neu(did, t)
        meine[did], neu = n["id"], neu + [did]
        melde(angelegt=n["id"], drive=did)

    letzte, ende = None, start + a.warten * 60
    while time.time() < ende:
        liste = {x["id"]: x for x in mux("/video/v1/assets?limit=100")["data"]}
        stand = {}
        for did, aid in meine.items():
            x = liste.get(aid) or mux(f"/video/v1/assets/{aid}")["data"]
            pr = x.get("progress") or {}
            stand[did] = {"status": x.get("status"), "zustand": pr.get("state"),
                          "prozent": 100 if x.get("status") == "ready" else max(0, min(99, int(pr.get("progress") or 0)))}
        if stand != letzte:
            melde(phase="mux", stand=stand)
            letzte = stand
        if all(s["status"] in ("ready", "errored") for s in stand.values()):
            break
        time.sleep(4)
    fehlt = [d for d, s in (letzte or {}).items() if s["status"] == "errored"]
    melde(phase="fertig", fehler=len(fehlt))

    # Aufräumen: neu angelegte Videos, die keiner in einen Link nimmt, nach einer Weile wieder löschen
    benutzt = lambda: {v.get("drive") for p in alle_projekte().values() for v in p.get("videos", [])}
    while neu and time.time() < start + a.aufheben * 60:
        if all(d in benutzt() for d in neu):
            melde(phase="verwendet")
            return
        time.sleep(30)
    frei = [d for d in neu if d not in benutzt()]
    for d in frei:
        mux(f"/video/v1/assets/{meine[d]}", "DELETE")
    if frei:
        melde(phase="aufgeraeumt", geloescht=len(frei))


# ---------------------------------------------------------------- Drive Abgleich (seit 22.11.2026)
# Ole, 22.11.2026: „einen Drive Update Button, wo er neue Videos neu erkennt, die im selben Ordner liegen“ und „das soll einfach
# immer aktiv aktualisiert werden, dass wenn ein Video nicht mehr im Ordner ist, es nicht mehr angezeigt wird“.
# Immer (alle 5 Minuten für alle Links, Cron von hermes): Videos, die im Papierkorb liegen, gelöscht oder aus ihrem Ordner
# verschoben sind, verschwinden von der Seite (Liste drive_weg im Projekt, Nummer und Kommentare bleiben). Liegen sie wieder
# im Ordner, kommen sie von selbst an ihren alten Platz zurück. Auf Knopfdruck (--neue) dazu neue Videos aus dem Ordner.
# Vorsicht eingebaut: nur eindeutige Antworten vom Drive zählen (Fehler = nichts ändern), und ein Link wird nie ganz leer
# geräumt (dann eher ein Hinweis, z.B. wenn der Agent den Zugriff auf den Ordner verloren hat).

def drive_info(did):
    """(datei, klar): datei None und klar True heißt gelöscht oder nicht mehr sichtbar, klar False heißt Fehler, nichts ändern."""
    try:
        return drive().files().get(fileId=did, fields="id,name,parents,trashed,createdTime,modifiedTime,size,md5Checksum,mimeType",
                                   **ALLE).execute(), True
    except Exception as e:
        return None, ("404" in str(e) or "notFound" in str(e))


def zeitpunkt(iso):
    try:
        return datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
    except ValueError:
        return None


def name_kern(name):
    """Dateiname zum Vergleichen: ohne Video Endung, klein, Leerzeichen zusammengefasst („Reel 3.MOV“ = „reel 3“)."""
    n = unicodedata.normalize("NFC", str(name or "")).strip().lower()
    return " ".join(re.sub(r"\.(mp4|mov|m4v|webm)$", "", n).split())


def neue_fassung_melden(code, video, alt=None, still=False):
    """Kommentar Dienst: mit alt Kommentare, Freigabe Status und Verlauf auf die neue Drive Datei umziehen, ohne still ein Eintrag im
    Verlauf. None, wenn der Dienst nicht antwortet (dann bleibt alles, wie es ist, und der nächste Abgleich versucht es noch einmal)."""
    team = env_datei(HAUS / "videos-api.env").get("VIDEOS_TEAM_KEY", "")
    daten = {"video": video, **({"alt": alt} if alt else {}), **({"still": True} if still else {})}
    req = urllib.request.Request(f"{API}/admin/projekt/{code}/neue-fassung", method="POST", data=json.dumps(daten).encode(),
                                 headers={"Content-Type": "application/json", "X-Team": team})
    try:
        return json.load(urllib.request.urlopen(req, timeout=20))
    except Exception as e:
        print(f"  Hinweis: Kommentar Dienst nicht erreicht ({type(e).__name__}), neue Fassung beim nächsten Abgleich", flush=True)
        return None


def drive_abgleich(s, neue=False, trocken=False, warten=0, leise=False):
    """Gleicht einen Link mit dem Drive ab. Gibt {weg, zurueck, neu, ersetzt, fertig, hinweis} mit Titeln zurück.

    Neue Fassung (seit 25.11.2026, Ole: „wenn das alte Video mit einem neuen Video mit dem selben Namen replaced wurde, erkennt das
    StageView noch nicht“), zwei Wege:
      a) dieselbe Drive Datei mit neuem Inhalt (Drive „Vorhandene Datei ersetzen“, neuer Export über Google Drive am Mac), erkannt an
         der Prüfsumme (md5). Videos von vorher haben noch keine: dann zählt eine andere Größe, wenn die Datei nach dem letzten Mux
         Upload geändert wurde, sonst wird die Prüfsumme nur nachgetragen.
      b) eine neue Datei mit demselben Namen im selben Ordner. Die alte liegt im Papierkorb, ist gelöscht (beides prüft auch der Cron)
         oder liegt noch daneben (nur mit --neue, also über den Knopf, und nur wenn die neue später kam).
    Beides ersetzt das Video an seinem Platz: Nummer, Link, Titel, Kommentare und Freigabe Status bleiben. Bis Mux fertig ist, spielt
    die Seite die bisherige Fassung (fassung_offen, bei b über vorher), danach wechselt sie von selbst (spätestens im nächsten Cron)."""
    p = lesen_json(projekt_datei(s), {})
    code = code_fuer(s, False)
    raus = {"weg": [], "zurueck": [], "neu": [], "ersetzt": [], "fertig": [], "hinweis": None}
    if not code:
        return raus
    vids = [v for v in p.get("videos", []) if v.get("drive")]
    ausgeblendet = [w for w in p.get("drive_weg") or [] if w.get("drive")]
    if not vids and not ausgeblendet and not neue:
        return raus
    bekannte_ordner = {v["ordner"] for v in vids + ausgeblendet if v.get("ordner")} | {q["ordner"] for q in p.get("quellen") or []}

    stand, ordner_neu, infos = {}, {}, {}  # drive → da | weg | unklar | weg404 ; drive → Ordner ; drive → Datei im Drive
    for v in vids + ausgeblendet:
        f, klar = drive_info(v["drive"])
        if f:
            infos[v["drive"]] = f
        if not klar:
            stand[v["drive"]] = "unklar"
        elif f is None:
            stand[v["drive"]] = "weg404"
        elif f.get("trashed"):
            stand[v["drive"]] = "weg"
        else:
            eltern = f.get("parents") or []
            if not v.get("ordner"):  # ältere Videos: Ordner beim ersten Abgleich nachtragen
                stand[v["drive"]] = "da"
                if eltern:
                    ordner_neu[v["drive"]] = eltern[0]
            elif v["ordner"] in eltern:
                stand[v["drive"]] = "da"
            elif set(eltern) & bekannte_ordner:  # nur in einen anderen Ordner des Links gewandert (z.B. andere Kategorie)
                stand[v["drive"]] = "da"
                ordner_neu[v["drive"]] = next(e for e in eltern if e in bekannte_ordner)
            else:
                stand[v["drive"]] = "weg"
    sichtbar = any(stand.get(v["drive"]) == "da" for v in vids + ausgeblendet)
    # 404 zählt nur, wenn der Agent im selben Link andere Videos sieht (sonst eher Zugriff verloren als gelöscht)
    weg = [v for v in vids if stand.get(v["drive"]) == "weg" or (stand.get(v["drive"]) == "weg404" and sichtbar)]
    zurueck = [w for w in ausgeblendet if stand.get(w["drive"]) == "da"]
    nummern = lesen_json(DATEN / "nummern.json", {}).get(code) or {}
    bekannt = ({v["drive"] for v in vids} | {w["drive"] for w in ausgeblendet} | set(nummern) | set(p.get("entfernt") or [])
               | {x for v in vids + ausgeblendet for x in v.get("vorher") or []})

    # a) dieselbe Datei, neuer Inhalt. Nebenbei Prüfsumme, Größe und Dateiname nachtragen (nachtrag, ohne neu zu bauen)
    neu_inhalt, nachtrag, mux_alle = [], {}, None
    for v in vids:
        f = infos.get(v["drive"])
        if stand.get(v["drive"]) != "da" or not f:
            continue
        md5, groesse = f.get("md5Checksum"), int(f.get("size") or 0) or None
        if v.get("md5"):
            if md5 and md5 != v["md5"]:
                neu_inhalt.append(v)
        elif md5 and v.get("groesse") and groesse and groesse != v["groesse"]:
            if mux_alle is None:
                mux_alle = mux_assets(alle=True)
            zuletzt = max((int(x.get("created_at") or 0) for x in mux_alle.get(v["drive"]) or []), default=0)
            geaendert = zeitpunkt(f.get("modifiedTime"))
            if zuletzt and geaendert and geaendert.timestamp() > zuletzt + 60:
                neu_inhalt.append(v)
        werte = {k: w for k, w in (("md5", md5), ("groesse", groesse), ("datei", f.get("name"))) if w}
        if any(v.get(k) != w for k, w in werte.items()):
            nachtrag[v["drive"]] = werte

    kandidaten = []
    if neue:
        if p.get("quellen"):  # gewählte Ordner: alles Neue darin, wie beim Anlegen (Unterordner, Kategorien)
            for q in p["quellen"]:
                ns = argparse.Namespace(ordner=[q["ordner"]], video=None, quelle=None, unterordner=q.get("tief"),
                                        gruppen_aus_ordnern=q.get("gruppen"), gruppe=None)
                kandidaten += [e for e in eintraege_aus(ns) if e["drive"] not in bekannt and e["drive"] not in {k["drive"] for k in kandidaten}]
        else:
            # Ältere Links ohne gemerkten Ordner: nur Ordner, aus denen der Link damals alle Videos genommen hat. Liegen dort
            # andere Videos von vor dem Anlegen (gemeinsamer Export Ordner eines Kunden), bleibt der Ordner außen vor.
            # Videos, die schon in einem anderen Link stecken, zählen in beiden Fällen nicht
            andere = {v.get("drive") for s2, p2 in alle_projekte().items() if s2 != s for v in p2.get("videos", [])}
            angelegt = zeitpunkt(p.get("angelegt"))
            ordner = {ordner_neu.get(v["drive"]) or v.get("ordner") for v in vids if stand.get(v["drive"]) == "da"} - {None}
            for o in sorted(ordner):
                kinder = [f for f in drive_kinder(o) if ist_video(f) and f["id"] not in andere]
                frueher = [f for f in kinder if angelegt and (zeitpunkt(f.get("createdTime")) or angelegt) <= angelegt]
                if not angelegt or any(f["id"] not in bekannt for f in frueher):
                    continue
                gruppen = [v.get("gruppe") for v in vids if (ordner_neu.get(v["drive"]) or v.get("ordner")) == o]
                gruppe = max(set(gruppen), key=gruppen.count) if gruppen else None
                namen = [f["name"] for f in kinder]
                for f in kinder:
                    if f["id"] not in bekannt:
                        kandidaten.append({"drive": f["id"], "titel": titel_aus_dateiname(f["name"], namen),
                                           "groesse": int(f.get("size") or 0) or None, "ordner": o, "gruppe": gruppe,
                                           "datei": f["name"], "md5": f.get("md5Checksum")})

    # b) neue Datei mit demselben Namen im selben Ordner. Ohne --neue nur in den Ordnern von Videos, die gerade fehlen
    fehlen, zurueck_ids = {v["drive"] for v in weg}, {w["drive"] for w in zurueck}
    alte = [(v, "weg" if v["drive"] in fehlen else "da") for v in vids if v["drive"] in fehlen or (neue and stand.get(v["drive"]) == "da")]
    alte += [(w, "aus") for w in ausgeblendet if w["drive"] not in zurueck_ids]
    ordner_von = lambda v: ordner_neu.get(v["drive"]) or v.get("ordner") or ((infos.get(v["drive"]) or {}).get("parents") or [None])[0]
    frische = list(kandidaten)
    for o in sorted({ordner_von(v) for v, art in alte if art != "da"} - {None}):
        try:
            kinder = drive_kinder(o)
        except Exception:
            continue
        for f in kinder:
            if ist_video(f) and f["id"] not in bekannt and f["id"] not in {k["drive"] for k in frische}:
                frische.append({"drive": f["id"], "groesse": int(f.get("size") or 0) or None, "ordner": o, "datei": f["name"],
                                "md5": f.get("md5Checksum")})
    paare = []
    for k in frische:
        kern = name_kern(k.get("datei"))
        if not kern or sum(1 for x in frische if x["ordner"] == k["ordner"] and name_kern(x.get("datei")) == kern) != 1:
            continue
        def passt(v):
            alt_name = v.get("datei") or (infos.get(v["drive"]) or {}).get("name")
            if alt_name:
                return name_kern(alt_name) == kern
            return name_kern(v.get("titel")) == name_kern(titel_aus_dateiname(k["datei"]))  # endgültig gelöscht, ohne gemerkten Namen
        treffer = [(v, art) for v, art in alte if ordner_von(v) == k["ordner"] and passt(v)]
        if len(treffer) != 1 or any(v is pv for pv, _, _ in paare):
            continue
        v, art = treffer[0]
        if art == "da":  # die alte Datei liegt noch daneben: nur, wenn die neue später ins Drive kam
            alt_t = zeitpunkt((infos.get(v["drive"]) or {}).get("createdTime"))
            neu_t = zeitpunkt((drive_info(k["drive"])[0] or {}).get("createdTime"))
            if not (alt_t and neu_t and neu_t > alt_t):
                continue
        paare.append((v, k, art))
    ersetzt_ids = {v["drive"] for v, _, _ in paare}
    weg = [v for v in weg if v["drive"] not in ersetzt_ids]
    kandidaten = [k for k in kandidaten if k["drive"] not in {k2["drive"] for _, k2, _ in paare}]
    if vids and weg and len(weg) == len(vids):
        raus["hinweis"] = (f"Alle {len(vids)} Videos fehlen im Drive (Papierkorb oder kein Zugriff). Die Seite bleibt, wie sie ist, "
                           "bitte prüfen, ob das so gewollt ist")
        weg = []

    # Neue Fassungen von früher, die bei Mux inzwischen fertig sind (oder gescheitert)
    fertig_ids, fehl_ids = set(), set()
    for v in vids:
        if v.get("fassung_offen") and v["drive"] not in {x["drive"] for x in neu_inhalt} | ersetzt_ids:
            try:
                st = mux(f"/video/v1/assets/{v['fassung_offen']}")["data"].get("status")
            except SystemExit:
                st = "errored"
            if st == "ready":
                fertig_ids.add(v["drive"])
            elif st == "errored":
                fehl_ids.add(v["drive"])
                print(f"  Mux konnte die neue Fassung von {v.get('titel')} nicht verarbeiten, die bisherige läuft weiter", flush=True)

    titel = lambda v: v.get("titel") or v["drive"]
    raus.update(weg=[titel(v) for v in weg], zurueck=[titel(w) for w in zurueck], neu=[k["titel"] for k in kandidaten],
                ersetzt=[titel(v) for v in neu_inhalt] + [titel(v) for v, _, _ in paare],
                fertig=[titel(v) for v in vids if v["drive"] in fertig_ids])
    # Hinweis am Link merken (App und Dashboard zeigen ihn), ins Protokoll nur, wenn er neu ist
    raus["hinweis_neu"] = bool(raus["hinweis"]) and raus["hinweis"] != p.get("drive_hinweis")
    etwas = weg or zurueck or kandidaten or ordner_neu or nachtrag or neu_inhalt or paare or fertig_ids or fehl_ids
    if not trocken and raus["hinweis"] != p.get("drive_hinweis") and not etwas:
        with Sperre():
            p = lesen_json(projekt_datei(s), {})
            if raus["hinweis"]:
                p["drive_hinweis"] = raus["hinweis"]
            else:
                p.pop("drive_hinweis", None)
            schreiben_json(projekt_datei(s), p)
    if trocken or not etwas:
        return raus

    # Neue Fassungen zu Mux, bevor etwas am Link geändert wird (klappt das nicht, versucht es der nächste Abgleich)
    hochgeladen = {}  # Drive Datei der neuen Fassung → Mux Asset
    for did, name in [(v["drive"], titel(v)) for v in neu_inhalt] + [(k["drive"], titel(v)) for v, k, _ in paare]:
        try:
            if link_freigeben(did):
                print(f"  Drive Link freigegeben: {name}")
        except Exception as e:
            print(f"  Hinweis: Freigabe für {name} nicht geprüft ({str(e)[:120]})")
        try:
            hochgeladen[did] = mux_neu(did, name)["id"]
            print(f"  neue Fassung zu Mux: {name}", flush=True)
        except (SystemExit, Exception) as e:
            print(f"  neue Fassung von {name} nicht zu Mux ({type(e).__name__}), beim nächsten Abgleich noch einmal", flush=True)
    for v in neu_inhalt:
        if v["drive"] not in hochgeladen:
            nachtrag.pop(v["drive"], None)  # Prüfsumme nicht nachtragen, sonst sähe der nächste Abgleich die Änderung nicht mehr

    jetzt_iso = datetime.now(timezone.utc).isoformat(timespec="seconds")
    doppelt, umgezogen, inhalt_ok = [], [], {}
    # ausblenden: was fehlt (nach der Prüfung „alle fehlen“) und fehlende, deren neue Fassung gerade nicht zu Mux kam
    weg_ids = {v["drive"] for v in weg} | {v["drive"] for v, k, art in paare if art == "weg" and k["drive"] not in hochgeladen}
    with Sperre():  # frisch lesen, damit nichts überschrieben wird, was in der Zwischenzeit dazukam
        p = lesen_json(projekt_datei(s), {})
        alle_nr = lesen_json(DATEN / "nummern.json", {})
        feste = alle_nr.setdefault(code, {})
        jetzt_da = {v.get("drive"): v for v in p.get("videos", []) + (p.get("drive_weg") or []) if v.get("drive")}
        ersatz = {}
        for v, k, art in paare:
            if k["drive"] not in hochgeladen:
                continue
            if v["drive"] not in jetzt_da or k["drive"] in jetzt_da:  # ein anderer Abgleich war schneller
                doppelt.append(hochgeladen[k["drive"]])
                continue
            if neue_fassung_melden(code, k["drive"], alt=v["drive"]) is None:  # Kommentare zuerst, sonst hingen sie an der alten Datei
                doppelt.append(hochgeladen[k["drive"]])
                continue
            ersatz[v["drive"]] = k
            umgezogen.append((v["drive"], k["drive"]))
        for v in neu_inhalt:
            jetzt = jetzt_da.get(v["drive"])
            if v["drive"] not in hochgeladen:
                continue
            if not jetzt or (jetzt.get("md5") and jetzt["md5"] == (nachtrag.get(v["drive"]) or {}).get("md5")):
                doppelt.append(hochgeladen[v["drive"]])  # schon von einem anderen Abgleich ersetzt
                continue
            inhalt_ok[v["drive"]] = hochgeladen[v["drive"]]

        def tauschen(v):
            k, alt = ersatz[v["drive"]], v["drive"]
            v["vorher"] = [x for x in v.get("vorher") or [] if x not in (alt, k["drive"])] + [alt]
            v.update({x: k[x] for x in ("drive", "ordner", "groesse", "md5", "datei") if k.get(x)})
            v["fassung_offen"] = hochgeladen[k["drive"]]
            if alt in feste and k["drive"] not in feste:  # gleiche Nummer, gleicher Link /<code>/<nr>
                feste[k["drive"]] = feste.pop(alt)
            return v

        bleibt, raus_neu = [], []
        for i, v in enumerate(p.get("videos", [])):
            did = v.get("drive")
            if did in ordner_neu:
                v["ordner"] = ordner_neu[did]
            if did in ersatz:
                bleibt.append(tauschen(v))
                continue
            if did in nachtrag:
                v.update(nachtrag[did])
            if did in fertig_ids or did in fehl_ids:
                v.pop("fassung_offen", None)
            if did in inhalt_ok:
                v["fassung_offen"] = inhalt_ok[did]
                (DATEN / "transkripte" / f"{did}.json").unlink(missing_ok=True)  # Transkript der alten Fassung
            if did in weg_ids:
                raus_neu.append({**v, "stelle": i, "weg_am": jetzt_iso})
            else:
                bleibt.append(v)
        rest = []
        for w in sorted(p.get("drive_weg") or [], key=lambda w: w.get("stelle", 0)):
            if w.get("drive") in ersatz:
                v = tauschen({k: x for k, x in w.items() if k not in ("stelle", "weg_am")})
                bleibt.insert(min(w.get("stelle", len(bleibt)), len(bleibt)), v)
            elif w.get("drive") in zurueck_ids and w["drive"] not in {v.get("drive") for v in bleibt}:
                v = {k: x for k, x in w.items() if k not in ("stelle", "weg_am")}
                if w["drive"] in ordner_neu:
                    v["ordner"] = ordner_neu[w["drive"]]
                bleibt.insert(min(w.get("stelle", len(bleibt)), len(bleibt)), v)
            elif w.get("drive") not in zurueck_ids:
                rest.append(w)
        p["videos"] = bleibt
        if raus["hinweis"]:
            p["drive_hinweis"] = raus["hinweis"]
        else:
            p.pop("drive_hinweis", None)
        if rest + raus_neu:
            p["drive_weg"] = rest + raus_neu
        else:
            p.pop("drive_weg", None)
        videos_aufnehmen(p, kandidaten)
        schreiben_json(projekt_datei(s), p)
        if ersatz:
            schreiben_json(DATEN / "nummern.json", alle_nr)
    for aid in doppelt:  # nur, was dieser Lauf eben selbst angelegt hat und nirgends steckt
        try:
            mux(f"/video/v1/assets/{aid}", "DELETE")
        except SystemExit:
            pass
    raus["ersetzt"] = [titel(v) for v in neu_inhalt if v["drive"] in inhalt_ok] + [titel(v) for v, _, _ in paare if v["drive"] in ersatz]
    for did in inhalt_ok:
        neue_fassung_melden(code, did)
    neu_bauen = weg_ids or zurueck or kandidaten or ersatz or inhalt_ok or fertig_ids
    if ersatz:  # sofort bauen: die Kommentare hängen schon an der neuen Datei, die Seite spielt bis Mux fertig ist die alte
        with Sperre():
            bauen(s)
        for alt, neu in umgezogen:  # was in den Sekunden dazwischen noch an der alten Datei landete
            neue_fassung_melden(code, neu, alt=alt, still=True)
    if kandidaten:
        nach_mux(p, warten)
    offen_ids = [a for d, a in hochgeladen.items() if a not in doppelt and (d in inhalt_ok or d in {k["drive"] for k in ersatz.values()})]
    if offen_ids and warten:
        fertig_jetzt = set(offen_ids) - mux_warten(offen_ids, warten)
        if fertig_jetzt:
            with Sperre():
                p = lesen_json(projekt_datei(s), {})
                for v in p.get("videos", []):
                    if v.get("fassung_offen") in fertig_jetzt:
                        v.pop("fassung_offen", None)
                schreiben_json(projekt_datei(s), p)
        elif not kandidaten:
            print("  neue Fassung noch bei Mux in Arbeit, bis dahin läuft die bisherige, danach wechselt die Seite von selbst", flush=True)
    if neu_bauen:
        with Sperre():
            ergebnis = bauen(s)
        if not leise:
            melden(ergebnis)
    return raus


def abgleich_text(r):
    teile = []
    if r.get("ersetzt"):
        n = len(r["ersetzt"])
        teile.append(f"{n} {'Video durch eine neue Fassung' if n == 1 else 'Videos durch neue Fassungen'} ersetzt")
    if r.get("fertig"):
        n = len(r["fertig"])
        teile.append(f"{n} {'neue Fassung' if n == 1 else 'neue Fassungen'} jetzt auf der Seite")
    if r["neu"]:
        teile.append(f"{len(r['neu'])} {'neues Video' if len(r['neu']) == 1 else 'neue Videos'} dazu")
    if r["weg"]:
        teile.append(f"{len(r['weg'])} nicht mehr im Drive, ausgeblendet")
    if r["zurueck"]:
        teile.append(f"{len(r['zurueck'])} wieder im Drive, zurück auf der Seite")
    return ", ".join(teile)


def b_marker(a):
    """Kommentare eines Videos als Marker für DaVinci Resolve (seit 23.11.2026): EDL zum Importieren (Timeline > Import > Timeline
    Markers from EDL) oder JSON für den direkten Weg über Resolve (Bild ab Timeline Anfang, Farbe, Text)."""
    s = schluessel_fuer(a.projekt)
    code = code_fuer(s, False) or fehler("Link hat noch keinen Code")
    team = env_datei(HAUS / "videos-api.env").get("VIDEOS_TEAM_KEY", "")
    url = f"{API}/admin/projekt/{code}/video/{a.nr}/marker?format={a.format}&start={urllib.parse.quote(a.start)}"
    try:
        inhalt = urllib.request.urlopen(urllib.request.Request(url, headers={"X-Team": team}), timeout=20).read().decode()
    except urllib.error.HTTPError as e:
        fehler(f"Marker: {e.code} {e.read().decode()[:200]}")
    if a.datei:
        Path(a.datei).write_text(inhalt, encoding="utf-8")
        print(f"Marker gespeichert: {a.datei}")
    else:
        print(inhalt)


def b_drive_abgleich(a):
    if a.alle:
        liste = [s for s in alle_projekte() if code_fuer(s, False)]
    else:
        liste = [schluessel_fuer(a.projekt or fehler("Link angeben oder --alle"))]
    summe = {"weg": 0, "zurueck": 0, "neu": 0, "ersetzt": 0}
    for s in liste:
        try:
            r = drive_abgleich(s, neue=a.neue and not a.alle, trocken=a.trocken, warten=a.warten, leise=a.alle)
        except (SystemExit, Exception) as e:  # ein Link mit Fehler hält die anderen nicht auf
            if not a.alle:
                raise
            print(f"{datetime.now().isoformat(timespec='seconds')} {code_fuer(s, False)}: übersprungen ({type(e).__name__})", flush=True)
            continue
        for k in summe:
            summe[k] += len(r[k])
        text = abgleich_text(r)
        if a.alle:  # Cron Protokoll: nur Code und Zahlen, und nur wenn sich etwas tut
            if text or r["hinweis_neu"]:
                print(f"{datetime.now().isoformat(timespec='seconds')} {code_fuer(s, False)}: {text or 'Hinweis'}"
                      f"{' (Probe)' if a.trocken else ''}", flush=True)
            continue
        for titel in r["ersetzt"]:
            print(f"  neue Fassung: {titel}")
        for titel in r["neu"]:
            print(f"  neu: {titel}")
        for titel in r["weg"]:
            print(f"  nicht mehr im Drive: {titel}")
        for titel in r["zurueck"]:
            print(f"  wieder da: {titel}")
        print("@ " + json.dumps({"phase": "fertig", **{k: len(r[k]) for k in summe}, "hinweis": r["hinweis"]}, ensure_ascii=False))
        ende = text or ("keine neuen Videos oder Fassungen im Ordner, alles aktuell" if a.neue else "alles aktuell")
        if r["hinweis"]:  # letzte Zeile zeigen App und Dashboard, deshalb der Hinweis dort
            ende = f"{text}. {r['hinweis']}" if text else r["hinweis"]
        print(f"Drive geprüft{' (Probe, nichts geändert)' if a.trocken else ''}: {ende}", flush=True)


def b_versatz(a):
    """Lippensynchron prüfen (seit 16.11.2026): pro Video, ob die Drive Datei Bild und Ton per Edit List verschiebt und bei Mux
    deshalb versetzt läuft. Schon bereinigte (Direct Upload) zählen als in Ordnung. --reparieren bringt die betroffenen bereinigt
    neu zu Mux: Nummern, Links und Kommentare bleiben, die Seite nimmt die neue Fassung, sobald sie fertig ist (asset_rang),
    die alten danach mit `stageview mux --aufraeumen --ja` löschen."""
    nur = schluessel_fuer(a.projekt) if a.projekt else None
    alle, gesehen, betroffen = mux_assets(alle=True), set(), []
    for s, p in alle_projekte().items():
        if nur and s != nur:
            continue
        code = code_fuer(s, False)
        for v in p.get("videos", []):
            did = v.get("drive")
            if not did or did in gesehen:
                continue
            gesehen.add(did)
            beste = (alle.get(did) or [{}])[0]
            if beste.get("upload_id"):
                print(f"  ok (bereinigt)  {code} {v.get('titel')}")
                continue
            try:
                w = edit_versatz(did)
            except Exception as e:
                print(f"  ?               {code} {v.get('titel')} ({str(e)[:80]})")
                continue
            if abs(w) > VERSATZ_GRENZE:
                betroffen.append((s, did, v.get("titel") or did))
                print(f"  versetzt {w:+.2f} s {code} {v.get('titel')}")
            else:
                print(f"  ok              {code} {v.get('titel')}")
    print(f"{len(betroffen)} von {len(gesehen)} Videos laufen bei Mux versetzt")
    if not betroffen or not a.reparieren:
        if betroffen:
            print("Reparieren mit --reparieren (lädt jedes betroffene Video einmal auf VPS 2, verpackt es neu und lädt es zu Mux)")
        return
    angelegt = []
    for s, did, titel in betroffen:
        print(f"  bereinigt zu Mux: {titel}", flush=True)
        angelegt.append(mux_bereinigt(did)["id"])
    offen = mux_warten(angelegt, a.warten) if a.warten else set(angelegt)
    # Alle Links neu bauen, in denen eins der Videos steckt (ein Drive Video kann in mehreren Links sein, z.B. Test Links)
    ids = {did for _, did, _ in betroffen}
    with Sperre():
        for s in sorted(s for s, p in alle_projekte().items() if any(v.get("drive") in ids for v in p.get("videos", []))):
            melden(bauen(s))
    if offen:
        print(f"{len(offen)} noch in Arbeit bei Mux, später `stageview bauen`")


def b_mux_weg(a):
    """Assets bei Mux löschen, die in keinem Link stecken (für Abbrechen im Dashboard). Benutzte bleiben immer."""
    benutzt = {v.get("drive") for p in alle_projekte().values() for v in p.get("videos", [])}
    weg = 0
    for aid in a.asset:
        if not re.fullmatch(r"[A-Za-z0-9]{10,80}", aid):
            continue
        try:
            x = mux(f"/video/v1/assets/{aid}")["data"]
        except SystemExit:
            continue  # schon weg
        did = str(x.get("passthrough") or "").removeprefix("drive:")
        if did in benutzt:
            print(f"bleibt (steckt in einem Link): drive:{did}")
            continue
        mux(f"/video/v1/assets/{aid}", "DELETE")
        weg += 1
    print(f"{weg} gelöscht")


def b_gruppe(a):
    """Videos einer Kategorie zuordnen (Nummern wie auf der Seite), mit --weg wieder herausnehmen, mit --reihenfolge die
    Kategorien sortieren. Links, Nummern und Kommentare bleiben, die Seite wird neu gebaut."""
    s = schluessel_fuer(a.projekt)
    if not a.nr and not a.reihenfolge:
        fehler("Nummern der Videos fehlen (z.B. 1 2 5 oder 1,2,5)")
    if a.nr and not (a.name or a.weg):
        fehler("--name \"Kategorie\" oder --weg angeben")
    pj = projekt_json(code_fuer(s, False))
    nach_nr = {str(v["nr"]): v["id"] for v in pj["videos"]}
    nrs = [n for x in a.nr for n in re.split(r"[,\s]+", x) if n]
    with Sperre():
        p = lesen_json(projekt_datei(s), {})
        for n in nrs:
            vid = nach_nr.get(n) or fehler(f"Video {n} ist nicht auf der Seite")
            for v in p["videos"]:
                if vid in (v.get("drive"), v.get("id"), v.get("playback_id")):
                    if a.weg:
                        v.pop("gruppe", None)
                    else:
                        v["gruppe"] = a.name.strip()
        if a.reihenfolge:
            p["gruppen"] = [g.strip() for g in a.reihenfolge if g.strip()]
        schreiben_json(projekt_datei(s), p)
        melden(bauen(s))
    print(("ohne Kategorie: " if a.weg else f"Kategorie „{a.name}“: ") + ", ".join(nrs) if nrs else "Reihenfolge gesetzt")


def b_titel(a):
    a.titel = a.titel_option or a.titel
    if not a.titel:
        fehler("neuer Titel fehlt")
    s = schluessel_fuer(a.projekt)
    code = code_fuer(s, False)
    pj = projekt_json(code)
    ziel = next((v for v in pj["videos"] if str(v["nr"]) == str(a.nr)), None) or fehler(f"Video {a.nr} nicht im Projekt")
    with Sperre():
        p = lesen_json(projekt_datei(s), {})
        for v in p["videos"]:
            if (v.get("drive") or v.get("id") or v.get("playback_id")) == ziel["id"]:
                v["titel"] = a.titel
        schreiben_json(projekt_datei(s), p)
        melden(bauen(s))


def b_entfernen(a):
    s = schluessel_fuer(a.projekt)
    code = code_fuer(s, False)
    pj = projekt_json(code)
    ziel = next((v for v in pj["videos"] if str(v["nr"]) == str(a.nr)), None) or fehler(f"Video {a.nr} nicht im Projekt")
    with Sperre():
        p = lesen_json(projekt_datei(s), {})
        p["videos"] = [v for v in p["videos"] if (v.get("drive") or v.get("id") or v.get("playback_id")) != ziel["id"]]
        if ziel["id"] not in (p.get("entfernt") or []):  # der Drive Abgleich holt es nie von selbst zurück
            p["entfernt"] = (p.get("entfernt") or []) + [ziel["id"]]
        schreiben_json(projekt_datei(s), p)
        melden(bauen(s))
    print(f"„{ziel['titel']}“ ist von der Seite runter (Nummer {a.nr} bleibt reserviert, Kommentare bleiben gespeichert)")


def b_projekt_titel(a):
    s = schluessel_fuer(a.projekt)
    with Sperre():
        p = lesen_json(projekt_datei(s), {})
        if a.kunde_id:  # Kunde aus der Liste zuteilen: Name, Ordner und (ohne --firma) die Firma des Kunden
            k = kunde_aus_liste(a.kunde_id)
            p.update(kunde=k["name"], kunde_ordner=k["id"])
            if a.firma is None:
                p["firma"] = k["firma"]
        for feld in ("titel", "kunde", "firma", "hinweis"):
            wert = getattr(a, feld)
            if wert is not None:
                p[feld] = wert
        if getattr(a, "darstellung", None):  # seit 17.11.2026: abschnitte (Standard) oder youtube (Langvideo groß, Shorts daneben)
            if a.darstellung == "youtube":
                p["darstellung"] = "youtube"
            else:
                p.pop("darstellung", None)
        schreiben_json(projekt_datei(s), p)
        melden(bauen(s))


def b_offline(a):
    """Projekt vom Netz nehmen: Link zeigt danach 404. Daten wandern ins Archiv, Kommentare bleiben in der Datenbank.
    Seit 17.11.2026 auch aus dem Dashboard („Link löschen“, Ole), dann mit --von. Zurück mit `stageview wiederherstellen`."""
    if not a.ja:
        fehler("nimmt den Link für alle vom Netz, nur mit --ja (und nur, wenn Ole es will)")
    s = schluessel_fuer(a.projekt)
    code = code_fuer(s, False)
    with Sperre():
        ziel = DATEN / "archiv" / f"{s}-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        ziel.parent.mkdir(parents=True, exist_ok=True)
        os.replace(projekt_datei(s), ziel)
        p = lesen_json(ziel, {})
        p["geloescht"] = {"am": datetime.now().isoformat(timespec="seconds"), "von": (getattr(a, "von", None) or "stageview").strip()[:60]}
        schreiben_json(ziel, p)
        if code and (WEB / code).is_dir():
            shutil.rmtree(WEB / code)
    print(f"{s} ist offline ({BASIS_URL}/{code} zeigt jetzt 404), Daten im Archiv: {ziel.name}")


def b_wiederherstellen(a):
    """Gelöschten Link zurückholen (seit 17.11.2026): neueste Fassung aus dem Archiv, gleicher Code, gleiche Nummern, gleiche
    Kommentare. Ohne Angabe: Liste der gelöschten Links. Achtung: hat Ole inzwischen `mux --aufraeumen` laufen lassen, können
    die Videos bei Mux weg sein, dann fehlen sie auf der Seite."""
    archiv, codes = DATEN / "archiv", lesen_json(DATEN / "codes.json", {})
    dateien = sorted(archiv.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True) if archiv.is_dir() else []
    ohne_zeit = lambda f: re.sub(r"-\d{8}-\d{6}$", "", f.stem)
    if not a.projekt:
        if not dateien:
            print("Keine gelöschten Links im Archiv.")
        for f in dateien[:40]:
            p, s = lesen_json(f, {}), ohne_zeit(f)
            g = p.get("geloescht") or {}
            online = " (wieder online)" if projekt_datei(s).exists() else ""
            print(f"{codes.get(s, '?'):8} {p.get('titel') or s}  ·  {p.get('kunde') or ''}  ·  gelöscht {g.get('am', '?')} von {g.get('von', '?')}  ·  {f.name}{online}")
        return
    t = a.projekt.strip()
    if "stagecraft.media" in t:
        t = [x for x in t.split("stagecraft.media", 1)[1].split("?")[0].split("/") if x][0]
    s = next((k for k, c in codes.items() if c == t), None) or ohne_zeit(Path(t))
    treffer = [f for f in dateien if f.stem == t.removesuffix(".json") or ohne_zeit(f) == s]
    if not treffer:
        fehler(f"Nichts im Archiv für {a.projekt} (stageview wiederherstellen ohne Angabe zeigt die Liste)")
    f = treffer[0]
    s = ohne_zeit(f)
    if projekt_datei(s).exists():
        fehler(f"{s} ist schon online: {BASIS_URL}/{codes.get(s, '')}")
    with Sperre():
        p = lesen_json(f, {})
        p.pop("geloescht", None)
        schreiben_json(projekt_datei(s), p)
        f.unlink()
        melden(bauen(s))
    print(f"{s} ist wieder online: {BASIS_URL}/{code_fuer(s, False)}")


def b_bauen(a):
    with Sperre():
        melden(bauen(schluessel_fuer(a.projekt) if a.projekt else None))


def b_kommentare(a):
    code = code_fuer(schluessel_fuer(a.projekt), False)
    pj, d = projekt_json(code), api(code)
    titel = {v["id"]: (v["nr"], v["titel"]) for v in pj["videos"]}
    oben = [k for k in d["kommentare"] if not k.get("antwort_auf") and (a.alle or not k["erledigt"])]
    if a.karte:
        reihe = [v["id"] for v in pj["videos"]]
        oben.sort(key=lambda k: (reihe.index(k["video"]) if k["video"] in reihe else 99, k.get("zeit") if k.get("zeit") is not None else 1e9))
        videos = {k["video"] for k in oben}
        if len(videos) == 1:
            nr, t = titel[next(iter(videos))]
            return karte_drucken(kommentar_karte([notiz(k.get("zeit"), k["text"], k["name"], f"{BASIS_URL}/{code}/{nr}") for k in oben],
                                                 t, f"{BASIS_URL}/{code}/{nr}"))
        if not oben:
            print("Keine offenen Kommentare." if not a.alle else "Keine Kommentare.")
            return
        return karte_drucken(kommentar_karte([notiz(k.get("zeit"), k["text"], k["name"], f"{BASIS_URL}/{code}/{titel[k['video']][0]}",
                                                    titel[k["video"]][1]) for k in oben if k["video"] in titel],
                                             pj.get("titel") or "", f"{BASIS_URL}/{code}"))
    if not oben:
        print("Keine offenen Kommentare." if not a.alle else "Keine Kommentare.")
    for vid in [v["id"] for v in pj["videos"]]:
        ks = [k for k in oben if k["video"] == vid]
        if not ks:
            continue
        nr, t = titel[vid]
        print(f"\nVideo {nr}: {t}  ({BASIS_URL}/{code}/{nr})")
        for k in ks:
            stelle = dauer_text(k["zeit"]) if k.get("zeit") is not None else "-"
            print(f"  [{k['id']}] {stelle}  {k['name']}{' (Stagecraft)' if k.get('rolle') == 'team' else ''}: {k['text']}{'  ✓ erledigt' if k['erledigt'] else ''}")
            for r in [x for x in d["kommentare"] if x.get("antwort_auf") == k["id"]]:
                print(f"      ↳ [{r['id']}] {r['name']}{' (Stagecraft)' if r.get('rolle') == 'team' else ''}: {r['text']}")


def kommentar_projekt(a, kid):
    code = code_fuer(schluessel_fuer(a.projekt), False)
    d = api(code)
    k = next((x for x in d["kommentare"] if x["id"] == kid), None) or fehler(f"Kommentar {kid} nicht in {code}")
    return code, k


def b_antworten(a):
    code, k = kommentar_projekt(a, a.id)
    r = api(code, "kommentare", "POST", {"video": k["video"], "text": a.text, "name": a.als, "antwort_auf": k.get("antwort_auf") or k["id"]})
    print(f"Antwort gespeichert ({r['id']}) als {a.als} mit Abzeichen Stagecraft")


def gleicher_text(t):
    return re.sub(r"\s+", " ", (t or "").strip()).casefold()


def kommentar_setzen(code, v, zeit, text, als, vorhanden):
    """Ein Kommentar vom Team. Gibt es denselben Text an diesem Video schon, wird er nicht doppelt gesetzt (z.B. nach einem Abbruch)."""
    alt = next((k for k in vorhanden if k["video"] == v["id"] and not k.get("antwort_auf") and gleicher_text(k["text"]) == gleicher_text(text)), None)
    stelle = dauer_text(zeit) if zeit is not None else "ohne Stelle"
    if alt:
        print(f"  schon da [{alt['id']}] {stelle}: {text[:70]}")
        return None
    r = api(code, "kommentare", "POST", {"video": v["id"], "zeit": zeit, "text": text, "name": als})
    print(f"  gesetzt [{r['id']}] {stelle} als {als}: {text[:70]}")
    return r


def b_kommentar(a):
    """Neuer Kommentar vom Team an einer Stelle im Video (z.B. Feedback aus dem Team einsortieren, 16.11.2026). Ohne --zeit ohne Stelle."""
    code, _, v = video_aus(a.projekt, a.nr)
    zeit = zeit_lesen(a.zeit, v.get("dauer"))
    if kommentar_setzen(code, v, zeit, a.text, a.als, api(code)["kommentare"]):
        print(f"Sichtbar für alle mit dem Link, mit Abzeichen Stagecraft: {BASIS_URL}/{code}/{v['nr']}")


def b_kommentare_setzen(a):
    """Mehrere Kommentare auf einmal aus einer JSON Liste [{"zeit": "1:08", "text": "…"}, {"zeit": null, "text": "…"}].
    Erst wird alles geprüft (Zeiten, Texte), dann gesetzt, so bleibt nie die Hälfte liegen. Mit --trocken nur die Vorschau."""
    code, _, v = video_aus(a.projekt, a.nr)
    try:
        roh = json.loads(sys.stdin.read() if a.datei == "-" else Path(a.datei).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        fehler(f"Liste nicht lesbar: {e}")
    if isinstance(roh, dict):
        roh = roh.get("kommentare") or []
    if not isinstance(roh, list) or not roh:
        fehler('Erwartet eine Liste wie [{"zeit": "1:08", "text": "…"}]')
    plan = []
    for i, k in enumerate(roh, 1):
        if not isinstance(k, dict) or not str(k.get("text") or "").strip():
            fehler(f"Eintrag {i} hat keinen Text")
        plan.append((zeit_lesen(k.get("zeit"), v.get("dauer")), str(k["text"]).strip(), str(k.get("als") or a.als)))
    plan.sort(key=lambda p: (p[0] is None, p[0] or 0))
    link = f"{BASIS_URL}/{code}/{v['nr']}"
    if a.karte and a.trocken:
        return karte_drucken(kommentar_karte([notiz(z, t, n, link) for z, t, n in plan], v["titel"], link, a.als, vorschau=True))
    print(f"{v['titel']} (Video {v['nr']}): {len(plan)} Kommentare{' (Vorschau, nichts gesetzt)' if a.trocken else ''}")
    if a.trocken:
        for zeit, text, als in plan:
            print(f"  {dauer_text(zeit) if zeit is not None else 'ohne Stelle':>11}  {als}: {text}")
        return
    vorhanden = api(code)["kommentare"]
    neu = sum(1 for zeit, text, als in plan if kommentar_setzen(code, v, zeit, text, als, vorhanden))
    print(f"{neu} neu gesetzt, sichtbar für alle mit dem Link: {BASIS_URL}/{code}/{v['nr']}")
    if a.karte:
        karte_drucken(kommentar_karte([notiz(z, t, n, link) for z, t, n in plan], v["titel"], link, a.als, neu=True))


def b_kontext(a):
    """Alles, um Feedback ohne Ansehen an die richtigen Stellen zu setzen: Transkript, Schnitte, Lautheit, Bildbögen, Kommentare."""
    code, _, v = video_aus(a.projekt, a.nr)
    start = time.time()
    tr = lesen_json(transkript_datei(v), None)
    if tr and (a.neu or tr.get("sprache") != a.sprache):
        tr = None
    spur = None if tr else transkript_anfragen(v, a.sprache)   # Mux schreibt, während ffmpeg das Video durchschaut
    ordner, ana = analyse_holen(code, v, a.abstand, a.neu)
    if spur:
        tr = transkript_abholen(v, *spur, a.sprache, start + a.warten)
    text = kontext_text(code, v, ordner, ana, tr, api(code)["kommentare"])
    schreiben(ordner / "kontext.md", text)
    print(text + f"\n(gespeichert: {ordner}/kontext.md)")


def b_transkript(a):
    code, _, v = video_aus(a.projekt, a.nr)
    tr = transkript_holen(v, a.sprache, a.warten, a.neu)
    if not tr:
        print("Mux schreibt noch am Transkript. In 1 bis 2 Minuten denselben Befehl noch einmal.")
        return
    print(f"# Transkript: {v['titel']} (Video {v['nr']}, {BASIS_URL}/{code}/{v['nr']}), Mux Spracherkennung")
    for s in (tr["stuecke"] if a.roh else saetze(tr["stuecke"])):
        print(f"{dauer_text(s['von'])} bis {dauer_text(s['bis'])}  {s['text']}")


def b_lautheit(a):
    code, _, v = video_aus(a.projekt, a.nr)
    _, ana = analyse_holen(code, v)
    print(f"{v['titel']} (Video {v['nr']}): gesamt {lufs_text(lufs(ana['lautheit']))} integriert (EBU R128)")
    for b in a.bereiche:
        teile = re.split(r"\s*(?:-|bis)\s*", b.strip(), maxsplit=1)
        if len(teile) != 2:
            fehler(f"Bereich {b!r}: bitte als 1:08-1:46 angeben")
        von, bis = zeit_lesen(teile[0], v.get("dauer")), zeit_lesen(teile[1], v.get("dauer"))
        if von is None or bis is None or bis <= von:
            fehler(f"Bereich {b!r}: Ende muss nach dem Anfang liegen")
        print(f"  {dauer_text(von)} bis {dauer_text(bis)}: {lufs_text(lufs(ana['lautheit'], von, bis))}")


def b_kommentar_aendern(a):
    """Text eines Stagecraft Kommentars ändern (seit 16.11.2026, z.B. ein von TESS gesetzter Punkt). Kundenkommentare lehnt der Dienst ab."""
    code, k = kommentar_projekt(a, a.id)
    r = api(code, f"kommentare/{k['id']}/text", "POST", {"text": a.text})
    print(f"Kommentar {k['id']} geändert ({dauer_text(r['zeit']) if r.get('zeit') is not None else 'ohne Stelle'}): {r['text'][:90]}")


def b_erledigt(a):
    code, k = kommentar_projekt(a, a.id)
    api(code, f"kommentare/{k.get('antwort_auf') or k['id']}/erledigt", "POST", {"erledigt": not a.wieder_offen, "name": a.als})
    print("Kommentar samt Antworten " + ("wieder offen" if a.wieder_offen else "abgehakt"))


def b_loeschen(a):
    code, k = kommentar_projekt(a, a.id)
    api(code, f"kommentare/{k['id']}", "DELETE")
    print(f"Kommentar {k['id']} gelöscht ({k['name']}: {k['text'][:60]}), Antworten darauf auch")


def b_status(a):
    code = code_fuer(schluessel_fuer(a.projekt), False)
    if a.karte:
        eintrag, videos = link_karte(lesen_json(projekt_datei(schluessel_fuer(a.projekt)), {}), code, True)
        return karte_drucken({"art": "stageview", "titel": "Freigabe Stand", "eintraege": [eintrag], "videos": videos})
    pj, d = projekt_json(code), api(code)
    offen = {}
    for k in d["kommentare"]:
        if not k.get("antwort_auf") and not k["erledigt"]:
            offen[k["video"]] = offen.get(k["video"], 0) + 1
    zaehl = {}
    for v in pj["videos"]:
        st = (d["status"].get(v["id"]) or {}).get("wert", "zur-freigabe")
        zaehl[st] = zaehl.get(st, 0) + 1
        von = (d["status"].get(v["id"]) or {}).get("von")
        n_offen = offen.get(v["id"], 0)
        extra = (f"  ({von})" if von else "") + (f"  · {n_offen} offene Kommentare" if n_offen else "")
        print(f"  {v['nr']:>3}  {STATUS[st]:<20} {v['titel']}{extra}")
    print(f"\n{zaehl.get('freigegeben', 0)} von {len(pj['videos'])} freigegeben, {zaehl.get('aenderung', 0)} mit Änderung, {sum(offen.values())} offene Kommentare")


def b_freigabe(a):
    code = code_fuer(schluessel_fuer(a.projekt), False)
    pj = projekt_json(code)
    v = next((x for x in pj["videos"] if str(x["nr"]) == str(a.nr)), None) or fehler(f"Video {a.nr} nicht im Projekt")
    api(code, "status", "POST", {"video": v["id"], "status": a.status, "name": a.als})
    print(f"{v['titel']}: {STATUS[a.status]}")


# Drive
def zeile(f):
    art = "Ordner" if ist_ordner(f) else (mb(int(f.get("size") or 0)) or f["mimeType"].split("/")[-1])
    vm = f.get("videoMediaMetadata") or {}
    extra = f"  {vm.get('width')}x{vm.get('height')} {dauer_text(int(vm.get('durationMillis', 0)) / 1000)}" if vm.get("width") else ""
    return f"{f['id']}  {art:>8}  {f.get('modifiedTime', '')[:10]}  {f['name']}{extra}"


def b_drive_ordner(a):
    for f in drive_kinder(drive_id(a.ordner)):
        print(zeile(f))


def b_drive_kunde(a):
    k = kunde_finden(a.kunde)
    if not k.get("drive_export"):
        fehler(f"für {k['name']} ist kein Drive Export Ordner hinterlegt (kunden.json, drive_export)")
    print(f"{k['name']}: Export Ordner {k['drive_export']}")
    for f in drive_kinder(drive_id(k["drive_export"])):
        print(zeile(f))


def b_drive_suchen(a):
    q = f"name contains '{a.text.replace(chr(39), chr(92) + chr(39))}' and trashed = false"
    r = drive().files().list(q=q, fields=f"files({FELDER})", includeItemsFromAllDrives=True, supportsAllDrives=True,
                             corpora="allDrives", orderBy="modifiedTime desc", pageSize=a.max).execute()
    for f in r.get("files", []):
        print(zeile(f))


def b_drive_umbenennen(a):
    f = drive().files().update(fileId=drive_id(a.datei), body={"name": a.name}, fields="id,name", **ALLE).execute()
    print(f"umbenannt: {f['name']}")


def b_drive_verschieben(a):
    did = drive_id(a.datei)
    alt = ",".join(drive_datei(did).get("parents", []))
    f = drive().files().update(fileId=did, addParents=drive_id(a.ziel), removeParents=alt, fields="id,name,parents", **ALLE).execute()
    print(f"verschoben: {f['name']}")


def b_drive_neuer_ordner(a):
    f = drive().files().create(body={"name": a.name, "mimeType": "application/vnd.google-apps.folder", "parents": [drive_id(a.in_ordner)]},
                               fields="id,name,webViewLink", **ALLE).execute()
    print(f"Ordner angelegt: {f['name']}  {f['id']}  {f.get('webViewLink', '')}")


def b_drive_freigeben(a):
    print("Link Freigabe gesetzt" if link_freigeben(drive_id(a.datei)) else "war schon per Link freigegeben")


def b_mux(a):
    alle = mux_assets(alle=True)
    if a.aufraeumen:
        # Ältere Fassungen eines Videos (z.B. 1080p nach dem Umstieg auf 4K) löschen, nur wenn die beste fertig ist
        weg = [(did, x, f"behalten: {liste[0].get('max_resolution_tier')}") for did, liste in alle.items()
               if liste[0].get("status") == "ready" for x in liste[1:]]
        # Neue Fassung als neue Drive Datei (seit 25.11.2026): die Assets der früheren Datei, sobald die neue fertig ist
        projekte = alle_projekte().values()
        benutzt = {v.get("drive") for p in projekte for v in p.get("videos", []) + (p.get("drive_weg") or [])}
        for p in projekte:
            for v in p.get("videos", []) + (p.get("drive_weg") or []):
                if v.get("vorher") and (alle.get(v.get("drive")) or [{}])[0].get("status") == "ready":
                    weg += [(alt, x, "alte Datei, die neue Fassung ist fertig") for alt in v["vorher"] if alt not in benutzt
                            for x in alle.get(alt) or []]
        weg = list({x["id"]: (did, x, grund) for did, x, grund in weg}.values())
        if not weg:
            print("Nichts aufzuräumen, pro Video gibt es nur eine Fassung bei Mux")
            return
        for did, x, grund in weg:
            print(f"{'lösche' if a.ja else 'würde löschen'}: {x.get('max_resolution_tier')} {x['status']} drive:{did} ({grund})")
            if a.ja:
                mux(f"/video/v1/assets/{x['id']}", "DELETE")
        if not a.ja:
            print("Zum Löschen mit --ja (offene Seiten, die gerade die alte Fassung abspielen, laden sie danach neu)")
        return
    for did, liste in sorted(alle.items(), key=lambda kv: int(kv[1][0].get("created_at") or 0)):
        x = liste[0]
        mehr = f"  (+{len(liste) - 1} ältere)" if len(liste) > 1 else ""
        print(f"{x['status']:<10} {x.get('max_resolution_tier', ''):>5} {dauer_text(x.get('duration')):>6}  {x.get('aspect_ratio', ''):>5}  drive:{did}{mehr}")


def b_hochstufen(a):
    """Videos, deren Original größer als 1080p ist, noch einmal in 4K zu Mux bringen (Standard seit 14.11.2026).
    Bis Mux fertig ist, spielt die Seite die bisherige Fassung. Danach wechselt sie von selbst, Nummern, Links und Kommentare bleiben."""
    nur = schluessel_fuer(a.projekt) if a.projekt else None
    alle = mux_assets(alle=True)
    ziele = {}
    for s, p in alle_projekte().items():
        if nur and s != nur:
            continue
        for v in p["videos"]:
            did = v.get("drive")
            if not did or did in ziele:
                continue
            if any(x.get("max_resolution_tier") == "2160p" and x.get("status") in ("ready", "preparing") for x in alle.get(did) or []):
                continue
            m = drive_datei(did).get("videoMediaMetadata") or {}
            if min(int(m.get("width") or 0), int(m.get("height") or 0)) <= 1080:
                continue  # Original nicht größer als 1080p, mehr gibt es nicht
            ziele[did] = v.get("titel") or did
    if not ziele:
        print("Alles schon in der höchsten Stufe, die das Original hergibt")
        return
    angelegt = []
    for did, titel in ziele.items():
        try:
            link_freigeben(did)
        except Exception as e:
            print(f"  Hinweis: Freigabe für {titel} nicht geprüft ({str(e)[:120]})")
        angelegt.append(mux_neu(did, titel)["id"])
        print(f"  zu Mux in 4K: {titel}", flush=True)
    offen = mux_warten(angelegt, a.warten) if a.warten else set(angelegt)
    with Sperre():
        melden(bauen(nur))
    if offen:
        print(f"  {len(offen)} Video(s) noch in Arbeit bei Mux, später `stageview bauen`, bis dahin läuft die bisherige Fassung")
    print("Alte Fassungen bei Mux danach mit `stageview mux --aufraeumen --ja` löschen (Speicher wird ohnehin mindestens einen Monat berechnet)")


def main():
    ap = argparse.ArgumentParser(prog="stageview", description="StageView Videoseiten (videos.stagecraft.media)")
    sub = ap.add_subparsers(dest="befehl", required=True)

    p = sub.add_parser("liste", help="alle Links, das neueste zuerst (--kunde, --neueste N, --videos)")
    p.add_argument("--kunde", help="nur die Links eines Kunden, z.B. Justus"); p.add_argument("--neueste", type=int, help="nur die N neuesten")
    p.add_argument("--videos", action="store_true", help="mit jedem Video Link und der Drive Datei")
    p.add_argument("--karte", action="store_true", help="als Karte für die TESS App"); p.set_defaults(f=b_liste)
    p = sub.add_parser("neueste", help="der neueste Link mit allen Video Links (--kunde für den eines Kunden)")
    p.add_argument("--kunde"); p.add_argument("--karte", action="store_true", help="als Karte für die TESS App")
    p.set_defaults(f=b_liste, neueste=1, videos=True)
    p = sub.add_parser("zeigen", help="Videos eines Projekts mit Nummern und Links"); p.add_argument("projekt"); p.set_defaults(f=b_zeigen)

    def quellen(p):
        p.add_argument("--ordner", action="append", help="Drive Ordner (Link oder ID), alle Videos darin")
        p.add_argument("--unterordner", action="store_true", help="auch Videos in Unterordnern")
        p.add_argument("--video", action="append", help="einzelnes Drive Video (Link oder ID), mehrfach möglich")
        p.add_argument("--quelle", action="append", help="Drive Ordner oder Video, wird selbst erkannt (mehrfach möglich)")
        p.add_argument("--warten", type=int, default=20, help="Minuten auf Mux warten (Standard 20, 0 = nicht warten)")
        p.add_argument("--gruppe", help="Kategorie für alle Videos dieses Aufrufs (z.B. \"Baby Boomer\")")
        p.add_argument("--gruppen-aus-ordnern", dest="gruppen_aus_ordnern", action="store_true",
                       help="jeder Unterordner wird eine Kategorie (nimmt Unterordner mit, ELEMENTE und Ähnliches nie)")

    p = sub.add_parser("neu", help="neues Projekt aus Drive Ordner oder Videos")
    p.add_argument("--titel", required=True); p.add_argument("--kunde", help="Kunde (Ordnername, SC-ID oder Name)")
    p.add_argument("--anzeige", help="Name oben auf der Seite, falls anders als im Kundenregister")
    p.add_argument("--firma"); p.add_argument("--dreh", help="Drehtag JJJJ-MM-TT"); p.add_argument("--hinweis")
    p.add_argument("--darstellung", choices=DARSTELLUNGEN, help="youtube: pro Kategorie Langvideo groß, Shorts daneben (Standard abschnitte)")
    p.add_argument("--schluessel"); quellen(p); p.set_defaults(f=b_neu)

    p = sub.add_parser("content-day", help="Projekt für einen Content Day aus dem Content Brain (Standard: der letzte)")
    p.add_argument("kunde"); p.add_argument("--name", help="z.B. Oktober"); p.add_argument("--warten", type=int, default=20)
    p.set_defaults(f=b_content_day)

    p = sub.add_parser("dazu", help="Videos zu einem Projekt hinzufügen"); p.add_argument("projekt"); p.add_argument("--titel")
    quellen(p); p.set_defaults(f=b_dazu)
    p = sub.add_parser("marker", help="Kommentare eines Videos als Marker für DaVinci (EDL zum Importieren oder JSON)")
    p.add_argument("projekt"); p.add_argument("nr"); p.add_argument("--format", choices=("edl", "json"), default="edl")
    p.add_argument("--start", default="01:00:00:00", help="Start Timecode der Timeline (Resolve Standard 01:00:00:00)")
    p.add_argument("--datei", help="in eine Datei statt auf den Bildschirm"); p.set_defaults(f=b_marker)
    p = sub.add_parser("drive-abgleich", help="Link mit dem Drive abgleichen: nicht mehr da = ausblenden, wieder da = zurück, --neue holt neue Videos")
    p.add_argument("projekt", nargs="?"); p.add_argument("--alle", action="store_true", help="alle Links (Cron, nur ausblenden und zurückholen)")
    p.add_argument("--neue", action="store_true", help="auch neue Videos aus dem Ordner dazu (wie der Knopf Drive abgleichen)")
    p.add_argument("--trocken", action="store_true", help="nur zeigen, was passieren würde")
    p.add_argument("--warten", type=int, default=0, help="Minuten auf Mux warten"); p.set_defaults(f=b_drive_abgleich)
    p = sub.add_parser("vorbereiten", help="für das Dashboard: Videos aus dem Drive schon zu Mux bringen, bevor der Link angelegt wird")
    p.add_argument("--quelle", action="append", required=True, help="Drive Ordner oder Video (mehrfach möglich)")
    p.add_argument("--unterordner", action="store_true", help="auch Videos aus Unterordnern (ohne Videos direkt im Ordner sowieso)")
    p.add_argument("--warten", type=int, default=30, help="Minuten auf Mux warten")
    p.add_argument("--aufheben", type=int, default=120, help="nach so vielen Minuten ungenutzte neue Videos bei Mux wieder löschen")
    p.set_defaults(f=b_vorbereiten)
    p = sub.add_parser("mux-weg", help="Mux Assets löschen, die in keinem Link stecken"); p.add_argument("asset", nargs="+")
    p.set_defaults(f=b_mux_weg)
    p = sub.add_parser("versatz", help="prüfen, ob Bild und Ton bei Mux versetzt laufen (Edit Lists aus Resolve), mit --reparieren beheben")
    p.add_argument("projekt", nargs="?"); p.add_argument("--reparieren", action="store_true"); p.add_argument("--warten", type=int, default=30)
    p.set_defaults(f=b_versatz)
    p = sub.add_parser("gruppe", help="Videos einer Kategorie zuordnen (Abschnitt auf der Seite), --weg nimmt sie heraus")
    p.add_argument("projekt"); p.add_argument("nr", nargs="*", help="Nummern der Videos, z.B. 1 2 5")
    p.add_argument("--name", help="Name der Kategorie"); p.add_argument("--weg", action="store_true")
    p.add_argument("--reihenfolge", nargs="+", help="Kategorien in dieser Reihenfolge zeigen")
    p.set_defaults(f=b_gruppe)
    p = sub.add_parser("titel", help="Titel eines Videos ändern"); p.add_argument("projekt"); p.add_argument("nr"); p.add_argument("titel", nargs="?")
    p.add_argument("--titel", dest="titel_option", help="statt des dritten Arguments")
    p.set_defaults(f=b_titel)
    p = sub.add_parser("projekt", help="Titel, Kunde, Firma oder Hinweis eines Projekts ändern"); p.add_argument("projekt")
    for feld in ("titel", "kunde", "firma", "hinweis"):
        p.add_argument("--" + feld)
    p.add_argument("--kunde-id", dest="kunde_id", help="Kunde aus `stageview kunden` zuteilen")
    p.add_argument("--darstellung", choices=DARSTELLUNGEN, help="Kategorien als Abschnitte (Standard) oder youtube: Langvideo groß, Shorts daneben")
    p.set_defaults(f=b_projekt_titel)
    sub.add_parser("kunden", help="alle Kunden in StageView mit Zahl der Links").set_defaults(f=b_kunden)
    p = sub.add_parser("kunde-neu", help="neuen Kunden anlegen (nur in StageView, nicht im Content Brain)"); p.add_argument("name"); p.add_argument("--firma")
    p.set_defaults(f=b_kunde_neu)
    p = sub.add_parser("kunde-aendern", help="Name oder Firma eines Kunden ändern, gilt für alle seine Links"); p.add_argument("id")
    p.add_argument("--name"); p.add_argument("--firma"); p.set_defaults(f=b_kunde_aendern)
    p = sub.add_parser("kunde-weg", help="Kunden aus StageView löschen (nur ohne Links)"); p.add_argument("id"); p.set_defaults(f=b_kunde_weg)
    p = sub.add_parser("entfernen", help="Video von der Seite nehmen (Drive und Mux bleiben)"); p.add_argument("projekt"); p.add_argument("nr")
    p.set_defaults(f=b_entfernen)
    p = sub.add_parser("offline", help="Projekt vom Netz nehmen, Daten ins Archiv (nur mit --ja), wie „Link löschen“ im Dashboard")
    p.add_argument("projekt"); p.add_argument("--ja", action="store_true"); p.add_argument("--von", help="wer löscht (steht im Archiv)")
    p.set_defaults(f=b_offline)
    p = sub.add_parser("wiederherstellen", help="gelöschten Link aus dem Archiv zurückholen, ohne Angabe die Liste der gelöschten")
    p.add_argument("projekt", nargs="?", help="Code, Link oder Archiv Datei"); p.set_defaults(f=b_wiederherstellen)
    p = sub.add_parser("bauen", help="Seiten neu bauen (alle oder eins)"); p.add_argument("projekt", nargs="?"); p.set_defaults(f=b_bauen)
    p = sub.add_parser("mux", help="alle Videos bei Mux mit Status und Stufe"); p.add_argument("--aufraeumen", action="store_true", help="ältere Fassungen löschen")
    p.add_argument("--ja", action="store_true"); p.set_defaults(f=b_mux)
    p = sub.add_parser("hochstufen", help="Videos mit 4K Original noch einmal in 4K zu Mux bringen"); p.add_argument("projekt", nargs="?")
    p.add_argument("--warten", type=int, default=30); p.set_defaults(f=b_hochstufen)

    p = sub.add_parser("kommentare", help="offene Kommentare eines Projekts"); p.add_argument("projekt"); p.add_argument("--alle", action="store_true")
    p.add_argument("--karte", action="store_true", help="als Karte für die TESS App")
    p.set_defaults(f=b_kommentare)
    p = sub.add_parser("antworten", help="auf einen Kommentar antworten (Abzeichen Stagecraft)"); p.add_argument("projekt"); p.add_argument("id", type=int)
    p.add_argument("text"); p.add_argument("--als", default="Stagecraft"); p.set_defaults(f=b_antworten)
    p = sub.add_parser("kommentar", help="neuer Kommentar vom Team an einer Stelle (Abzeichen Stagecraft)"); p.add_argument("projekt"); p.add_argument("nr")
    p.add_argument("text"); p.add_argument("--zeit", help="Stelle im Video, z.B. 1:08 (ohne: Kommentar ohne Stelle)")
    p.add_argument("--als", default="Stagecraft"); p.set_defaults(f=b_kommentar)
    p = sub.add_parser("kommentare-setzen", help="mehrere Kommentare vom Team aus einer JSON Liste, erst geprüft, dann gesetzt")
    p.add_argument("projekt"); p.add_argument("nr", nargs="?"); p.add_argument("--datei", required=True, help='JSON [{"zeit": "1:08", "text": "…"}], - liest von stdin')
    p.add_argument("--als", default="Stagecraft", help="Name am Kommentar, z.B. Jonas"); p.add_argument("--trocken", action="store_true", help="nur Vorschau")
    p.add_argument("--karte", action="store_true", help="Vorschau bzw. Ergebnis als Karte für die TESS App")
    p.set_defaults(f=b_kommentare_setzen)
    p = sub.add_parser("kontext", help="Transkript, Schnitte, Lautheit und Bildbögen eines Videos, um Feedback an die richtigen Stellen zu setzen")
    p.add_argument("projekt", help="Code oder Link, auch der Link auf ein Video"); p.add_argument("nr", nargs="?")
    p.add_argument("--sprache", default="de", help="Sprache für die Spracherkennung (de, en, auto …)")
    p.add_argument("--abstand", type=int, help="Sekunden zwischen den Bildern (Standard je nach Länge)")
    p.add_argument("--warten", type=int, default=150, help="so lange höchstens auf Mux warten (Sekunden)")
    p.add_argument("--neu", action="store_true", help="alles neu, auch das Transkript"); p.set_defaults(f=b_kontext)
    p = sub.add_parser("transkript", help="Transkript eines Videos mit Zeiten (Mux Spracherkennung, einmal erstellt, dann gespeichert)")
    p.add_argument("projekt"); p.add_argument("nr", nargs="?"); p.add_argument("--sprache", default="de")
    p.add_argument("--warten", type=int, default=150); p.add_argument("--neu", action="store_true")
    p.add_argument("--roh", action="store_true", help="Untertitel Stücke statt Sätze"); p.set_defaults(f=b_transkript)
    p = sub.add_parser("lautheit", help="Lautheit (LUFS) eines Videos, gesamt und für Bereiche wie 1:08-1:46")
    p.add_argument("projekt"); p.add_argument("nr"); p.add_argument("bereiche", nargs="*"); p.set_defaults(f=b_lautheit)
    p = sub.add_parser("kommentar-aendern", help="Text eines Stagecraft Kommentars ändern (nie den eines Kunden)")
    p.add_argument("projekt"); p.add_argument("id", type=int); p.add_argument("text"); p.set_defaults(f=b_kommentar_aendern)
    p = sub.add_parser("erledigt", help="Kommentar samt Antworten abhaken"); p.add_argument("projekt"); p.add_argument("id", type=int)
    p.add_argument("--wieder-offen", action="store_true"); p.add_argument("--als", default="Stagecraft"); p.set_defaults(f=b_erledigt)
    p = sub.add_parser("loeschen", help="Kommentar löschen (z.B. Spam), nur wenn Ole es will"); p.add_argument("projekt"); p.add_argument("id", type=int)
    p.set_defaults(f=b_loeschen)
    p = sub.add_parser("status", help="Freigabe Stand aller Videos"); p.add_argument("projekt")
    p.add_argument("--karte", action="store_true", help="als Karte für die TESS App"); p.set_defaults(f=b_status)
    p = sub.add_parser("freigabe", help="Status eines Videos setzen"); p.add_argument("projekt"); p.add_argument("nr")
    p.add_argument("status", choices=list(STATUS)); p.add_argument("--als", default="Stagecraft"); p.set_defaults(f=b_freigabe)

    d = sub.add_parser("drive", help="Google Drive (auch geteilte Ablagen)").add_subparsers(dest="drive_befehl", required=True)
    p = d.add_parser("ordner", help="Inhalt eines Ordners"); p.add_argument("ordner"); p.set_defaults(f=b_drive_ordner)
    p = d.add_parser("kunde", help="Export Ordner eines Kunden"); p.add_argument("kunde"); p.set_defaults(f=b_drive_kunde)
    p = d.add_parser("suchen", help="Dateien nach Namen suchen"); p.add_argument("text"); p.add_argument("--max", type=int, default=20)
    p.set_defaults(f=b_drive_suchen)
    p = d.add_parser("umbenennen"); p.add_argument("datei"); p.add_argument("name"); p.set_defaults(f=b_drive_umbenennen)
    p = d.add_parser("verschieben"); p.add_argument("datei"); p.add_argument("ziel"); p.set_defaults(f=b_drive_verschieben)
    p = d.add_parser("neuer-ordner"); p.add_argument("name"); p.add_argument("--in", dest="in_ordner", required=True)
    p.set_defaults(f=b_drive_neuer_ordner)
    p = d.add_parser("freigeben", help="Link Freigabe (Jeder mit dem Link: Betrachter)"); p.add_argument("datei"); p.set_defaults(f=b_drive_freigeben)

    a = ap.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
