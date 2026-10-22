# App Store Connect – metadata

Everything App Store Connect asks for when the app is created, in English (primary language) and German.
Character limits are Apple's; `tools/appstore/check.py` counts them.

## App information

| Field | Value |
|---|---|
| Name | CreepSmash |
| Bundle ID | de.wanner-it.creepsmash.game |
| SKU | creepsmash-ios |
| Primary language | English (U.S.) – German added as a second localization |
| Primary category | Games › Strategy |
| Secondary category | Games › Action |
| Content rights | Contains no third-party content (all graphics, sounds, music and maps are own work; fonts under the SIL Open Font License) |
| Copyright | 2026 Gerhard Wanner |
| Seller / provider | Gerhard Wanner (individual account) |
| Price | Free |
| Availability | All countries |
| Platforms | iPhone, iPad; Mac with Apple silicon ("Designed for iPad") and Apple Vision Pro: allow |

## URLs

| Field | Value |
|---|---|
| Privacy policy URL | https://diavolezza.github.io/creepsmash/privacy.html |
| Support URL | https://diavolezza.github.io/creepsmash/support.html |
| Marketing URL | (optional, none) |

The two pages are in `docs/appstore/web/` (both languages on one page each) and are published on GitHub Pages
from the repository Diavolezza/Diavolezza.github.io (folder `creepsmash/`, next to the site's legal notice).

## App privacy ("nutrition label")

- Data collection: **"No, we do not collect data from this app."**
- Reason: no accounts, no server, no analytics, no ads. Records and the saved game stay on the device; in a
  multiplayer game the player name and the game inputs go directly to the other devices on the local network
  and are not stored by anyone. Game Center (once enabled) is Apple's service; data Apple processes there is
  not declared by the developer.
- Privacy manifest: `CreepSmash/PrivacyInfo.xcprivacy` (no tracking, no collected data; UserDefaults with
  reason CA92.1).
- Export compliance: `ITSAppUsesNonExemptEncryption = NO` in `Config/Info.plist` (no own encryption).

## Age rating (questionnaire)

| Question | Answer |
|---|---|
| Cartoon or fantasy violence | Infrequent/mild (towers shoot abstract spaceships, which explode – no people, no blood) |
| Realistic violence, horror, sexual content, nudity, profanity, drugs, alcohol, tobacco, gambling, contests, medical topics, mature themes | None |
| Unrestricted web access | No |
| User-generated content, messaging or chat | No (only the player name is shown to the other players on the local network) |
| Advertising | No |
| In-app purchases, loot boxes | No |
| Parental controls, age assurance | No |

Expected result: 9+ because of the mild fantasy violence. Answering "none" would give 4+; the honest answer is
"infrequent/mild".

## Texts – English (U.S.)

**Subtitle** (max. 30)

```
Multiplayer tower defense
```

**Promotional text** (max. 170, can be changed at any time without a new version)

```
Defend or attack? Every creep you send raises your income. Play against up to three computers or with friends on the same network, no account needed.
```

**Keywords** (max. 100, comma-separated, no spaces; words from the name and subtitle count anyway)

```
td,strategy,creeps,towers,versus,local,lan,offline,retro,arcade,wifi,friends,pvp,maze,defence,party
```

**Description** (max. 4000)

```
CreepSmash is a tower defense game for two to four players. Every player has a board with the same path. You build towers that shoot down the creeps walking along your path, and you send creeps to the next player. Every creep you send raises your income for good. So every credit is a decision: defense now, or more income later.

HOW IT WORKS
• Everyone starts with 20 lives. A creep that reaches the end of your path costs you a life and walks on to the next player.
• 6 tower types: laser, slowing laser, splash laser, rockets, rapid fire and the Ultimate tower, each with several levels.
• 16 creep types, from cheap swarms to the Fat Colossus. White creeps cannot be slowed down.
• Every tower aims at the nearest, farthest, fastest, strongest or weakest creep.
• The last player with lives left wins.

HOW TO PLAY
• Against 1 to 3 computer opponents on three levels. Every computer plays in its own style.
• Multiplayer for 2 to 4 people on the same Wi-Fi network or nearby: no account, no server, no internet. Free seats can be given to computers. If the host leaves, another player takes over.
• 14 maps, 8 of them with special sections from the original game: fast lanes, portals, laps, dead ends and crossings.
• Games against the computer are saved and can be continued later.

AFTER THE GAME
• An evaluation with income, lives, attack and defense over the whole game.
• Your defense seen with Green IT eyes: how much you stopped, how much of your towers' capacity was actually used, and how much of your income went into defense. Building far more than you need is the same waste as in a data center.
• Leaderboard, statistics and 17 achievements, stored on your device.

ABOUT
CreepSmash was written in Java in 2008 by ten computer science students at HFT Stuttgart, University of Applied Sciences. This is a new version for iPhone, iPad and Mac with new graphics, sounds, music and maps.

No ads, no in-app purchases, no tracking. In English and German.
```

## Texts – German

**Untertitel** (max. 30)

```
Tower Defense für 2 bis 4
```

**Werbetext** (max. 170)

```
Verteidigen oder angreifen? Jeder Creep, den du schickst, erhöht dein Einkommen. Spiel gegen bis zu drei Computer oder mit Freunden im selben Netz, ohne Konto.
```

**Schlüsselwörter** (max. 100)

```
td,strategie,türme,creeps,mehrspieler,lokal,offline,retro,wlan,freunde,duell,verteidigung,arcade
```

**Beschreibung** (max. 4000)

```
CreepSmash ist ein Tower-Defense-Spiel für zwei bis vier Spieler. Jeder hat ein Spielfeld mit demselben Weg. Du baust Türme, die die Creeps auf deinem Weg abschießen, und du schickst Creeps zum nächsten Spieler. Jeder Creep, den du schickst, erhöht dein Einkommen dauerhaft. Jeder Credit ist also eine Entscheidung: jetzt verteidigen oder später mehr verdienen.

SO FUNKTIONIERT ES
• Jeder beginnt mit 20 Leben. Ein Creep, der das Ende deines Wegs erreicht, kostet ein Leben und läuft beim nächsten Spieler weiter.
• 6 Turmarten: Laser, Bremslaser, Splash-Laser, Raketen, Schnellfeuer und der Ultimate-Turm, jeweils mit mehreren Stufen.
• 16 Creep-Arten, vom billigen Schwarm bis zum Fat Colossus. Weiße Creeps lassen sich nicht bremsen.
• Jeder Turm zielt auf den nächsten, fernsten, schnellsten, stärksten oder schwächsten Creep.
• Wer als Letzter noch Leben hat, gewinnt.

SO WIRD GESPIELT
• Gegen 1 bis 3 Computer in drei Stärken. Jeder Computer hat seinen eigenen Spielstil.
• Mehrspieler für 2 bis 4 Personen im selben WLAN oder in der Nähe: ohne Konto, ohne Server, ohne Internet. Freie Plätze können Computer übernehmen. Geht der Eröffner, übernimmt ein anderer Spieler.
• 14 Karten, 8 davon mit Besonderheiten aus dem Originalspiel: Schnellbahnen, Portale, Runden, Sackgassen und Kreuzungen.
• Spiele gegen den Computer werden gespeichert und lassen sich später fortsetzen.

NACH DEM SPIEL
• Eine Auswertung mit Einkommen, Leben, Angriff und Abwehr über das ganze Spiel.
• Deine Abwehr aus Green-IT-Sicht: wie viel du abgewehrt hast, wie viel der Kapazität deiner Türme wirklich genutzt wurde und welcher Anteil deines Einkommens in die Abwehr ging. Wer weit mehr baut als nötig, verschwendet wie ein überdimensioniertes Rechenzentrum.
• Bestenliste, Statistik und 17 Erfolge, gespeichert auf deinem Gerät.

ÜBER DAS SPIEL
CreepSmash entstand 2008 in Java als Projekt von zehn Informatik-Studierenden an der Hochschule für Technik Stuttgart. Dies ist eine Neuauflage für iPhone, iPad und Mac mit neuer Grafik, neuen Klängen, neuer Musik und neuen Karten.

Keine Werbung, keine In-App-Käufe, kein Tracking. Auf Deutsch und Englisch.
```

## Notes for App Review

```
CreepSmash needs no account and no server.

Single player: tap "Vs. computer", choose a map, the number of opponents (1 to 3 computers) and the difficulty, then "Start game".

Multiplayer works only on the local network (Bonjour, peer-to-peer Wi-Fi) and needs a second device with the same app version: on one device "Multiplayer" > "Open a round" > "Open", on the other "Multiplayer" > the round in the list > "Join" (or "Join with a code" and the code shown on the first device); the first device then taps "Start". "Quick game for two" pairs two devices that both tap it. The app asks for permission to use the local network the first time "Multiplayer" is opened.
```

## Screenshots

Generated with `./build.sh script` and `tools/appstore/screenshots.sh` (iPhone landscape, iPad portrait, both languages):

| Display | Simulator | Size (px) |
|---|---|---|
| iPhone 6.9" | iPhone 18 Pro Max | 2868 × 1320 |
| iPad 13" | iPad Pro 13-inch (M5) | 2064 × 2752 |

Apple scales them down for the smaller displays. Output: `build/appstore/<language>/<device>/NN-<name>.png`
(not in git).
