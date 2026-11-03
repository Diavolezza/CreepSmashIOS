#!/usr/bin/env python3
"""Creates the Game Center leaderboards and achievements of CreepSmash in App Store Connect, from
docs/appstore/game-center.md and the images in build/appstore/game-center/ (both made by game_center.py).

Uses the App Store Connect API with a team key. The key never goes into the repository: put a file
~/.appstoreconnect/creepsmash.json with {"issuer_id": "…", "key_id": "…", "key_file": "~/…/AuthKey_….p8"}.
Only the standard library and the openssl command are used.

  python3 tools/appstore/asc_gamecenter.py            # check: sign in, find the app, list what exists
  python3 tools/appstore/asc_gamecenter.py --apply    # create what is missing (existing entries are skipped)
  python3 tools/appstore/asc_gamecenter.py --attach [--version=1.0.2]   # Game Center for the editable App Store version
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


def call(method, path, body=None, attempt=1):
    req = urllib.request.Request(API + path if path.startswith("/") else path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        if e.code >= 500 and attempt < 4:          # App Store Connect answers 500 now and then: try again
            time.sleep(3 * attempt)
            return call(method, path, body, attempt + 1)
        sys.exit(f"** {method} {path}: HTTP {e.code}\n{detail[:1500]}")


def try_call(method, path, body=None):
    """Like call, but None instead of stopping on an HTTP error (for reads of things that may not exist)."""
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError:
        return None


def all_pages(path):
    items, url = [], path
    while url:
        r = call("GET", url)
        items += r.get("data", [])
        url = r.get("links", {}).get("next")
    return items


def upload_image(kind, parent_id, file, rel=None, rel_type=None):
    """kind: 'gameCenterAchievementImages' or 'gameCenterLeaderboardImages' (parent: a localization), or with
    rel/rel_type e.g. 'gameCenterChallengeImages' with rel 'version' and rel_type 'gameCenterChallengeVersions'."""
    data = file.read_bytes()
    if rel is None:
        rel = "gameCenterAchievementLocalization" if kind == "gameCenterAchievementImages" else "gameCenterLeaderboardLocalization"
        rel_type = rel + "s"
    r = call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": {"fileName": file.name, "fileSize": len(data)},
             "relationships": {rel: {"data": {"type": rel_type, "id": parent_id}}}}})
    image = r["data"]
    for op in image["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"], data=part,
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req, timeout=120).read()
    call("PATCH", f"/v1/{kind}/{image['id']}", {"data": {"type": kind, "id": image["id"], "attributes": {"uploaded": True}}})


# ---- what should exist (from the generated table)
doc = (ROOT / "docs/appstore/game-center.md").read_text()
boards = [dict(id=m[0], en=m[1].strip(), de=m[2].strip(), image=m[3]) for m in
          re.findall(r"\| `(cs\.fastest\.[\w.]+)` \| ([^|]+) \| ([^|]+) \| ([\w.-]+\.png) \|", doc)]
achievements = [dict(id=m[0], points=int(m[1]), en=m[2].strip(), en_desc=m[3].strip(), de=m[4].strip(), de_desc=m[5].strip(), image=m[6])
                for m in re.findall(r"\| `(cs\.(?!fastest)[\w.]+)` \| (\d+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([\w.-]+\.png) \|", doc)]
challenges = [dict(id=m[0], board=m[1], en=m[2].strip(), en_desc=m[3].strip(), de=m[4].strip(), de_desc=m[5].strip(), image=m[6])
              for m in re.findall(r"\| `(cs\.challenge\.[\w.]+)` \| `([\w.]+)` \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([\w.-]+\.png) \|", doc)]
activities = [dict(id=m[0], en=m[1].strip(), en_desc=m[2].strip(), de=m[3].strip(), de_desc=m[4].strip(), image=m[5])
              for m in re.findall(r"\| `(cs\.activity\.[\w.]+)` \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([\w.-]+\.png) \|", doc)]
FALLBACK_URL = re.search(r"Fallback URL \(systems before iOS 26\): (\S+?)\.? Every", doc).group(1)
assert len(boards) == 9 and len(achievements) == 39 and len(challenges) == 9 and len(activities) == 1, \
    (len(boards), len(achievements), len(challenges), len(activities))
missing_images = [x["image"] for x in boards + achievements + challenges + activities if not (IMAGES / x["image"]).exists()]
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
if "--attach" in sys.argv:
    # Game Center for an App Store version (default: the editable one): without this link the leaderboards
    # and achievements are not visible in any build, not even in TestFlight.
    wanted = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--version=")), None)
    versions = all_pages(f"/v1/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&limit=50")
    editable = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")
    version = next((v for v in versions if (v["attributes"]["versionString"] == wanted if wanted
                    else v["attributes"].get("appStoreState") in editable)), None)
    if not version:
        sys.exit("** no editable App Store version (create it in App Store Connect first): "
                 + ", ".join(f"{v['attributes']['versionString']} {v['attributes'].get('appStoreState')}" for v in versions))
    print(f"  App Store version {version['attributes']['versionString']} ({version['attributes'].get('appStoreState')})")
    linked = None
    for gv in all_pages(f"/v1/gameCenterDetails/{detail['id']}/gameCenterAppVersions?limit=50"):
        sv = call("GET", f"/v1/gameCenterAppVersions/{gv['id']}/appStoreVersion").get("data")
        print(f"  Game Center app version {gv['id']}: {json.dumps(gv['attributes'])} → {sv and sv['attributes']['versionString']}")
        if sv and sv["id"] == version["id"]:
            linked = gv
    if linked:
        print("✓ Game Center already attached to this version")
    else:
        linked = call("POST", "/v1/gameCenterAppVersions", {"data": {"type": "gameCenterAppVersions",
                      "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})["data"]
        print(f"✓ Game Center attached to version {version['attributes']['versionString']}: {json.dumps(linked['attributes'])}")
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


# --extras: only the activity and the challenges (leaderboards and achievements are complete).
for b in ([] if "--extras" in sys.argv else boards):
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

for a in ([] if "--extras" in sys.argv else achievements):
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
# ---- the activity (link to a game against the computer), its version, texts and image; the leaderboards link to it
existing_activities = {x["attributes"]["vendorIdentifier"]: x for x in
                       all_pages(f"/v1/gameCenterDetails/{detail['id']}/gameCenterActivities?limit=50")}


def version_with_texts(kind, parent_rel, parent_type, parent_id, versions_path, texts, image, version_attributes=None):
    """The (first) version of a challenge or an activity with its English and German texts and the default image.
    kind: 'gameCenterChallenge' or 'gameCenterActivity'."""
    versions = all_pages(versions_path)
    if versions:
        version = versions[0]
    else:
        body = {"data": {"type": kind + "Versions", "relationships": {parent_rel: {"data": {"type": parent_type, "id": parent_id}}}}}
        if version_attributes:
            body["data"]["attributes"] = version_attributes
        version = call("POST", f"/v1/{kind}Versions", body)["data"]
    have = {loc["attributes"]["locale"] for loc in all_pages(f"/v1/{kind}Versions/{version['id']}/localizations")}
    for lang, locale in LOCALES.items():
        if locale not in have:
            call("POST", f"/v1/{kind}Localizations", {"data": {"type": kind + "Localizations",
                 "attributes": {"locale": locale, "name": texts[lang], "description": texts[lang + "_desc"]},
                 "relationships": {"version": {"data": {"type": kind + "Versions", "id": version["id"]}}}}})
    if not (try_call("GET", f"/v1/{kind}Versions/{version['id']}/defaultImage") or {}).get("data"):
        upload_image(kind + "Images", version["id"], IMAGES / image, rel="version", rel_type=kind + "Versions")
    return version


for a in activities:
    act = existing_activities.get(a["id"]) or call("POST", "/v1/gameCenterActivities", {"data": {"type": "gameCenterActivities",
          "attributes": {"referenceName": a["en"], "vendorIdentifier": a["id"], "minimumPlayersCount": 1,
                         "maximumPlayersCount": 1, "supportsPartyCode": False},
          "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail["id"]}}}}})["data"]
    version_with_texts("gameCenterActivity", "activity", "gameCenterActivities", act["id"],
                       f"/v1/gameCenterActivities/{act['id']}/versions", a, a["image"], {"fallbackUrl": FALLBACK_URL})
    for b in boards:
        lb = existing_boards[b["id"]]
        _, level, opponents = b["id"].rsplit(".", 2)
        call("PATCH", f"/v1/gameCenterLeaderboards/{lb['id']}", {"data": {"type": "gameCenterLeaderboards", "id": lb["id"],
             "attributes": {"activityProperties": {"level": level, "opponents": opponents}}}})
        call("PATCH", f"/v1/gameCenterLeaderboards/{lb['id']}/relationships/activity",
             {"data": {"type": "gameCenterActivities", "id": act["id"]}})
    print(f"✓ activity {a['id']} (linked to {len(boards)} leaderboards)")

# ---- challenges, one per leaderboard: three days, repeatable
existing_challenges = {x["attributes"]["vendorIdentifier"]: x for x in
                       all_pages(f"/v1/gameCenterDetails/{detail['id']}/gameCenterChallenges?limit=50")}
for c in challenges:
    ch = existing_challenges.get(c["id"]) or call("POST", "/v1/gameCenterChallenges", {"data": {"type": "gameCenterChallenges",
         "attributes": {"referenceName": c["en"], "vendorIdentifier": c["id"], "challengeType": "LEADERBOARD",
                        "repeatable": True},
         "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail["id"]}},
                           "leaderboard": {"data": {"type": "gameCenterLeaderboards", "id": existing_boards[c["board"]]["id"]}}}}})["data"]
    version_with_texts("gameCenterChallenge", "challenge", "gameCenterChallenges", ch["id"],
                       f"/v1/gameCenterChallenges/{ch['id']}/versions", c, c["image"])
    print(f"✓ challenge {c['id']}")
print("✓ done")
