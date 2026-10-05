# Sidetap

**Double-tap or triple-tap your desk to run an action on your Mac.**

Sidetap is a macOS app that listens through your MacBook's built-in microphone, recognizes taps on your desk, and counts them. Audio is processed on your Mac and never leaves it.

Sidetap is an experimental prototype and a fork of [Holo](https://github.com/JustinGamer191/Holo) by JustinGamer191.

## Actions

Each gesture runs one action that you choose:

- Play a sound or speak text.
- Copy or paste text.
- Open a website, an app, a file, or a folder.
- Run a Shortcut or a shell command.
- Press a keyboard shortcut that you record.
- Press a media key: play or pause, next or previous track, volume up or down, or mute.
- Take a screenshot of the full screen or a selected area, saved to the Desktop, the clipboard, or both.

Until you assign an action, a gesture only shows in the app. Shell commands run without confirmation and inside Sidetap's sandbox, so use commands that are safe to repeat. For anything that the sandbox blocks or that takes several steps, run a Shortcut.

The first time an action pastes text, presses keys, or takes a screenshot, macOS might ask for Accessibility or Screen Recording access.

## Requirements

- A MacBook that runs macOS 14 or later. Sidetap always uses the built-in microphone, whatever the system input is.
- Xcode, because you build Sidetap from source. Xcode 26 is recommended.

## Install

1. Create the local signing certificate. You do this one time. For the commands, see [Install a local build](CONTRIBUTING.md#install-a-local-build).
1. Build, sign, and install Sidetap:

   ```sh
   ./scripts/install_local.sh
   ```

The script installs Sidetap in `~/Applications` and opens it. Because every build is signed with the same certificate, macOS keeps the app's permissions when you rebuild.

## Set up a desk

1. Put the MacBook where it stays during use. If you move or rotate it later, recalibrate.
1. In **Calibration**, click **Begin Calibration**. macOS asks for microphone access.
1. Follow the prompts to tap ten times in each of four areas around the MacBook.
1. Click **Save and Set Actions**, and then choose an action for **Double tap** and for **Triple tap**.
1. Click **Desk**. Actions run only while **Desk** is selected.

## Gestures

Gestures work anywhere on the calibrated desk. A desk starts with a double tap and a triple tap. To add a gesture with one more tap, click **Add Gesture** in **Actions**. You can add as many as you want.

- Taps that are no more than 0.45 seconds apart belong to one gesture.
- The gesture with the most taps runs its action at its last tap.
- Any other gesture runs its action about 0.7 seconds after its last tap, when no further tap can follow.
- A single tap does nothing.

To avoid false triggers, Sidetap ignores a tap within 0.3 seconds of a key press or a click, and it runs no actions while the room is too loud.

## Multiple desks

To use Sidetap at more than one desk, calibrate a profile at each desk. Then, in the profile menu on the toolbar, choose **Use This Location for** the profile. Sidetap switches to a profile when the Mac is within 300 m of where you pinned it.

## Privacy

Sidetap is sandboxed and uploads nothing. It discards raw audio after analysis, and a profile stores acoustic features, not recordings. The one exception is the debug recording option in **Diagnostics**, which is off at every launch and saves 90 ms clips locally until you delete them.

## Limitations

- A profile fits one MacBook position on one desk.
- Rigid desks, such as wood or laminate, work best. Soft mats, laptop stands, and desks that shift are unsupported.
- Sidetap can miss a light tap, and a sharp sound such as a dropped object can count as a tap.
- A gesture with more taps fails more often, because each tap can be missed. A missed tap runs the action of a gesture with fewer taps.
- Accuracy is measured on one MacBook and one desk only. For the evidence, see [Sidetap acceptance audit](ACCEPTANCE.md).

## Development

- For build, test, and verification tools, see [Contributing to Sidetap](CONTRIBUTING.md).
- For the interface rules and signal-processing references, see [Sidetap interface direction](DESIGN.md).
- For signed and notarized releases, see [Releasing Sidetap](RELEASING.md).

## License

Sidetap is available under the [MIT License](LICENSE).
