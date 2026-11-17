#!/usr/bin/env python3
"""Kommentare und Freigabe Status für videos.stagecraft.media (seit 12.11.2026).

Läuft auf VPS 2 als systemd User Dienst `videos-api` von hermes, nur auf 127.0.0.1.
nginx reicht /api/ hierher durch. Quelle: STAGECRAFT_VIDEOPLAYER/server/videos_api.py

Keine Anmeldung: wer den Link zum Projekt hat, darf kommentieren (wie bei Pixieset).
Jedes Gerät schickt einen eigenen Zufallsschlüssel (X-Autor), damit man eigene Kommentare
löschen kann. Das Team schickt zusätzlich den Team Schlüssel (X-Team) und bekommt die
Rolle "team" (Abzeichen Stagecraft, darf alles löschen).

Gelöscht wird nie wirklich, nur ausgeblendet. Jede Änderung steht im Verlauf.

Endpunkte (projekt = Ordnername unter /var/www/videos, seit 13.11.2026 nur der Code, z.B. abc123):
  GET    /api/<projekt>/                      alle Kommentare und Status des Projekts
  POST   /api/<projekt>/kommentare            {video, zeit, text, name, antwort_auf}
  POST   /api/<projekt>/kommentare/<id>/erledigt   {erledigt, name}  gilt für den ganzen Verlauf, Kommentar samt Antworten (seit 13.11.2026)
  POST   /api/<projekt>/kommentare/<id>/text   {text}  eigenen Kommentar ändern (seit 16.11.2026), Team auch Stagecraft Kommentare,
                                              der alte Text bleibt im Verlauf
  DELETE /api/<projekt>/kommentare/<id>
  POST   /api/<projekt>/status                {video, status, name}
  POST   /api/<projekt>/fehler                {art, video, weg, geraet}  Abspielfehler vom Handy (seit 13.11.2026),
                                              nur Gerätetyp und Fehlercode, keine Adresse. Ansehen: Tabelle fehler

Admin Dashboard /admin (seit 14.11.2026, Ole: Übersicht aller Links, reingehen, Namen bearbeiten). Anmeldung wie beim
Aufgaben Dashboard (Ole, 14.11.2026: „derselbe Login Screen, dieselben Benutzernamen und Passwörter“): Name wählen, Passwort,
geprüft von der Brücke der TESS App (127.0.0.1:8651, /login und /me). Die Brücke legt dafür ein Gerät „Browser StageView …“
an (nur Aufgaben Rechte, Telegram Hinweis an Ole), dessen Token als HttpOnly Cookie sv_sitzung (Pfad /api/) im Browser liegt.
Passwort ändern oder Gerät sperren in der TESS App gilt damit sofort auch hier. Zugang haben die Admins (Ole, Jonas) und seit
17.11.2026 auch das Team (Caspar, Niklas, Rolle team in der Brücke; Ole: „als Nutzer Caspar und Niklas hinzufügen“).
Wer angemeldet ist, ist auch auf allen Kundenseiten als Stagecraft unterwegs (gleiches Cookie). X-Team geht weiter (Befehl
stageview, Team Link). Änderungen laufen über den Befehl `stageview` (derselbe Weg wie bei TESS und Alfred), lange
Aufträge (neuer Link, Videos dazu) als eigener systemd Dienst.
  POST   /api/admin/anmelden                  {zugang: tess|alfred|caspar|niklas, passwort, geraet} → Cookie, {name}
  POST   /api/admin/abmelden                  meldet das Gerät bei der Brücke ab, löscht das Cookie
  GET    /api/admin/uebersicht                alle Projekte mit Videos, Freigabe, offenen Kommentaren, Kunden, Aufträgen
  POST   /api/admin/projekt/<code>            {titel, kunde, firma, hinweis, darstellung}
  POST   /api/admin/projekt/<code>/video/<nr> {titel}
  POST   /api/admin/projekt/<code>/video/<nr>/entfernen
  POST   /api/admin/projekt/<code>/dazu       {quellen, titel}      Auftrag
  POST   /api/admin/neu                       {titel, kunde, quellen, unterordner, kategorien, dreh}   Auftrag
  POST   /api/admin/vorbereiten               {quelle, unterordner}  Auftrag (seit 16.11.2026): Drive Link einfügen, Videos gehen
                                              sofort zu Mux, während Titel und Kunde eingetragen werden (stageview vorbereiten)
  GET    /api/admin/auftrag/<id>              Stand eines Auftrags (Phase, gefundene Videos, Mux Fortschritt, Link, Fehler)
  POST   /api/admin/auftrag/<id>/abbrechen    vorbereiten anhalten, dabei neu angelegte Videos bei Mux löschen (nur ungenutzte)
  POST   /api/admin/kunden                    {name, firma} neuer Kunde (nur StageView, nie im Content Brain)
  POST   /api/admin/kunden/<id>               {name, firma} ändern, gilt für alle Links des Kunden
  POST   /api/admin/kunden/<id>/loeschen      nur ohne Links, Kunden aus dem Content Brain werden nur ausgeblendet
"""
import hashlib
import hmac
import json
import os
import re
import http.cookies
import secrets
import sqlite3
import subprocess
import threading
import urllib.error
import urllib.request
import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WEB = Path(os.environ.get("VIDEOS_WEB", "/var/www/videos"))
DB = Path(os.environ.get("VIDEOS_DB", str(Path.home() / ".hermes/data/videos/kommentare.db")))
PORT = int(os.environ.get("VIDEOS_PORT", "8652"))
TEAM_KEY = os.environ.get("VIDEOS_TEAM_KEY", "")
HERKUNFT = {h.strip() for h in os.environ.get("VIDEOS_ORIGIN", "https://videos.stagecraft.media").split(",") if h.strip()}
BRUECKE = os.environ.get("TESS_BRUECKE", "http://127.0.0.1:8651")  # Brücke der TESS App, prüft Namen und Passwörter
# Zugänge der Brücke, die hier rein dürfen, mit Namen und der Rolle, die die Brücke für sie meldet (seit 17.11.2026 auch das Team)
ADMIN_ZUGAENGE = {"tess": "Ole", "alfred": "Jonas", "caspar": "Caspar", "niklas": "Niklas"}
ZUGANG_ROLLE = {"tess": "admin", "alfred": "admin", "caspar": "team", "niklas": "team"}
COOKIE = "sv_sitzung"
DATEN = Path(os.environ.get("STAGEVIEW_DATEN", str(Path.home() / ".hermes/data/stageview")))
BEFEHL = os.environ.get("STAGEVIEW_BEFEHL", str(Path.home() / ".local/bin/stageview"))
OS_PFAD = Path(os.environ.get("STAGEVIEW_OS", str(Path.home() / "workspace/stagecraft-os")))
BASIS_URL = "https://videos.stagecraft.media"
CODE_RE = re.compile(r"^[a-z0-9]{6}$")

STATUS = ("zur-freigabe", "aenderung", "freigegeben")
PROJEKT_RE = re.compile(r"^(?:[a-z0-9-]+-)?[a-z0-9]{6}$")  # seit 13.11.2026 meist nur der Code
MAX_TEXT, MAX_NAME, MAX_BODY = 2000, 60, 16_000
SCHREIBEN_PRO_10_MIN = 60

_sperre = threading.Lock()
_projekte = {}  # projekt -> (mtime, set(video ids))
_schreiben = defaultdict(deque)  # ip -> Zeitpunkte
_fehlversuche = defaultdict(deque)  # ip -> Zeitpunkte falscher Passwörter
_fehlversuche_alle = deque()
_sitzungen = {}  # sha256(token) -> (geprüft um, {"zugang", "name"} oder None)


def jetzt():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def db():
    con = sqlite3.connect(DB, timeout=10)
    con.row_factory = sqlite3.Row
    return con


def anlegen():
    DB.parent.mkdir(parents=True, exist_ok=True)
    with db() as con:
        con.executescript("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS kommentare (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          projekt TEXT NOT NULL, video TEXT NOT NULL,
          zeit REAL, text TEXT NOT NULL, name TEXT NOT NULL,
          rolle TEXT NOT NULL DEFAULT 'kunde', autor TEXT NOT NULL,
          antwort_auf INTEGER, erledigt INTEGER NOT NULL DEFAULT 0,
          erledigt_von TEXT, erledigt_am TEXT,
          erstellt TEXT NOT NULL, geloescht INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS k_projekt ON kommentare(projekt, video);
        CREATE TABLE IF NOT EXISTS status (
          projekt TEXT NOT NULL, video TEXT NOT NULL, wert TEXT NOT NULL,
          von TEXT, am TEXT, PRIMARY KEY (projekt, video));
        CREATE TABLE IF NOT EXISTS verlauf (
          id INTEGER PRIMARY KEY AUTOINCREMENT, am TEXT NOT NULL, projekt TEXT NOT NULL,
          video TEXT, art TEXT NOT NULL, von TEXT, daten TEXT);
        CREATE TABLE IF NOT EXISTS fehler (
          id INTEGER PRIMARY KEY AUTOINCREMENT, am TEXT NOT NULL, projekt TEXT NOT NULL,
          video TEXT, art TEXT NOT NULL, weg TEXT, geraet TEXT);
        """)
        # Ein Verlauf ist immer als Ganzes erledigt oder offen (Ole, 13.11.2026): Antworten übernehmen den Zustand des Kommentars
        con.execute("""UPDATE kommentare SET
            erledigt = (SELECT p.erledigt FROM kommentare p WHERE p.id = kommentare.antwort_auf),
            erledigt_von = (SELECT p.erledigt_von FROM kommentare p WHERE p.id = kommentare.antwort_auf),
            erledigt_am = (SELECT p.erledigt_am FROM kommentare p WHERE p.id = kommentare.antwort_auf)
          WHERE antwort_auf IS NOT NULL AND EXISTS (SELECT 1 FROM kommentare p WHERE p.id = kommentare.antwort_auf)
            AND erledigt IS NOT (SELECT p.erledigt FROM kommentare p WHERE p.id = kommentare.antwort_auf)""")
        # Bearbeiten (seit 16.11.2026): Zeitpunkt der letzten Änderung, der alte Text steht im Verlauf
        if "bearbeitet" not in {r[1] for r in con.execute("PRAGMA table_info(kommentare)")}:
            con.execute("ALTER TABLE kommentare ADD COLUMN bearbeitet TEXT")
    os.chmod(DB, 0o600)


def videos_im_projekt(projekt):
    """Video IDs aus projekt.json. None, wenn es das Projekt nicht gibt."""
    if not PROJEKT_RE.match(projekt):
        return None
    datei = WEB / projekt / "projekt.json"
    try:
        mtime = datei.stat().st_mtime
    except OSError:
        return None
    with _sperre:
        alt = _projekte.get(projekt)
        if alt and alt[0] == mtime:
            return alt[1]
    try:
        ids = {v["id"] for v in json.loads(datei.read_text(encoding="utf-8")).get("videos", [])}
    except Exception:
        return None
    with _sperre:
        _projekte[projekt] = (mtime, ids)
    return ids


def autor_hash(schluessel):
    return hashlib.sha256(("videos:" + schluessel).encode()).hexdigest()


def bremse(ip):
    """True, wenn diese Adresse gerade zu viel schreibt."""
    grenze = time.time() - 600
    with _sperre:
        q = _schreiben[ip]
        while q and q[0] < grenze:
            q.popleft()
        if len(q) >= SCHREIBEN_PRO_10_MIN:
            return True
        q.append(time.time())
    return False


def anmelden_gesperrt(ip):
    """Höchstens 6 falsche Passwörter in 15 Minuten pro Adresse und 40 pro Stunde insgesamt."""
    t = time.time()
    with _sperre:
        for q, fenster in ((_fehlversuche[ip], 900), (_fehlversuche_alle, 3600)):
            while q and q[0] < t - fenster:
                q.popleft()
        return len(_fehlversuche[ip]) >= 6 or len(_fehlversuche_alle) >= 40


def anmelden_fehlgeschlagen(ip):
    with _sperre:
        _fehlversuche[ip].append(time.time())
        _fehlversuche_alle.append(time.time())


def bruecke(pfad, methode="GET", daten=None, token=None, ip=None):
    """Anfrage an die Brücke der TESS App. Gibt (status, json) zurück, status 0 = nicht erreichbar."""
    kopf = {"Content-Type": "application/json"}
    if token:
        kopf["Authorization"] = "Bearer " + token
    if ip:
        kopf["X-Forwarded-For"] = ip  # damit die Sperre der Brücke pro Adresse zählt, nicht für alle StageView Anmeldungen
    req = urllib.request.Request(BRUECKE + pfad, method=methode, headers=kopf,
                                 data=json.dumps(daten).encode() if daten is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}
    except Exception:
        return 0, {}


def sitzung_pruefen(token):
    """Wer steckt hinter dem Cookie? Fragt die Brücke (/me) und merkt sich die Antwort 60 s. Nur die Zugänge aus ADMIN_ZUGAENGE
    mit passender Rolle zählen.
    Ist die Brücke kurz nicht erreichbar, gilt eine bekannte Sitzung noch bis zu 15 Minuten."""
    if not token or len(token) > 200:
        return None
    k, t = hashlib.sha256(token.encode()).hexdigest(), time.time()
    with _sperre:
        alt = _sitzungen.get(k)
    if alt and t - alt[0] < 60:
        return alt[1]
    status, d = bruecke("/me", token=token)
    if status == 0 and alt and alt[1] and t - alt[0] < 900:
        return alt[1]
    wer = {"zugang": d["agent"], "name": ADMIN_ZUGAENGE[d["agent"]]} if (
        status == 200 and d.get("agent") in ADMIN_ZUGAENGE and d.get("rolle") == ZUGANG_ROLLE[d["agent"]]) else None
    with _sperre:
        _sitzungen[k] = (t, wer)
        if len(_sitzungen) > 500:
            for alt_k in sorted(_sitzungen, key=lambda x: _sitzungen[x][0])[:250]:
                del _sitzungen[alt_k]
    return wer


def sitzung_vergessen(token):
    with _sperre:
        _sitzungen.pop(hashlib.sha256((token or "").encode()).hexdigest(), None)


def lies_json(pfad, standard):
    try:
        return json.loads(Path(pfad).read_text(encoding="utf-8"))
    except Exception:
        return standard


def slug(text):
    t = str(text or "").lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")[:60]


def gehoert_zu(p, k):
    return p.get("kunde_ordner") == k["id"] or (not p.get("kunde_ordner") and (p.get("kunde") or "") == k["name"])


def kundenliste(projekte):
    """Kunden in StageView, dieselbe Logik wie kunden_liste() in stageview.py: eigene aus data/stageview/kunden.json,
    dazu das Kundenregister im Content Brain ohne ausgeblendete, dazu Kunden, die nur an einem Link hängen."""
    d = lies_json(DATEN / "kunden.json", {})
    raus = [{"id": k["id"], "name": k["name"], "firma": k.get("firma") or "", "quelle": "stageview"} for k in d.get("kunden", [])]
    ids, weg = {k["id"] for k in raus}, set(d.get("ausgeblendet", []))
    reg = lies_json(OS_PFAD / "plugins/stagecraft-team/skills/stagecraft-content-brain/kunden-register.json", {})
    eintraege = reg.get("kunden", reg) if isinstance(reg, dict) else reg
    for k in eintraege if isinstance(eintraege, list) else []:
        if isinstance(k, dict) and k.get("ordner") and k.get("name") and k["ordner"] not in ids and k["ordner"] not in weg:
            raus.append({"id": k["ordner"], "name": k["name"], "firma": k.get("firma") or "", "quelle": "content-brain"})
            ids.add(k["ordner"])
    for p in projekte:
        if not any(gehoert_zu(p, k) for k in raus):
            kid = p.get("kunde_ordner") or slug(p.get("kunde")) or "ohne-kunde"
            if kid not in ids:
                raus.append({"id": kid, "name": p.get("kunde") or "Ohne Kunde", "firma": "", "quelle": "link"})  # Firma gehört zum Link
                ids.add(kid)
    for k in raus:
        k["links"] = sum(1 for p in projekte if gehoert_zu(p, k))
    return sorted(raus, key=lambda k: k["name"].lower())


def auftraege():
    """Aufträge aus dem Dashboard der letzten 24 Stunden, laufende zuerst. Ende steht als __ENDE__ <code> im Protokoll."""
    ordner, grenze, raus = DATEN / "auftraege", time.time() - 86400, []
    for meta in sorted(ordner.glob("*.json"), reverse=True) if ordner.is_dir() else []:
        if meta.stat().st_mtime < grenze:
            continue
        a = lies_json(meta, {})
        if a.get("art") == "vorbereiten":  # gehört zum Fenster „Neuer Link“, nicht in die Liste
            continue
        a.update(auftrag_lesen(meta.stem)[0])
        raus.append(a)
    raus.sort(key=lambda a: a.get("start", ""), reverse=True)
    raus.sort(key=lambda a: not a["laeuft"])  # laufende zuerst, sonst neueste zuerst
    return raus[:20]


AUFTRAG_RE = re.compile(r"^\d{8}-\d{6}-[0-9a-f]{4}$")


def auftrag_lesen(aid):
    """Protokoll eines Auftrags: laeuft, ok, zuletzt, link, fehler. Dazu die Zeilen „@ {json}“ von stageview vorbereiten
    (Phase, gefundene Videos, Mux Fortschritt) zusammengeführt, und die bei Mux neu angelegten Assets."""
    try:
        zeilen = [z.strip() for z in (DATEN / "auftraege" / f"{aid}.log").read_text(encoding="utf-8", errors="replace").splitlines() if z.strip()]
    except OSError:
        zeilen = []
    stand, angelegt = {}, []
    for z in zeilen:
        if z.startswith("@ "):
            try:
                d = json.loads(z[2:])
            except ValueError:
                continue
            if "angelegt" in d:
                angelegt.append(str(d["angelegt"]))
            elif isinstance(d, dict):
                stand.update(d)
    ende = next((z for z in reversed(zeilen) if z.startswith("__ENDE__")), None)
    inhalt = [z for z in zeilen if not z.startswith(("__ENDE__", "@ ")) and not z.endswith(" start")]
    link = next((m.group(0) for z in reversed(inhalt) for m in [re.search(r"https://videos\.stagecraft\.media/[a-z0-9]{6}", z)] if m), None)
    fehlertext = None
    if ende is not None and ende.split()[-1] != "0":
        fehlertext = (next((z for z in reversed(inhalt) if z.upper().startswith("FEHLER")), None) or (inhalt[-1] if inhalt else "")).split(":", 1)[-1].strip()[:300]
    return ({"laeuft": ende is None, "ok": ende is not None and ende.split()[-1] == "0",
             "zuletzt": inhalt[-1][:220] if inhalt else "startet …", "link": link, "fehler": fehlertext, "stand": stand}, angelegt)


def auftrag_abbrechen(aid):
    """vorbereiten anhalten und die dabei neu angelegten Videos bei Mux löschen (stageview mux-weg lässt benutzte stehen)."""
    meta = lies_json(DATEN / "auftraege" / f"{aid}.json", {})
    if meta.get("art") != "vorbereiten":
        raise Fehler(400, "Nur das Vorbereiten lässt sich abbrechen")
    try:
        subprocess.run(["systemctl", "--user", "stop", f"stageview-{aid}"], capture_output=True, timeout=20)
    except Exception:
        pass
    _, angelegt = auftrag_lesen(aid)
    if angelegt:
        stageview("mux-weg", *angelegt, zeit=120)
    with open(DATEN / "auftraege" / f"{aid}.log", "a", encoding="utf-8") as f:
        f.write("abgebrochen\n__ENDE__ 130\n")
    return {"ok": True, "geloescht": len(angelegt)}


def uebersicht():
    """Alles fürs Dashboard: Projekte aus ~/.hermes/data/stageview, gebaute Seiten aus /var/www/videos, Kommentare und Status aus der Datenbank."""
    codes = lies_json(DATEN / "codes.json", {})
    with db() as con:
        offen, gesamt = defaultdict(int), defaultdict(int)
        for r in con.execute("SELECT projekt, video, erledigt FROM kommentare WHERE geloescht=0 AND antwort_auf IS NULL"):
            gesamt[(r["projekt"], r["video"])] += 1
            if not r["erledigt"]:
                offen[(r["projekt"], r["video"])] += 1
        status = {(r["projekt"], r["video"]): r["wert"] for r in con.execute("SELECT projekt, video, wert FROM status")}
        letzte = {r["projekt"]: r["am"] for r in con.execute("SELECT projekt, MAX(am) am FROM verlauf GROUP BY projekt")}
        neueste = defaultdict(list)
        for r in con.execute("SELECT id, projekt, video, zeit, text, name, rolle, erstellt FROM kommentare "
                             "WHERE geloescht=0 AND erledigt=0 AND antwort_auf IS NULL ORDER BY id DESC"):
            if len(neueste[r["projekt"]]) < 30:
                neueste[r["projekt"]].append({"id": r["id"], "video": r["video"], "zeit": r["zeit"], "text": r["text"][:280],
                                              "name": r["name"], "rolle": r["rolle"], "erstellt": r["erstellt"]})
    projekte, definitionen = [], []
    for datei in sorted((DATEN / "projekte").glob("*.json")):
        d, code = lies_json(datei, {}), codes.get(datei.stem)
        definitionen.append(d)
        pj = lies_json(WEB / code / "projekt.json", None) if code and CODE_RE.match(code) else None
        videos = [{"nr": v["nr"], "id": v["id"], "titel": v.get("titel"), "playback_id": v.get("playback_id"), "dauer": v.get("dauer"),
                   "seitenverhaeltnis": v.get("seitenverhaeltnis"), "posting": v.get("posting"), "format": v.get("format"),
                   "status": status.get((code, v["id"]), "zur-freigabe"), "offen": offen.get((code, v["id"]), 0),
                   "kommentare": gesamt.get((code, v["id"]), 0)} for v in (pj or {}).get("videos", [])]
        nr = {v["id"]: v["nr"] for v in videos}
        projekte.append({
            "schluessel": datei.stem, "code": code, "link": f"{BASIS_URL}/{code}" if pj else None,
            "titel": d.get("titel") or datei.stem, "kunde": d.get("kunde", ""), "kunde_ordner": d.get("kunde_ordner") or "",
            "firma": d.get("firma", ""), "hinweis": d.get("hinweis", ""), "darstellung": d.get("darstellung") or "abschnitte",
            "dreh": d.get("dreh"), "angelegt": d.get("angelegt"), "stand": (pj or {}).get("stand"), "letzte": letzte.get(code),
            "videos": videos, "wartend": max(0, len(d.get("videos", [])) - len(videos)),
            "kommentare": [{**k, "nr": nr.get(k["video"])} for k in neueste.get(code, []) if k["video"] in nr]})
    return {"projekte": projekte, "kunden": kundenliste(definitionen), "auftraege": auftraege(), "jetzt": jetzt()}


def stageview(*args, zeit=90):
    """Befehl stageview ausführen (derselbe Weg wie bei TESS und Alfred). Wirft Fehler mit der letzten Zeile der Ausgabe."""
    try:
        r = subprocess.run([BEFEHL, *args], capture_output=True, text=True, timeout=zeit)
    except subprocess.TimeoutExpired:
        raise Fehler(504, "Das dauert gerade zu lange, bitte gleich nochmal laden")
    if r.returncode != 0:
        zeilen = [z.strip() for z in (r.stdout + "\n" + r.stderr).splitlines() if z.strip()]
        meldung = next((z for z in reversed(zeilen) if z.startswith("FEHLER:")), zeilen[-1] if zeilen else "stageview ist fehlgeschlagen")
        raise Fehler(400, meldung.removeprefix("FEHLER:").strip()[:300])
    return r.stdout


def auftrag_starten(art, titel, args, code=None):
    """Lange Aufträge (Mux braucht Minuten) als eigener systemd Dienst, damit sie einen Neustart der API überstehen."""
    ordner = DATEN / "auftraege"
    ordner.mkdir(parents=True, exist_ok=True)
    aid = datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(2)
    log = ordner / f"{aid}.log"
    (ordner / f"{aid}.json").write_text(json.dumps({"id": aid, "art": art, "titel": titel, "code": code, "start": jetzt()}), encoding="utf-8")
    log.write_text("", encoding="utf-8")
    try:
        subprocess.run(["systemd-run", "--user", "--collect", "--quiet", f"--unit=stageview-{aid}", "-p", "MemoryMax=600M",
                        "-p", f"StandardOutput=append:{log}", "-p", f"StandardError=append:{log}",
                        "/bin/sh", "-c", 'echo "$(date -Is) start"; "$0" "$@"; echo "__ENDE__ $?"', BEFEHL, *args],
                       check=True, capture_output=True, timeout=20)
    except Exception as e:
        log.write_text(f"Fehler: Auftrag ließ sich nicht starten ({type(e).__name__})\n__ENDE__ 1\n", encoding="utf-8")
    return {"id": aid}


def quellen_args(text):
    """Drive Links oder IDs (Ordner oder Videos), eine pro Zeile. stageview erkennt selbst, was ein Ordner ist."""
    teile = [t.strip() for t in re.split(r"[\s,]+", str(text or "")) if t.strip()][:20]
    if not teile:
        raise Fehler(400, "Drive Link fehlt")
    for t in teile:
        if not re.fullmatch(r"[A-Za-z0-9_\-./:?=&%]{10,400}", t):
            raise Fehler(400, "Das sieht nicht nach einem Drive Link aus")
    return [f"--quelle={t}" for t in teile]


def sauber(text, laenge):
    text = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", str(text or "")).strip()
    return text[:laenge]


def zahl(wert):
    try:
        return int(wert)
    except (TypeError, ValueError):
        raise Fehler(404, "Kommentar fehlt")


def als_dict(r, eigener_autor, team):
    eigen = eigener_autor is not None and hmac.compare_digest(r["autor"], eigener_autor)
    return {
        "id": r["id"], "video": r["video"], "zeit": r["zeit"], "text": r["text"], "name": r["name"],
        "rolle": r["rolle"], "antwort_auf": r["antwort_auf"], "erledigt": bool(r["erledigt"]),
        "erledigt_von": r["erledigt_von"], "erstellt": r["erstellt"],
        "bearbeitet": r["bearbeitet"] if "bearbeitet" in r.keys() else None,
        "darf_loeschen": team or eigen,
        # Ändern (Ole, 16.11.2026): eigene Kommentare, das Team dazu alle Stagecraft Kommentare (z.B. von TESS gesetzt), nie die von Kunden
        "darf_bearbeiten": eigen or (team and r["rolle"] == "team"),
    }


class Fehler(Exception):
    def __init__(self, code, text):
        super().__init__(text)
        self.code, self.text = code, text


class Api(BaseHTTPRequestHandler):
    server_version = "videos-api"
    sys_version = ""

    def log_message(self, *args):  # keine Texte, keine Adressen im Log
        pass

    # ---------- Hilfen
    def antwort(self, code, daten, kopf=None):
        body = json.dumps(daten, ensure_ascii=False).encode()
        self.send_response(code)
        for k, v in (kopf or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def koerper(self):
        laenge = int(self.headers.get("Content-Length") or 0)
        if laenge > MAX_BODY:
            raise Fehler(413, "zu gross")
        if not laenge:
            return {}
        try:
            return json.loads(self.rfile.read(laenge))
        except Exception:
            raise Fehler(400, "kein JSON")

    def ip(self):
        return self.headers.get("X-Real-IP") or self.client_address[0]

    def ist_team(self):
        """Team Schlüssel (Befehl stageview, Team Link) oder angemeldet über das Admin Dashboard."""
        k = self.headers.get("X-Team") or ""
        if TEAM_KEY and k and hmac.compare_digest(k, TEAM_KEY):
            return True
        return self.admin_sitzung() is not None

    def sitzung_token(self):
        c = http.cookies.SimpleCookie()
        try:
            c.load(self.headers.get("Cookie") or "")
        except http.cookies.CookieError:
            return ""
        m = c.get(COOKIE)
        return m.value if m else ""

    def admin_sitzung(self):
        if not hasattr(self, "_sitzung"):
            self._sitzung = sitzung_pruefen(self.sitzung_token()) if (self.headers.get("Cookie") or "").find(COOKIE + "=") >= 0 else None
        return self._sitzung

    def autor(self):
        k = self.headers.get("X-Autor") or ""
        return autor_hash(k) if 20 <= len(k) <= 128 else None

    def pfad(self):
        teile = [t for t in self.path.split("?")[0].split("/") if t]
        if len(teile) < 2 or teile[0] != "api":
            raise Fehler(404, "unbekannt")
        projekt = teile[1]
        ids = videos_im_projekt(projekt)
        if ids is None:
            raise Fehler(404, "Projekt unbekannt")
        return projekt, ids, teile[2:]

    def schreib_pruefung(self):
        herkunft = self.headers.get("Origin")
        if herkunft and herkunft not in HERKUNFT:
            raise Fehler(403, "fremde Seite")
        if bremse(self.ip()):
            raise Fehler(429, "zu viele Änderungen, bitte kurz warten")

    def verarbeiten(self, methode):
        try:
            self.__dict__.pop("_sitzung", None)  # Sitzung pro Anfrage neu ansehen
            teile = [t for t in self.path.split("?")[0].split("/") if t]
            if teile[:2] == ["api", "admin"]:
                return self.admin(methode, teile[2:])
            projekt, ids, rest = self.pfad()
            team, autor = self.ist_team(), self.autor()
            if methode == "GET" and rest == []:
                return self.antwort(200, self.alles(projekt, autor, team))
            self.schreib_pruefung()
            if methode == "POST" and rest == ["kommentare"]:
                return self.antwort(201, self.neuer_kommentar(projekt, ids, self.koerper(), autor, team))
            if methode == "POST" and len(rest) == 3 and rest[0] == "kommentare" and rest[2] == "erledigt":
                return self.antwort(200, self.erledigt(projekt, rest[1], self.koerper(), autor, team))
            if methode == "POST" and len(rest) == 3 and rest[0] == "kommentare" and rest[2] == "text":
                return self.antwort(200, self.bearbeiten(projekt, rest[1], self.koerper(), autor, team))
            if methode == "DELETE" and len(rest) == 2 and rest[0] == "kommentare":
                return self.antwort(200, self.loeschen(projekt, rest[1], autor, team))
            if methode == "POST" and rest == ["status"]:
                return self.antwort(200, self.status(projekt, ids, self.koerper(), team))
            if methode == "POST" and rest == ["fehler"]:
                return self.antwort(200, self.fehler(projekt, ids, self.koerper()))
            raise Fehler(404, "unbekannt")
        except Fehler as f:
            self.antwort(f.code, {"fehler": f.text})
        except Exception as e:  # nie Details nach außen
            print("Fehler:", type(e).__name__, e, flush=True)
            self.antwort(500, {"fehler": "intern"})

    def do_GET(self):
        self.verarbeiten("GET")

    def do_POST(self):
        self.verarbeiten("POST")

    def do_DELETE(self):
        self.verarbeiten("DELETE")

    # ---------- Admin Dashboard
    def admin(self, methode, rest):
        if methode == "POST" and rest == ["anmelden"]:
            self.schreib_pruefung()
            ip = self.ip()
            if anmelden_gesperrt(ip):
                raise Fehler(429, "Zu viele Versuche. Probier es in 15 Minuten nochmal.")
            d = self.koerper()
            zugang, pw = str(d.get("zugang") or ""), str(d.get("passwort") or "")[:200]
            if zugang not in ADMIN_ZUGAENGE:
                raise Fehler(400, "Diesen Zugang gibt es hier nicht.")
            if not pw:
                raise Fehler(400, "Passwort fehlt.")
            geraet = re.sub(r"[^\w .'-]", "", str(d.get("geraet") or "")).removeprefix("Browser").strip()[:20]
            status, a = bruecke("/login", "POST", {"agent": zugang, "passwort": pw, "geraet": f"Browser StageView {geraet}".strip()}, ip=ip)
            if status == 401:
                anmelden_fehlgeschlagen(ip)
                raise Fehler(401, "Passwort falsch.")
            if status == 0:
                raise Fehler(503, "Die Anmeldung ist gerade nicht erreichbar, bitte gleich nochmal.")
            if status != 200 or not a.get("token"):
                raise Fehler(status if status in (403, 429) else 502, a.get("error") or "Das hat nicht geklappt.")
            if not sitzung_pruefen(a["token"]):  # nur die erlaubten Zugänge, sonst das Gerät gleich wieder abmelden
                bruecke("/logout", "POST", {}, token=a["token"])
                raise Fehler(403, "Dieser Zugang darf hier nicht rein.")
            cookie = f"{COOKIE}={a['token']}; Path=/api/; Max-Age=31536000; HttpOnly; Secure; SameSite=Strict"
            return self.antwort(200, {"name": ADMIN_ZUGAENGE[zugang], "zugang": zugang}, {"Set-Cookie": cookie})
        if methode == "POST" and rest == ["abmelden"]:
            herkunft = self.headers.get("Origin")
            if herkunft and herkunft not in HERKUNFT:
                raise Fehler(403, "nicht erlaubt")
            token = self.sitzung_token()
            if token:
                bruecke("/logout", "POST", {}, token=token)
                sitzung_vergessen(token)
            return self.antwort(200, {"ok": True}, {"Set-Cookie": f"{COOKIE}=; Path=/api/; Max-Age=0; HttpOnly; Secure; SameSite=Strict"})
        if not self.ist_team():
            raise Fehler(401, "Bitte anmelden")
        if methode == "GET" and rest == ["uebersicht"]:
            ich = self.admin_sitzung()
            return self.antwort(200, {**uebersicht(), "ich": ich or {"zugang": "team", "name": "Team"}})
        if len(rest) >= 2 and rest[0] == "auftrag" and not (AUFTRAG_RE.match(rest[1]) and (DATEN / "auftraege" / f"{rest[1]}.json").exists()):
            raise Fehler(404, "Auftrag unbekannt")
        if methode == "GET" and len(rest) == 2 and rest[0] == "auftrag":
            stand, _ = auftrag_lesen(rest[1])
            return self.antwort(200, {"id": rest[1], "art": lies_json(DATEN / "auftraege" / f"{rest[1]}.json", {}).get("art"), **stand})
        herkunft = self.headers.get("Origin")
        if methode != "POST" or (herkunft and herkunft not in HERKUNFT):
            raise Fehler(403, "nicht erlaubt")
        d = self.koerper()
        if rest == ["vorbereiten"]:
            q = str(d.get("quelle") or "").strip()
            if not q:
                raise Fehler(400, "Drive Link fehlt")
            args = ["vorbereiten", *quellen_args(q), "--warten=30"]
            if d.get("unterordner"):
                args.append("--unterordner")
            return self.antwort(202, auftrag_starten("vorbereiten", "Vorbereiten", args))
        if len(rest) == 3 and rest[0] == "auftrag" and rest[2] == "abbrechen":
            return self.antwort(200, auftrag_abbrechen(rest[1]))
        if rest == ["neu"]:
            titel = sauber(d.get("titel"), 120)
            if not titel:
                raise Fehler(400, "Titel fehlt")
            args = ["neu", f"--titel={titel}", *quellen_args(d.get("quellen")), "--warten=45"]
            kunde = sauber(d.get("kunde"), 80)
            if kunde:
                args.append(f"--kunde={kunde}")
            if d.get("unterordner"):
                args.append("--unterordner")
            if d.get("kategorien"):  # seit 17.11.2026: jeder Unterordner wird eine Kategorie auf der Seite
                args.append("--gruppen-aus-ordnern")
            dreh = sauber(d.get("dreh"), 10)
            if re.fullmatch(r"\d{4}-\d{2}-\d{2}", dreh):
                args.append(f"--dreh={dreh}")
            return self.antwort(202, auftrag_starten("neu", titel, args))
        if rest == ["kunden"]:
            name = sauber(d.get("name"), 80)
            if not name:
                raise Fehler(400, "Name fehlt")
            ausgabe = stageview("kunde-neu", f"--firma={sauber(d.get('firma'), 80)}", "--", name)
            m = re.search(r"Kunde angelegt: ([a-z0-9-]+)", ausgabe)
            return self.antwort(200, {"ok": True, "id": m.group(1) if m else None})
        if len(rest) >= 2 and rest[0] == "kunden":
            if not re.fullmatch(r"[a-z0-9-]{1,64}", rest[1]):
                raise Fehler(404, "Kunde unbekannt")
            if len(rest) == 2:
                args = ["kunde-aendern", rest[1]]
                for feld in ("name", "firma"):
                    if feld in d:
                        wert = sauber(d.get(feld), 80)
                        if feld == "name" and not wert:
                            raise Fehler(400, "Name darf nicht leer sein")
                        args.append(f"--{feld}={wert}")
                stageview(*args, zeit=180)
                return self.antwort(200, {"ok": True})
            if rest[2:] == ["loeschen"]:
                stageview("kunde-weg", rest[1])
                return self.antwort(200, {"ok": True})
        if len(rest) < 2 or rest[0] != "projekt" or not CODE_RE.match(rest[1]) or rest[1] not in lies_json(DATEN / "codes.json", {}).values():
            raise Fehler(404, "Projekt unbekannt")
        code = rest[1]
        if len(rest) == 2:
            args = ["projekt", code]
            if d.get("kunde_id"):
                if not re.fullmatch(r"[a-z0-9-]{1,64}", str(d["kunde_id"])):
                    raise Fehler(400, "Kunde unbekannt")
                args.append(f"--kunde-id={d['kunde_id']}")
            if d.get("darstellung") in ("abschnitte", "youtube"):  # seit 17.11.2026
                args.append(f"--darstellung={d['darstellung']}")
            for feld, laenge in (("titel", 120), ("kunde", 80), ("firma", 80), ("hinweis", 400)):
                if feld in d:
                    wert = sauber(d.get(feld), laenge)
                    if feld == "titel" and not wert:
                        raise Fehler(400, "Titel darf nicht leer sein")
                    args.append(f"--{feld}={wert}")
            stageview(*args)
            return self.antwort(200, {"ok": True})
        if rest[2:3] == ["dazu"] and len(rest) == 3:
            args = ["dazu", code, *quellen_args(d.get("quellen")), "--warten=45"]
            titel = sauber(d.get("titel"), 120)
            if titel:
                args.append(f"--titel={titel}")
            schluessel = next((s for s, c in lies_json(DATEN / "codes.json", {}).items() if c == code), "")
            projekt_titel = lies_json(DATEN / "projekte" / f"{schluessel}.json", {}).get("titel") or code
            return self.antwort(202, auftrag_starten("dazu", projekt_titel + (f" · {titel}" if titel else ""), args, code))
        if rest[2:3] == ["video"] and len(rest) >= 4 and rest[3].isdigit():
            if len(rest) == 4:
                titel = sauber(d.get("titel"), 120)
                if not titel:
                    raise Fehler(400, "Titel darf nicht leer sein")
                stageview("titel", code, rest[3], f"--titel={titel}")
                return self.antwort(200, {"ok": True})
            if rest[4:] == ["entfernen"]:
                stageview("entfernen", code, rest[3])
                return self.antwort(200, {"ok": True})
        raise Fehler(404, "unbekannt")

    # ---------- Logik
    def alles(self, projekt, autor, team):
        with db() as con:
            ks = con.execute("SELECT * FROM kommentare WHERE projekt=? AND geloescht=0 ORDER BY id", (projekt,)).fetchall()
            st = con.execute("SELECT video, wert, von, am FROM status WHERE projekt=?", (projekt,)).fetchall()
        return {
            "kommentare": [als_dict(r, autor, team) for r in ks],
            "status": {r["video"]: {"wert": r["wert"], "von": r["von"], "am": r["am"]} for r in st},
            "team": team,
            "jetzt": jetzt(),
        }

    def neuer_kommentar(self, projekt, ids, d, autor, team):
        if autor is None:
            raise Fehler(400, "Geräteschlüssel fehlt")
        video, text, name = str(d.get("video") or ""), sauber(d.get("text"), MAX_TEXT), sauber(d.get("name"), MAX_NAME)
        if video not in ids:
            raise Fehler(400, "Video unbekannt")
        if not text or not name:
            raise Fehler(400, "Text und Name fehlen")
        antwort_auf, zeit = d.get("antwort_auf"), d.get("zeit")
        with db() as con:
            if antwort_auf is not None:
                eltern = con.execute("SELECT id, antwort_auf FROM kommentare WHERE id=? AND projekt=? AND video=? AND geloescht=0",
                                     (zahl(antwort_auf), projekt, video)).fetchone()
                if not eltern:
                    raise Fehler(400, "Kommentar zum Antworten fehlt")
                antwort_auf = eltern["antwort_auf"] or eltern["id"]  # Antworten nur eine Ebene tief
                zeit = None
                wurzel = con.execute("SELECT erledigt, erledigt_von, erledigt_am FROM kommentare WHERE id=?", (antwort_auf,)).fetchone()
            if zeit is not None:
                try:
                    zeit = max(0.0, min(float(zeit), 36000.0))
                except (TypeError, ValueError):
                    zeit = None
            cur = con.execute(
                "INSERT INTO kommentare (projekt, video, zeit, text, name, rolle, autor, antwort_auf, erstellt) VALUES (?,?,?,?,?,?,?,?,?)",
                (projekt, video, zeit, text, name, "team" if team else "kunde", autor, antwort_auf, jetzt()))
            if antwort_auf is not None and wurzel and wurzel["erledigt"]:  # Antwort in einem erledigten Verlauf gilt mit als erledigt
                con.execute("UPDATE kommentare SET erledigt=1, erledigt_von=?, erledigt_am=? WHERE id=?",
                            (wurzel["erledigt_von"], wurzel["erledigt_am"], cur.lastrowid))
            con.execute("INSERT INTO verlauf (am, projekt, video, art, von, daten) VALUES (?,?,?,?,?,?)",
                        (jetzt(), projekt, video, "kommentar", name, json.dumps({"id": cur.lastrowid})))
            r = con.execute("SELECT * FROM kommentare WHERE id=?", (cur.lastrowid,)).fetchone()
        return als_dict(r, autor, team)

    def erledigt(self, projekt, kid, d, autor, team):
        name = sauber(d.get("name"), MAX_NAME) or None
        wert = 1 if d.get("erledigt") else 0
        with db() as con:
            r = con.execute("SELECT * FROM kommentare WHERE id=? AND projekt=? AND geloescht=0", (zahl(kid), projekt)).fetchone()
            if not r:
                raise Fehler(404, "Kommentar fehlt")
            if r["antwort_auf"]:  # Haken gilt immer für den ganzen Verlauf, also am Kommentar oben ansetzen
                r = con.execute("SELECT * FROM kommentare WHERE id=? AND geloescht=0", (r["antwort_auf"],)).fetchone() or r
            con.execute("UPDATE kommentare SET erledigt=?, erledigt_von=?, erledigt_am=? WHERE id=? OR antwort_auf=?",
                        (wert, name if wert else None, jetzt() if wert else None, r["id"], r["id"]))
            con.execute("INSERT INTO verlauf (am, projekt, video, art, von, daten) VALUES (?,?,?,?,?,?)",
                        (jetzt(), projekt, r["video"], "erledigt" if wert else "wieder offen", name, json.dumps({"id": r["id"]})))
            r = con.execute("SELECT * FROM kommentare WHERE id=?", (r["id"],)).fetchone()
        return als_dict(r, autor, team)

    def bearbeiten(self, projekt, kid, d, autor, team):
        text = sauber(d.get("text"), MAX_TEXT)
        if not text:
            raise Fehler(400, "Text fehlt")
        with db() as con:
            r = con.execute("SELECT * FROM kommentare WHERE id=? AND projekt=? AND geloescht=0", (zahl(kid), projekt)).fetchone()
            if not r:
                raise Fehler(404, "Kommentar fehlt")
            if not als_dict(r, autor, team)["darf_bearbeiten"]:
                raise Fehler(403, "Nur eigene Kommentare")
            if r["text"] != text:
                con.execute("UPDATE kommentare SET text=?, bearbeitet=? WHERE id=?", (text, jetzt(), r["id"]))
                con.execute("INSERT INTO verlauf (am, projekt, video, art, von, daten) VALUES (?,?,?,?,?,?)",
                            (jetzt(), projekt, r["video"], "bearbeitet", "team" if team else r["name"],
                             json.dumps({"id": r["id"], "vorher": r["text"]}, ensure_ascii=False)))
                r = con.execute("SELECT * FROM kommentare WHERE id=?", (r["id"],)).fetchone()
        return als_dict(r, autor, team)

    def loeschen(self, projekt, kid, autor, team):
        with db() as con:
            r = con.execute("SELECT * FROM kommentare WHERE id=? AND projekt=? AND geloescht=0", (zahl(kid), projekt)).fetchone()
            if not r:
                raise Fehler(404, "Kommentar fehlt")
            if not als_dict(r, autor, team)["darf_loeschen"]:
                raise Fehler(403, "Nur eigene Kommentare")
            con.execute("UPDATE kommentare SET geloescht=1 WHERE id=? OR antwort_auf=?", (r["id"], r["id"]))
            con.execute("INSERT INTO verlauf (am, projekt, video, art, von, daten) VALUES (?,?,?,?,?,?)",
                        (jetzt(), projekt, r["video"], "geloescht", "team" if team else r["name"], json.dumps({"id": r["id"]})))
        return {"ok": True}

    def status(self, projekt, ids, d, team):
        video, wert, name = str(d.get("video") or ""), d.get("status"), sauber(d.get("name"), MAX_NAME) or None
        if video not in ids or wert not in STATUS:
            raise Fehler(400, "Video oder Status unbekannt")
        am = jetzt()
        with db() as con:
            con.execute("INSERT INTO status (projekt, video, wert, von, am) VALUES (?,?,?,?,?) "
                        "ON CONFLICT(projekt, video) DO UPDATE SET wert=excluded.wert, von=excluded.von, am=excluded.am",
                        (projekt, video, wert, name, am))
            con.execute("INSERT INTO verlauf (am, projekt, video, art, von, daten) VALUES (?,?,?,?,?,?)",
                        (am, projekt, video, "status", name, json.dumps({"status": wert, "team": team})))
        return {"video": video, "wert": wert, "von": name, "am": am}

    def fehler(self, projekt, ids, d):
        video = str(d.get("video") or "")
        with db() as con:
            con.execute("INSERT INTO fehler (am, projekt, video, art, weg, geraet) VALUES (?,?,?,?,?,?)",
                        (jetzt(), projekt, video if video in ids else "", sauber(d.get("art"), 200) or "unbekannt",
                         sauber(d.get("weg"), 20), sauber(d.get("geraet"), 300)))
            con.execute("DELETE FROM fehler WHERE id <= (SELECT MAX(id) - 5000 FROM fehler)")
        return {"ok": True}


def main():
    anlegen()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Api)
    server.daemon_threads = True
    print(f"videos-api auf 127.0.0.1:{PORT}, Daten {DB}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
