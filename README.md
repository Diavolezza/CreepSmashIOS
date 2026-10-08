# CreepSmash for iOS

A remake of the multiplayer tower defense game **CreepSmash** as an iPhone/iPad/Mac app in Swift. The original Java version was written in the summer semester of 2008 by ten computer science students in the course *Informatikprojekt 2* at HFT Stuttgart (University of Applied Sciences), supervised by Prof. Dr.-Ing. Gerhard Wanner.

Two players, landscape: your own board and your opponent's board side by side. Spend your credits on towers to defend, or send creeps to your opponent – every creep you send raises your income for good.

## Project layout

| Folder | Contents |
|---|---|
| `CreepSmashCore/` | Game core as a Swift package without UI: rules, values, deterministic simulation, network lockstep, computer opponent, tests |
| `CreepSmash/` | iOS app (SwiftUI): menu, boards, controls, effects, sound, matchmaking |
| `CreepSmash.xcodeproj` | Xcode project (Xcode 16 or later; files in `CreepSmash/` are picked up automatically) |
| `Config/Info.plist` | Info.plist keys Xcode cannot generate (local network / Bonjour) |
| `docs/SPEC.md` | Game rules and values from the original, deliberate deviations |
| `tools/` | Python scripts that generate the maps, the tower and creep sprites, the sound effects, the music, the logo and the app icon |

## Build and run

1. Open `CreepSmash.xcodeproj` in Xcode.
2. For a real device: select your team under *Signing & Capabilities* of the *CreepSmash* target.
3. Pick an iPhone simulator or device and press ⌘R.

From the command line:

```sh
./build.sh            # test the game core + build the app for the simulator
./build.sh run        # also install and start it in the simulator
./build.sh demo       # start a game with autopilot, fast-forward, take a screenshot
./build.sh duo        # two simulators play each other over the local network
./build.sh duo quick  # same, using "quick game" instead of a code
./build.sh play       # two visible simulators: you vs. the autopilot over the network
./build.sh shot …     # start the app invisibly with launch arguments, take a screenshot
./build.sh commit     # commit everything with the message in build/commit-msg.txt and push
./build.sh stop       # shut down all simulators
```

Output also goes to `build.log`. To test only the game core: `cd CreepSmashCore && swift test`

## License

The remake's code, graphics, sounds and music are under the MIT License (see `LICENSE`); all of them
were made anew for this app, nothing is taken over from the original. The fonts Press Start 2P,
VT323 and Orbitron are under the SIL Open Font License 1.1 (OFL files next to the fonts). The game
idea, rules and values follow the original CreepSmash (2008), which was published under the GPLv3;
the tests use the path points of its map "Blue" (`OriginalBlueMap.swift`) to check the rules
against known values.

## Open

- Game Center as an additional way to find opponents (needs an Apple Developer membership)

## Technical notes

- **Lockstep:** every device runs the full simulation; only commands with their execution tick are exchanged. The `Match` protocol hides where commands come from: `LocalMatch` plays against the computer, `NetworkMatch` against another device over any `Transport`.
- **Determinism:** the core only uses integers (positions in milli-pixels), so all devices stay bit-identical. Both devices exchange `Game.checksum()` every 20 ticks to detect divergence.
- **Matchmaking:** the player sees the same three options regardless of the network – *quick game*, *host a game* (shows a code) and *join with code*. Behind the scenes the app looks for the other player nearby via Bonjour (same Wi-Fi or peer-to-peer) and, later, via Game Center.
- **Languages:** English is the source language, German the translation (String Catalog). The flag on the start screen switches the language inside the app; without a choice the device language decides. `L("…")` in `AppLanguage.swift` looks up a text in the chosen language.
- **Records:** statistics, a leaderboard of the fastest wins per difficulty and tiered achievements are kept on the device (`Progress.swift` in the core, `ProgressStore.swift` in the app); Game Center can mirror them later.
- **Timing:** 20 ticks per second as in the original; rendering interpolates creep movement to the display refresh rate.
