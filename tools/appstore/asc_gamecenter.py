#!/usr/bin/env python3
"""Creates the Game Center leaderboards and achievements of CreepSmash in App Store Connect, from
docs/appstore/game-center.md and the images in build/appstore/game-center/ (both made by game_center.py).

Uses the App Store Connect API with a team key. The key never goes into the repository: put a file
~/.appstoreconnect/creepsmash.json with {"issuer_id": "…", "key_id": "…", "key_file": "~/…/AuthKey_….p8"}.
Only the standard library and the openssl command are used.

  python3 tools/appstore/asc_gamecenter.py            # check: sign in, find the app, list what exists
  python3 tools/appstore/asc_gamecenter.py --apply    # create what is missing (existing entries are skipped)
"""
import base64, json, os, pathlib, re, ssl, subprocess, sys, time, urllib.error, urllib.request

# Python from python.org brings no root certificates; macOS has them in /etc/ssl/cert.pem.
if os.path.exists("/etc/ssl/cert.pem"):
    urllib.request.install_opener(urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile="/etc/ssl/cert.pem"))))

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUNDLE_ID = "de.wanner-it.creepsmash.game"
API = "https://api.appstoreconnect.apple.com"
LOCALES = {"en": "en-US", "de": "de-DE"}
IMAGES = ROOT / "build/appstore/game-center"

cfg = json.loads(pathlib.Path("~/.appstoreconnect/creepsmash.json").expanduser().read_text())
KEY_FILE = pathlib.Path(os.path.expanduser(cfg["key_file"]))


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    """ECDSA signature from openssl (DER) to the raw r||s form JWT expects."""
    assert sig[0] == 0x30
    i = 2 if sig[1] < 0x80 else 3
    out = b""
    for _ in range(2):
        assert sig[i] == 0x02
        n = sig[i + 1]
        out += sig[i + 2:i + 2 + n].lstrip(b"\0").rjust(32, b"\0")
        i += 2 + n
    return out


_token = (None, 0)


def token() -> str:
    global _token
    if _token[0] and time.time() < _token[1] - 60:
        return _token[0]
    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": cfg["key_id"], "typ": "JWT"}).encode())
    claims = b64(json.dumps({"iss": cfg["issuer_id"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}).encode())
    msg = f"{header}.{claims}".encode()
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(KEY_FILE)], input=msg, capture_output=True, check=True).stdout
    _token = (f"{header}.{claims}.{b64(der_to_raw(sig))}", now + 1100)
    return _token[0]


def call(method, path, body=None):
    req = urllib.request.Request(API + path if path.startswith("/") else path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        sys.exit(f"** {method} {path}: HTTP {e.code}\n{detail[:1500]}")


def all_pages(path):
    items, url = [], path
    while url:
        r = call("GET", url)
        items += r.get("data", [])
        url = r.get("links", {}).get("next")
    return items


def upload_image(kind, localization_id, file):
    """kind: 'gameCenterAchievementImages' or 'gameCenterLeaderboardImages'."""
    data = file.read_bytes()
    rel = "gameCenterAchievementLocalization" if kind == "gameCenterAchievementImages" else "gameCenterLeaderboardLocalization"
    r = call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": {"fileName": file.name, "fileSize": len(data)},
             "relationships": {rel: {"data": {"type": rel + "s", "id": localization_id}}}}})
    image = r["data"]
    for op in image["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"], data=part,
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req).read()
    call("PATCH", f"/v1/{kind}/{image['id']}", {"data": {"type": kind, "id": image["id"], "attributes": {"uploaded": True}}})


# ---- what should exist (from the generated table)
doc = (ROOT / "docs/appstore/game-center.md").read_text()
boards = [dict(id=m[0], en=m[1].strip(), de=m[2].strip(), image=m[3]) for m in
          re.findall(r"\| `(cs\.fastest\.[\w.]+)` \| ([^|]+) \| ([^|]+) \| ([\w.-]+\.png) \|", doc)]
achievements = [dict(id=m[0], points=int(m[1]), en=m[2].strip(), en_desc=m[3].strip(), de=m[4].strip(), de_desc=m[5].strip(), image=m[6])
                for m in re.findall(r"\| `(cs\.(?!fastest)[\w.]+)` \| (\d+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([\w.-]+\.png) \|", doc)]
assert len(boards) == 9 and len(achievements) == 39, (len(boards), len(achievements))
missing_images = [x["image"] for x in boards + achievements if not (IMAGES / x["image"]).exists()]
if missing_images:
    sys.exit(f"** images missing ({len(missing_images)}): run python3 tools/appstore/game_center.py --images")

apply = "--apply" in sys.argv

# ---- app and its Game Center detail
apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
if not apps:
    sys.exit(f"** no app with bundle ID {BUNDLE_ID} in App Store Connect")
app = apps[0]
print(f"✓ signed in; app {app['attributes']['name']} ({app['id']})")
detail = call("GET", f"/v1/apps/{app['id']}/gameCenterDetail").get("data")
if not detail:
    if not apply:
        print("  Game Center is not enabled for the app yet (--apply enables it)")
    else:
        detail = call("POST", "/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails",
                      "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
        print("✓ Game Center enabled for the app")
existing_boards = {x["attributes"]["vendorIdentifier"]: x for x in all_pages(f"/v1/gameCenterDetails/{detail['id']}/gameCenterLeaderboards?limit=200")} if detail else {}
existing_achievements = {x["attributes"]["vendorIdentifier"]: x for x in all_pages(f"/v1/gameCenterDetails/{detail['id']}/gameCenterAchievements?limit=200")} if detail else {}
print(f"  leaderboards: {len(existing_boards)} of {len(boards)} exist; achievements: {len(existing_achievements)} of {len(achievements)} exist")
if "--status" in sys.argv and detail:
    # One leaderboard and one achievement in full, with the state of an image and the v2 view (versions).
    print(json.dumps(call("GET", f"/v1/gameCenterDetails/{detail['id']}"), indent=1)[:1500])
    for kind, items in (("gameCenterLeaderboard", existing_boards), ("gameCenterAchievement", existing_achievements)):
        first = next(iter(items.values()))
        print(f"== {kind} {first['attributes']['vendorIdentifier']}")
        print(json.dumps(first["attributes"], indent=1))
        locs = all_pages(f"/v1/{kind}s/{first['id']}/localizations")
        for loc in locs:
            img = call("GET", f"/v1/{kind}Localizations/{loc['id']}/{kind}Image").get("data") or {}
            print(loc["attributes"].get("locale"), "image:", (img.get("attributes") or {}).get("assetDeliveryState"))
        v2 = call("GET", f"/v2/{kind}s/{first['id']}?include=versions")
        print(json.dumps(v2, indent=1)[:2500])
    sys.exit(0)
if not apply:
    sys.exit(0)

def localizations(kind, parent_id):
    """Existing localizations of a leaderboard or achievement by locale, each with its image (or None)."""
    out = {}
    for loc in all_pages(f"/v1/{kind}s/{parent_id}/localizations?limit=50"):
        image_kind = "gameCenterLeaderboardImage" if kind == "gameCenterLeaderboard" else "gameCenterAchievementImage"
        image = call("GET", f"/v1/{kind}Localizations/{loc['id']}/{image_kind}").get("data")
        out[loc["attributes"]["locale"]] = (loc, image)
    return out


for b in boards:
    if b["id"] in existing_boards:
        lb = existing_boards[b["id"]]
    else:
        lb = call("POST", "/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards", "attributes": {
            "referenceName": b["en"], "vendorIdentifier": b["id"], "defaultFormatter": "ELAPSED_TIME_SECOND",
            "submissionType": "BEST_SCORE", "scoreSortType": "ASC", "scoreRangeStart": "1", "scoreRangeEnd": "36000"},
            "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail["id"]}}}}})["data"]
    have = localizations("gameCenterLeaderboard", lb["id"]) if b["id"] in existing_boards else {}
    for lang, locale in LOCALES.items():
        loc, image = have.get(locale, (None, None))
        if not loc:
            loc = call("POST", "/v1/gameCenterLeaderboardLocalizations", {"data": {"type": "gameCenterLeaderboardLocalizations",
                  "attributes": {"locale": locale, "name": b[lang]},
                  "relationships": {"gameCenterLeaderboard": {"data": {"type": "gameCenterLeaderboards", "id": lb["id"]}}}}})["data"]
        if not image:
            upload_image("gameCenterLeaderboardImages", loc["id"], IMAGES / b["image"])
    print(f"✓ leaderboard {b['id']}")

for a in achievements:
    if a["id"] in existing_achievements:
        ach = existing_achievements[a["id"]]
    else:
        ach = call("POST", "/v1/gameCenterAchievements", {"data": {"type": "gameCenterAchievements", "attributes": {
            "referenceName": a["en"], "vendorIdentifier": a["id"], "points": a["points"],
            "showBeforeEarned": True, "repeatable": False},
            "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail["id"]}}}}})["data"]
    have = localizations("gameCenterAchievement", ach["id"]) if a["id"] in existing_achievements else {}
    for lang, locale in LOCALES.items():
        loc, image = have.get(locale, (None, None))
        if not loc:
            loc = call("POST", "/v1/gameCenterAchievementLocalizations", {"data": {"type": "gameCenterAchievementLocalizations",
                  "attributes": {"locale": locale, "name": a[lang], "beforeEarnedDescription": a[lang + "_desc"],
                                 "afterEarnedDescription": a[lang + "_desc"]},
                  "relationships": {"gameCenterAchievement": {"data": {"type": "gameCenterAchievements", "id": ach["id"]}}}}})["data"]
        if not image:
            upload_image("gameCenterAchievementImages", loc["id"], IMAGES / a["image"])
    print(f"✓ achievement {a['id']}")
print("✓ done")
