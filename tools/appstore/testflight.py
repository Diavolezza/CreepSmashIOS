"""Sets up a build for external testers in TestFlight: beta texts (EN/DE), review contact, the group with a
public link, the build in the group and its submission to the beta review. Repeatable: what exists is updated.

Usage (from the repository root):  python3 tools/appstore/testflight.py BUILD     e.g. 53
Uses the API key of tools/appstore/asc_gamecenter.py (~/.appstoreconnect/creepsmash.json).
"""
import sys
import time

src = open("tools/appstore/asc_gamecenter.py").read()
exec(src[:src.index("doc = (ROOT")])

GROUP = "Online-Test"
PUBLIC_LINK_LIMIT = 10
FEEDBACK = "info@wanner-it.de"
PRIVACY = "https://diavolezza.github.io/creepsmash/privacy.html"

DESCRIPTION = {
    "en-US": "CreepSmash is a tower defense game for two to four players. This test version is for testing "
             "online play through Game Center.",
    "de-DE": "CreepSmash ist ein Tower-Defense-Spiel für zwei bis vier Spieler. Diese Testversion dient dem Test "
             "des Online-Spiels über Game Center.",
}
WHATS_NEW = {
    "en-US": "Online play through Game Center: Multiplayer → Game Center, invite a friend or find a random opponent "
             "and play a round. Afterwards please tap \"Send log\" in the options and email the log to "
             f"{FEEDBACK}.",
    "de-DE": "Online-Spiel über Game Center: Mehrspieler → Game Center, einen Freund einladen oder einen zufälligen "
             "Gegner suchen und eine Runde spielen. Bitte danach in den Optionen auf „Protokoll senden“ tippen und "
             f"das Protokoll per Mail an {FEEDBACK} schicken.",
}
REVIEW_NOTES = (
    "This test build is for testing online play through Game Center with a few testers. No account or login of "
    "the app is needed. Online play: sign in to Game Center, then Multiplayer > Game Center, invite a friend or "
    "find a random opponent. A game against the computer (Vs. computer) needs no second device. Test builds "
    "record the connection during online games in a local file; the tester can send it on purpose with "
    "\"Send log\" in the options (share sheet). Nothing is sent automatically."
)


def upsert(collection_path, create_type, key, wanted, relationships):
    """Updates the item whose `key` attribute matches, or creates it."""
    for item in call("GET", collection_path)["data"]:
        if item["attributes"].get(key) == wanted[key]:
            attrs = {k: v for k, v in wanted.items() if k != key}
            call("PATCH", f"/v1/{create_type}/{item['id']}",
                 {"data": {"type": create_type, "id": item["id"], "attributes": attrs}})
            return item["id"]
    return call("POST", f"/v1/{create_type}",
                {"data": {"type": create_type, "attributes": wanted, "relationships": relationships}})["data"]["id"]


def main():
    number = sys.argv[1] if len(sys.argv) > 1 else sys.exit("build number missing")
    app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    aid = app["id"]

    # 1. The build, once it is processed.
    for _ in range(60):
        builds = call("GET", f"/v1/builds?filter[app]={aid}&filter[version]={number}")["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "not there yet"
        print(f"▸ build {number}: {state}", flush=True)
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            sys.exit("** the build cannot be used")
        time.sleep(30)
    else:
        sys.exit("** the build is still not processed – run the script again later")
    build = builds[0]
    bid = build["id"]
    if build["attributes"].get("usesNonExemptEncryption") is None:
        # Only HTTPS through Apple's frameworks: exempt.
        call("PATCH", f"/v1/builds/{bid}",
             {"data": {"type": "builds", "id": bid, "attributes": {"usesNonExemptEncryption": False}}})
        print("▸ export compliance: no non-exempt encryption")

    # 2. Texts for the testers and the review.
    app_rel = {"app": {"data": {"type": "apps", "id": aid}}}
    for locale, text in DESCRIPTION.items():
        upsert(f"/v1/apps/{aid}/betaAppLocalizations", "betaAppLocalizations", "locale",
               {"locale": locale, "description": text, "feedbackEmail": FEEDBACK, "privacyPolicyUrl": PRIVACY}, app_rel)
    build_rel = {"build": {"data": {"type": "builds", "id": bid}}}
    for locale, text in WHATS_NEW.items():
        upsert(f"/v1/builds/{bid}/betaBuildLocalizations", "betaBuildLocalizations", "locale",
               {"locale": locale, "whatsNew": text}, build_rel)
    print("▸ beta texts EN/DE set")

    # 3. Review contact: the same as for the App Store review.
    version = call("GET", f"/v1/apps/{aid}/appStoreVersions?limit=1")["data"][0]
    store = call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]["attributes"]
    detail = call("GET", f"/v1/apps/{aid}/betaAppReviewDetail")["data"]
    call("PATCH", f"/v1/betaAppReviewDetails/{detail['id']}", {"data": {
        "type": "betaAppReviewDetails", "id": detail["id"], "attributes": {
            "contactFirstName": store["contactFirstName"], "contactLastName": store["contactLastName"],
            "contactPhone": store["contactPhone"], "contactEmail": store["contactEmail"],
            "demoAccountRequired": False, "notes": REVIEW_NOTES}}})
    print("▸ beta review contact and notes set")

    # 4. External group with a public link, the build in it.
    group_attrs = {"publicLinkEnabled": True, "publicLinkLimitEnabled": True,
                   "publicLinkLimit": PUBLIC_LINK_LIMIT, "feedbackEnabled": True}
    group = next((g for g in call("GET", f"/v1/apps/{aid}/betaGroups")["data"] if g["attributes"]["name"] == GROUP), None)
    if group:
        call("PATCH", f"/v1/betaGroups/{group['id']}",
             {"data": {"type": "betaGroups", "id": group["id"], "attributes": group_attrs}})
    else:
        group = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups",
                     "attributes": {"name": GROUP, **group_attrs}, "relationships": app_rel}})["data"]
        print(f"▸ group {GROUP} created")
    call("POST", f"/v1/betaGroups/{group['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
    print(f"▸ build {number} in group {GROUP}")

    # 5. Beta review (only the first build of a version needs a full review; later ones are usually quick).
    submitted = try_call("GET", f"/v1/builds/{bid}/betaAppReviewSubmission")
    if not (submitted and submitted.get("data")):
        call("POST", "/v1/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions", "relationships": build_rel}})
        print("▸ submitted to the beta review")
    state = call("GET", f"/v1/builds/{bid}/buildBetaDetail")["data"]["attributes"]
    link = call("GET", f"/v1/betaGroups/{group['id']}")["data"]["attributes"].get("publicLink")
    print(f"▸ external state: {state.get('externalBuildState')}, internal: {state.get('internalBuildState')}")
    print(f"▸ public link: {link}")


main()
