# Blinq

A lightweight macOS menu bar app that reminds you to take screen breaks, and stays out of the way when you're on a call.

## Features

- **Break reminders**: a full-screen, blurred break overlay every *N* minutes with a countdown ring and a rotating tip.
- **Heads-up bar**: a translucent bar slides in at the top of every screen 10 seconds before a break, with *Skip*, *Snooze* and *Start now*.
- **Call-aware**: pauses automatically while Google Meet, Slack, Teams, Zoom, FaceTime, Webex, Discord or WhatsApp is using your microphone. When the call ends, it suggests a break if you've been at it long enough.
- **Posture and blink nudges**: separate lightweight reminders ("Sit up straight", "Blink your eyes") that show as a small toast, never a blackout.
- **Smart resets**: idle time, screen lock and sleep count as a break.
- **Sounds**: a configurable system sound for each event (warning, break start and end, posture, blink).
- **Stats**: breaks taken and skipped today, shown in the menu.
- **Launch at login**.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode command line tools (Swift 5.9+)

## Build and run

```sh
./bundle.sh
```

This builds a release binary, wraps it in `Blinq.app` (notifications and launch-at-login need a real app bundle), ad-hoc signs it and opens it. Move `Blinq.app` to `/Applications` if you want it permanently.

For quick iteration you can also run `swift run`; notifications are disabled in that mode.

## How call detection works

Blinq uses CoreAudio process objects (`kAudioHardwarePropertyProcessObjectList`) to see **which apps are currently capturing microphone input**. If one of them is a known call app or browser, you're treated as being in a call. This requires **no permissions**, never reads audio, and ignores things like Siri or dictation.

During a call the break timer keeps counting (screen time is still screen time) but never interrupts you. About 30 seconds after the call ends, Blinq sends a "Call ended — take a break?" notification if a break is due.

## Settings

| Setting | Default |
|---|---|
| Work interval | 20 min |
| Break length | 20 sec |
| Snooze length | 5 min |
| Next break after skip | 10 min |
| Reset after idle for | 5 min |
| Sit up straight reminder | every 15 min |
| Blink reminder | every 10 min |

Each reminder can have a custom message (leave it blank to rotate built-in tips) and its own sound.

## Testing

The menu has a **Test** submenu to trigger the heads-up bar, a full break, or each nudge immediately. You can also fire a nudge at launch:

```sh
BLINQ_TEST=blink ./Blinq.app/Contents/MacOS/Blinq   # or posture
```

## Project layout

```
Sources/Blinq/
├── main.swift          App entry, menu bar, settings UI
├── Scheduler.swift     Break state machine, timers, notifications
├── CallDetector.swift  Per-process mic detection and screen-share heuristic
├── UI.swift            Break overlay and heads-up bar
├── Nudges.swift        Posture and blink reminders
└── Sounds.swift        Per-event sounds
```
