#!/usr/bin/env python3
"""Echter Datenstand für Vorführung und Screenshots, ohne Anmeldung: Liste der Links per ssh (stageview liste), dazu pro Link
die öffentlichen Daten der Videoseite (projekt.json, /api/<code>/). Daraus eine Übersicht wie GET /api/admin/uebersicht.
Schreibt nach build/demo.json (nicht im Git, nicht im App Paket). Die App liest sie nur im Testbuild mit SV_DEMO_DATEI.
Aufruf im Ordner app/: python3 scripts/demo_daten.py"""
import json, re, subprocess, urllib.request
from collections import defaultdict
from pathlib import Path

ZIEL = Path(__file__).resolve().parent.parent / "build" / "demo.json"
ZIEL.parent.mkdir(exist_ok=True)

def holen(url):
    with urllib.request.urlopen(url, timeout=20) as r:
        return json.loads(r.read())

def slug(t):
    t = t.lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")

liste = subprocess.run(["ssh", "-i", str(Path.home() / ".ssh/id_ed25519"), "hermes@82.165.217.31", "stageview liste"],
                       capture_output=True, text=True, timeout=60).stdout
zeilen = [re.match(r"^(\w{6})\s+\S+\s+(.*) · ([^·]*?)\s+\((\d+) Videos?, angelegt (\d\d)\.(\d\d)\.(\d{4})\)\s+\[(.*)\]$", z) for z in liste.splitlines()]
# Drive Abgleich (seit 22.11.2026): ausgeblendete Videos und Hinweis pro Link, nur Titel und Datum
drive = json.loads(subprocess.run(["ssh", "-i", str(Path.home() / ".ssh/id_ed25519"), "hermes@82.165.217.31",
    "python3 -c 'import json,glob,os;print(json.dumps({os.path.basename(f)[:-5]: {\"weg\": [{\"titel\": w.get(\"titel\"), \"am\": w.get(\"weg_am\")} "
    "for w in (d.get(\"drive_weg\") or [])], \"hinweis\": d.get(\"drive_hinweis\")} for f in glob.glob(os.path.expanduser(\"~/.hermes/data/stageview/projekte/*.json\")) "
    "for d in [json.load(open(f))]}))'"], capture_output=True, text=True, timeout=60).stdout or "{}")
projekte, kommentare_alle, kunden, seiten = [], {}, {}, {}
for m in [m for m in zeilen if m]:
    code, titel, kunde, _, tag, monat, jahr, schluessel = m.groups()
    try:
        pj = holen(f"https://videos.stagecraft.media/{code}/projekt.json")
        api = holen(f"https://videos.stagecraft.media/api/{code}/")
    except Exception as e:
        print("übersprungen", code, e)
        continue
    kommentare_alle[code] = api
    # Aufbau der Kundenansicht wie in projekt.json (Kategorien, Darstellung, Hinweis, Kategorie pro Video)
    seiten[code] = {"gruppen": pj.get("gruppen") or [], "darstellung": pj.get("darstellung") or "abschnitte", "hinweis": pj.get("hinweis") or "",
                    "videos": [{"id": v["id"], "gruppe": v.get("gruppe")} for v in pj.get("videos", [])]}
    offen, gesamt, letzte = defaultdict(int), defaultdict(int), None
    for k in api["kommentare"]:
        letzte = max(letzte or "", k["erstellt"])
        if k.get("antwort_auf") is None:
            gesamt[k["video"]] += 1
            if not k["erledigt"]:
                offen[k["video"]] += 1
    for s in api["status"].values():
        letzte = max(letzte or "", s.get("am") or "")
    videos = [{"nr": v["nr"], "id": v["id"], "titel": v["titel"], "playback_id": v.get("playback_id"), "dauer": v.get("dauer"), "fps": v.get("fps"),
               "seitenverhaeltnis": v.get("seitenverhaeltnis"), "posting": v.get("posting"), "format": v.get("format"),
               "status": (api["status"].get(v["id"]) or {}).get("wert", "zur-freigabe"), "offen": offen[v["id"]],
               "kommentare": gesamt[v["id"]]} for v in pj.get("videos", [])]
    nr = {v["id"]: v["nr"] for v in videos}
    offene = [{"id": k["id"], "video": k["video"], "zeit": k["zeit"], "text": k["text"][:280], "name": k["name"], "rolle": k["rolle"],
               "erstellt": k["erstellt"], "nr": nr.get(k["video"])}
              for k in sorted(api["kommentare"], key=lambda k: -k["id"]) if k.get("antwort_auf") is None and not k["erledigt"]][:30]
    kid = slug(kunde)
    kunden.setdefault(kid, {"id": kid, "name": kunde, "firma": "", "quelle": "content-brain", "links": 0})["links"] += 1
    projekte.append({"schluessel": schluessel, "code": code, "link": f"https://videos.stagecraft.media/{code}", "titel": pj.get("titel") or titel,
                     "kunde": kunde, "kunde_ordner": kid, "firma": pj.get("firma") or "", "hinweis": pj.get("hinweis") or "",
                     "darstellung": pj.get("darstellung") or "abschnitte", "dreh": pj.get("dreh"), "angelegt": f"{jahr}-{monat}-{tag}",
                     "stand": pj.get("stand"), "letzte": letzte, "videos": videos, "wartend": 0, "kommentare": offene,
                     "drive_weg": (drive.get(schluessel) or {}).get("weg") or [], "drive_hinweis": (drive.get(schluessel) or {}).get("hinweis")})
    print(f"{code}  {len(videos):2} Videos  {sum(offen.values()):2} offen  {titel}")
uebersicht = {"projekte": projekte, "kunden": sorted(kunden.values(), key=lambda k: k["name"].lower()), "auftraege": [],
              "ich": {"zugang": "tess", "name": "Ole"}}
ZIEL.write_text(json.dumps({"uebersicht": uebersicht, "kommentare": kommentare_alle, "seiten": seiten}, ensure_ascii=False), encoding="utf-8")
print("geschrieben:", ZIEL, f"{len(projekte)} Links")
