# Energy efficiency – measurements and changes

Running record of what was measured, what was changed and what it brought (material for a blog post and
the Green IT lectures at HFT Stuttgart). Tools: `tools/energy/` (Instruments Power Profiler and Time
Profiler on the device, release builds, the same scenes every time).

## Setup

- iPhone 17 Pro, iOS 27.2, release builds installed from Xcode.
- Scenes: start screen (60 s), start screen with music (60 s), game against 1 computer and against 3
  computers with the autopilot playing (90 s each). Sound effects on in all scenes.
- Two kinds of numbers:
  - **CPU share** of the app process (Instruments, phone on the cable). Precise, but only the app.
  - **Battery drain of the whole iPhone** in %/h (Power Profiler, phone on battery, connected to the Mac
    over Wi-Fi, auto-brightness off, brightness fixed at 49 %). Median from second 20 on (launch
    excluded). Battery 4,252 mAh ≈ 16 Wh, so 1 %/h ≈ 0.16 W.

## Round 1: start screen, button texts, audio, frame rate (version 1.0.6)

| Scene | CPU before | CPU after | Whole iPhone before | after | change |
|---|---:|---:|---:|---:|---:|
| Start screen | 10.1 % | 2.1 % | 5.94 %/h | 5.16 %/h | −13 % |
| Start screen with music | 10.9 % | 2.8 % | 6.56 %/h | 5.85 %/h | −11 % |
| Game vs. 1 computer | 29.3 % | 23.8 % | 5.73 %/h | 5.46 %/h | −5 % |
| Game vs. 3 computers | 30.6 % | 24.3 % | 5.83 %/h | 5.62 %/h | −4 % |

What brought something:

- **Start screen animation at 30 instead of 60 fps** (stars and grid move slowly), still while another
  page covers it and with Reduce Motion: CPU 10 → 2 %, GPU impact 0.33 → 0.03; the whole phone −11 to −13 %.
- **Button texts built once** – the largest find, only visible in the Time Profiler: the tooltips and
  accessibility labels of the 22 tower and creep buttons were localized anew with every change of the
  credits (20 times a second): about a quarter of the app's CPU time in a game. Now cached per language.

What brought nothing (measurable):

- **Limiting the boards to 60 fps**: iPhone apps run at 60 Hz anyway unless they ask for more
  (`CADisableMinimumFrameDurationOnPhone`). Kept (and 30 fps in Low Power Mode).
- **Game clock at 10 fps while paused**, **audio engine sleeping after 5 s of silence**: right in
  principle, no measurable effect in these scenes (no pauses; sound on).

Lessons:

- Measure before optimizing: the expected culprit (frame rate) was not one, the real one (text building)
  was invisible without a profiler.
- 20 % less CPU for the app is only ~4 % less power for the whole phone in a game: display, radio and
  the system's base load dominate. Judging an optimization by the app's own CPU number overstates it
  about five times.
- The black background of the retro look already saves display power on OLED.

Remaining: drawing the boards (~18 % of the app's CPU time) and SwiftUI's own work.

## Round 2: online games – baseline (version 1.0.11, protocol 7)

Each device sends a packet for every tick, 20 per second, also empty ones. Traffic measured in a real
Game Center game (two iPhones, 15 minutes): about 21 messages and 1.1 KB per second and direction,
about 1 MB per game.

Energy: `tools/energy/online.sh` – the iPhone plays against a simulator on the Mac over the local Wi-Fi
(Bonjour), both with the autopilot, map Rennbahn, 120 s from tick 0; for comparison the same game against
the computer (`-demo -demoFromStart`), right before it. Whole iPhone on battery, median from second 20.

| Scene | CPU | Whole iPhone | Networking impact |
|---|---:|---:|---:|
| Game vs. 1 computer (from tick 0) | 24.0 % | 5.10 %/h | 0.00 |
| Online game over Wi-Fi | 23.2 % | 5.76 %/h | 0.03 |

The online game costs about 13 % more for the whole phone (0.66 %/h ≈ 0.1 W), while the app's CPU share
is the same: the extra comes from the Wi-Fi radio, which can hardly sleep with 20 packets a second in each
direction. Single measurements; the radio's share shows in short spikes (up to 8 %/h).

## Round 3: bundles instead of a packet per tick (version 1.1, protocol 8)

Each device sends a bundle every few ticks: "my commands up to tick T", usually none, with the checksums
and a ping every 2 s inside. Short JSON keys, empty fields left out: an empty bundle is about 33 bytes.
Every device chooses its input delay from the measured round trip (bundle interval + the way to the others
+ 1 tick), at most 400 ms – beyond that the game rather waits now and then than reacting late to every tap.

Measured like round 2, with the network log on the iPhone, two bundle intervals (single measurements;
a first run was disturbed by a video playing on the phone and was repeated):

| | protocol 7 (every tick) | every 2 ticks | every 4 ticks |
|---|---:|---:|---:|
| Messages per second and direction | 21 | 10 | 5 |
| Wi-Fi bytes of the app in 2 minutes (received + sent, with TCP/IP) | 1,139 KB | 774 KB (−32 %) | 445 KB (−61 %) |
| Networking impact (Instruments) | 0.0066 | 0.0066 | 0.0029 |
| Whole iPhone, game vs. computer | 5.10 %/h | 5.32 %/h | 5.32 %/h |
| Whole iPhone, online game | 5.76 %/h | 5.78 %/h | 5.59 %/h |
| Extra for online | +0.66 %/h (+13 %) | +0.46 %/h (+9 %) | +0.27 %/h (+5 %) |
| Round trip iPhone ↔ simulator (median) | – | 222 ms | 241 ms |
| Time the game waited in 112 s | 0 (fixed delay 200 ms) | 1.0 s | 5.9 s |

Every 4 ticks saves the most – the iPhone's Wi-Fi sleeps between the packets – but packets *to* the phone
wait for its next wake-up, and the game stalled for a moment in more than half of all seconds. Every 2 ticks
still stalled now and then (1 s in two minutes). **Decision: a bundle every tick, as before** – the game must
not stall, not even rarely; game feel comes first. What protocol 8 keeps: the shorter messages, the
checksums inside the bundles instead of messages of their own, and the input delay from the measured round
trip (at most 400 ms).

Lesson for the blog: the energy of the radio and the reaction time are the same dial here. Fewer packets let
the Wi-Fi sleep – and that is exactly why packets to the phone arrive later. A measurable saving (a third of
the extra energy) was not worth a game that stalls.

The round trip includes the simulator on the Mac, which picks up its messages late when it is busy
(between two simulators on the same Mac: 250–600 ms). Between two iPhones it should be shorter; the real
test with people decides about the game feel.
