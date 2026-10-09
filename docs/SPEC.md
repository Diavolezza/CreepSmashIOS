# CreepSmash iOS – Game Rules and Values

Source: the Java original (github.com/khakulov/CreepSmash), written in the course *Informatikprojekt 2* at HFT Stuttgart.
This document records what the Swift remake takes over and where it deliberately deviates.

## 1 Game principle

- 2 to 4 players, each with an own board showing the same map (the app: 2 over the network, up to 4 against the computer).
- Start: 20 lives, 500 credits (original: 200 – the opening was too slow), 200 credits income.
- Every 15 seconds the income is added to the credits.
- Credits buy towers on your own board (defense) or send creeps to the next player's board (attack).
- Every creep you send raises your income permanently.
- A creep that reaches the end of the path costs the board owner one life and then continues on the board of the next living player – never on the sender's board. With 2 players it simply starts again on the opponent's board.
- A creep that is shot down pays its bounty to the board owner.
- A player with 0 lives is out; their towers stop shooting, creeps on their board move on to the next player. The last survivor wins.
- Player order (ring): player 1 → 2 → 3 → 4 → 1. In the original: top left → top right → bottom right → bottom left.

## 2 Timing

| Value | Original | Remake |
|---|---|---|
| Tick | 50 ms (20 ticks/s) | same |
| Income interval | 300 ticks = 15 s | same |
| Lead time before the game starts | 300 ticks (loading + countdown) | 100 ticks (5 s countdown), configurable |
| First income | at game start | same |
| Action until effect (build, upgrade, sell, strategy) | about 50 ticks (server delay during which the tower is "under construction" and does not shoot) | input delay (4 ticks) + 40 ticks build time, configurable |

## 3 Board and map

- 16 × 16 cells of 20 pixels → 320 × 320 pixels per player.
- Map file (text): a line with the image file (`.jpg`/`.png`), path points `x,y` (in walking order), blocked cells `x;y`; lines starting with `#` are comments.
- Path cells and blocked cells cannot be built on; each cell holds at most one tower.
- Maps: six own designs (Blue, Neon, Spirale, Canyon, Platine, Vulkan), generated with `tools/maps/generate.py` and embedded with `tools/maps/embed.py`. The original map BLUE (75 path points) is only used by the tests (`Tests/.../OriginalBlueMap.swift`).

## 4 Creeps

Movement: a path segment (from point i to point i+1) has 1000 steps. Each tick a creep advances by `speed` steps. A creep with speed 70 therefore needs a little over 14 ticks (0.7 s) per cell.

| # | Name | Price | Income | Health | Speed | Bounty | Special |
|---|---|---:|---:|---:|---:|---:|---|
| 1 | Mercury | 50 | 5 | 300 | 70 | 5 | |
| 2 | Mako | 100 | 10 | 700 | 65 | 10 | |
| 3 | Fast Nova | 250 | 25 | 1,400 | 80 | 25 | |
| 4 | Large Manta | 500 | 50 | 3,500 | 50 | 50 | |
| 5 | Demeter | 1,000 | 90 | 7,000 | 60 | 90 | |
| 6 | Ray | 2,000 | 180 | 14,000 | 65 | 180 | immune to slowing |
| 7 | Speedy Raider | 4,000 | 360 | 30,000 | 90 | 360 | fast |
| 8 | Big Toucan | 8,000 | 720 | 80,000 | 60 | 720 | |
| 9 | Vulture | 15,000 | 1,200 | 140,000 | 70 | 1,200 | |
| 10 | Shark | 25,000 | 2,000 | 250,000 | 75 | 2,000 | immune to slowing |
| 11 | Racing Mamba | 40,000 | 3,200 | 500,000 | 100 | 3,200 | fast |
| 12 | Huge Titan | 60,000 | 4,800 | 1,200,000 | 65 | 4,800 | |
| 13 | Zeus | 100,000 | 7,000 | 1,500,000 | 65 | 7,000 | regenerates 500 health per tick |
| 14 | Phoenix | 200,000 | 14,000 | 2,500,000 | 80 | 14,000 | immune to slowing |
| 15 | Express Raptor | 400,000 | 28,000 | 6,000,000 | 140 | 28,000 | very fast |
| 16 | Fat Colossus | 1,000,000 | 56,000 | 15,000,000 | 70 | 56,000 | |

Income = 10 % (creeps 1–4), 9 % (5–8), 8 % (9–12), 7 % (13–16) of the price.

Wave: a tap sends one creep. In the original a long press sent a wave of up to 20 creeps of the same type (as many as the credits allow), 130 ms apart. The remake sends one creep after the other (every 120 ms) for as long as the button is held, until the credits run out; the credits count down with each creep. (The computer opponent still uses the wave command, up to 20 creeps 3 ticks apart.)

## 5 Towers

Columns: price (of the level; an upgrade costs the price of the next level), range (pixels), reload time (ticks between two shots), damage per shot, splash radius (pixels), splash falloff at the edge, slowing (fraction), slowing duration (ticks).

| Tower | Level | Price | Range | Reload | Damage | Splash | Falloff | Slow | Slow ticks | Weapon |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Basic | 1 | 50 | 35 | 13 | 25 | – | – | – | – | laser |
| | 2 | 100 | 40 | 13 | 50 | – | – | – | – | laser |
| | 3 | 750 | 45 | 13 | 200 | – | – | – | – | laser |
| | 4 | 2,000 | 50 | 13 | 750 | – | – | – | – | laser |
| Slow | 1 | 100 | 35 | 15 | 25 | – | – | 30 % | 40 | slow laser |
| | 2 | 200 | 45 | 16 | 50 | – | – | 35 % | 40 | slow laser |
| | 3 | 400 | 50 | 17 | 75 | – | – | 45 % | 50 | slow laser |
| | 4 | 3,000 | 55 | 18 | 100 | 25 | 0.7 | 50 % | 50 | slow splash |
| Splash | 1 | 250 | 40 | 15 | 50 | 35 | 0.7 | – | – | splash laser |
| | 2 | 750 | 45 | 12 | 200 | 35 | 0.7 | – | – | splash laser |
| | 3 | 3,000 | 55 | 10 | 400 | 35 | 0.6 | – | – | splash laser |
| | 4 | 7,500 | 60 | 10 | 1,100 | 35 | 0.5 | – | – | splash laser |
| Rocket | 1 | 1,000 | 50 | 75 | 1,000 | 25 | 0.8 | – | – | rocket |
| | 2 | 3,000 | 60 | 75 | 2,500 | 25 | 0.8 | – | – | rocket |
| | 3 | 7,500 | 70 | 65 | 7,500 | 30 | 0.7 | – | – | rocket |
| | 4 | 15,000 | 80 | 60 | 15,000 | 35 | 0.6 | – | – | rocket |
| Speed | 1 | 1,000 | 50 | 9 | 225 | – | – | – | – | laser |
| | 2 | 3,000 | 55 | 7 | 450 | – | – | – | – | laser |
| | 3 | 7,500 | 60 | 5 | 1,100 | – | – | – | – | laser |
| | 4 | 15,000 | 65 | 3 | 1,800 | – | – | – | – | laser |
| Ultimate | 1 | 20,000 | 100 | 100 | 25,000 | – | – | – | – | laser |
| | 2 | 50,000 | 150 | 50 | 40,000 | – | – | – | – | laser |

- Selling returns 75 % of all level prices paid.
- Range: distance between the cell centers of tower and creep < range.
- A tower fires as soon as its reload time has passed and its target strategy finds a creep in range; then the reload time starts again.

### Weapons

- **Laser:** full damage to the target immediately.
- **Slow laser:** like the laser; afterwards the target (unless immune) is slowed to `base speed × (1 − slow)` for the slowing duration, but only if that makes it slower than it is now.
- **Splash laser:** hits all active creeps within the splash radius around the target. Damage per creep = `damage − damage × falloff × distance / splash radius`.
- **Slow splash:** splash laser plus slowing of all creeps hit.
- **Rocket:** flies to the target and accelerates on the way (0.075 px per tick, +0.03 px each tick). If the target dies first, the rocket picks a new target by its strategy, otherwise it fizzles. On impact it deals splash damage as above.

### Target strategies

| Strategy | Choice among the creeps in range | Default for |
|---|---|---|
| Closest | smallest distance to the tower | Basic, Splash |
| Farthest | furthest along the path | – |
| Fastest | highest current speed, non-immune preferred | Slow |
| Strongest | most health | – |
| Weakest | least health | Rocket, Speed, Ultimate |

"Locked": the tower keeps its last target as long as it lives and stays in range.
On a tie the creep checked last wins (order: order of entry on the board).

Finding in the original code: for Fastest, Strongest and Weakest the comparison is reversed. "Strongest" actually picks the creep with the least health, "Weakest" the one with the most, "Fastest" the slowest. The remake implements the strategies as named. So that Rocket, Speed and Ultimate behave as players are used to, their default is "Weakest" (in the original it was called "Strongest" but acted as "Weakest").

## 6 Network (lockstep)

Original: the server assigns each action an execution round (`current round + 50`) and sends it to all clients; every client runs the same simulation. The server also sets the pace (the highest round clients may compute).

Remake without a server (`CreepSmashCore/Sources/CreepSmashCore/Network.swift`):

- Every device runs the complete simulation of all boards.
- Inputs get an execution tick (`current tick + input delay`) and are sent to the other player.
- Each player sends one packet per tick, even if it is empty. A device computes a tick only once the other player's packet for that tick has arrived; otherwise it waits ("Waiting for …").
- Every 20 ticks the devices exchange a checksum of the game state. If they differ, the game has diverged (a bug; shown to the player, the game stops).
- Credits and income of all players are part of the shared state. An action is checked when it executes (enough credits, cell free, tower ready); if it is invalid it is dropped the same way on every device. This replaces the anti-cheat part of the old server.
- Setup: the player who hosts the game (player 0) picks the map and sends map and rules to the guest after a handshake that checks the protocol version (`NetMessage.protocolVersion`, to be raised with every change to rules, simulation or messages).
- Pause applies to both devices. Leaving the game (or losing the connection) counts as surrender; the other player wins.
- Transports: TCP via Bonjour (`_creepsmash._tcp`, same network or peer-to-peer between nearby devices); Game Center will follow. For the code game the host advertises a service whose name contains the code; for the quick game every device advertises and browses at the same time, and the device with the smaller random id connects to the other.

## 7 Deliberate deviations from the original

1. Integer arithmetic instead of `double` (positions in milli-pixels, integer square root), so all devices compute bit-identically. Angles and rendering are computed in the UI only.
2. Credits are not deducted locally right away but when the command executes in the shared state. Until then the UI shows the reserved costs.
3. Countdown 5 s instead of 15 s.
4. Layout: landscape, both boards the same size side by side. iPhone: towers on the left, creeps on the right. iPad: the boards use the full width, towers below the own board, creeps below the opponent's board.
5. Target strategies work as named (see section 5).
6. Start credits 500 instead of 200.
7. Send modes "next", "all" and "random" (the original's game modes 0–2) can be switched by each player during the game instead of being fixed for the whole game. "All" sends the creep to every living opponent; price, income bonus and health count once per recipient. "Random" draws the recipient from the game state, so every device draws the same.
8. Layouts with more than two players: iPhone – the next opponent's board large, a chip per opponent above it (a tap shows that board); iPad landscape – the own board large, the opponents small next to it, the creeps beside them; iPad portrait – the opponents small at the top, the creeps below them, the own board at the bottom. The board that receives the own creeps is framed in gold.
9. Statistics per player: damage done by the towers and health of all creeps sent (for the evaluation after the game).
10. Graphics: towers and creeps are own designs (`tools/sprites/sprites.py`), line drawings rendered large and scaled down smoothly. Colors mean the same as in the original: a tower's level is green, yellow, red, white; creeps cycle green, gray, yellow, red in each group of four, and white creeps (Ray, Shark, Phoenix) cannot be slowed down. A tower turns its barrel towards the creep it shoots at (display only, not part of the game state).
11. Sound effects are synthesized (`tools/sounds/sfx.py`), not the original recordings; same events, same file names.
12. A tower does not fire while it is being built or upgraded (in the original it fired during the upgrade). It still fires while it is sold or changes its target strategy.
13. Computer opponents have playing styles (favorite tower line, where along the path they build, how much they invest in attacks, swarms or strong waves, decision rhythm), drawn anew for every game, so several computers do not play alike. Tests use the neutral style.
14. In a game against computers the game stops for the player who is out (the remaining computers are not played on in the background); the result shows the player's place.
