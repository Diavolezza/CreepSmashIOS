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

## Next: online games over Game Center

To be measured: traffic and energy of an online game (each device sends a packet for every tick,
20 per second, also empty ones), before and after batching or a smaller encoding.
