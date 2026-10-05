# Sidetap interface direction

Sidetap should feel like a quiet macOS instrument: spatial, precise, and calm. It should not look like a generic analytics dashboard or a science-fiction control panel.

References were reviewed on July 16, 2026.

## Reference lessons

- Apple places Liquid Glass in the functional layer—navigation and controls—and recommends standard materials for content. Use system components first and custom glass sparingly. See [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/).
- Linear's 2026 refresh says interface elements should not compete for attention they have not earned, and that structure should be felt rather than seen. Sidetap therefore uses fewer icons, separators, borders, and elevated containers. See [A calmer interface for a product in motion](https://linear.app/now/behind-the-latest-design-refresh).
- Things succeeds through a stable sidebar, a single obvious working area, progressive disclosure, and purposeful motion. Sidetap keeps advanced sensing and rejection controls out of the primary path. See [Things](https://culturedcode.com/things/).
- Raycast's 2026 Mac redesign uses Liquid Glass in ways that support the function of a launcher while staying familiar and compact. Sidetap follows the same rule for its toolbar and primary controls. See [The New Raycast](https://www.raycast.com/blog/the-new-raycast).
- Apple's recognition of iA Writer and Mela reinforces task focus, contextual dimming, and attention to interaction details over decoration. See the [2025 Apple Design Awards](https://developer.apple.com/design/awards/2025/).
- The community-maintained [Slopless design directory](https://www.slopless.design/) is useful as a pattern audit, not a design authority: it identifies the repeated gradients, inflated cards, interchangeable dashboards, and filler copy that make generated interfaces converge on the same look.

## Anti-slop rules

1. No purple–cyan gradients, neon glow, decorative blobs, or forced dark mode.
2. No bento grid of interchangeable metric cards.
3. No boxes inside boxes. A container must communicate real grouping or interaction.
4. No uppercase eyebrow copy, excessive tracking, or oversized marketing headings inside the app.
5. One semantic accent color. Status colors are reserved for success, warning, recording, and error.
6. No decorative icon tiles. Symbols identify actions or objects only.
7. No invented metrics or ornamental charts. Every number must come from real capture or evaluation data.
8. Liquid Glass is for toolbar and important controls. Content uses standard system materials.
9. Prefer native `NavigationSplitView`, `List`, `Form`, `Table`, `LabeledContent`, `Gauge`, `ProgressView`, menus, sheets, and toolbars.
10. Motion explains a state change; nothing continuously pulses merely to look alive.

## Signal-processing lessons

- [Acustico](https://www.cs.dartmouth.edu/~hci/papers/Acustico.pdf) detects a surface tap as a short power pulse whose neighboring windows are substantially quieter. Sidetap applies the same temporal principle after capture, with deliberately looser thresholds because it has only the MacBook microphone rather than contact accelerometers.
- Essentia's [EffectiveDuration](https://essentia.upf.edu/reference/std_EffectiveDuration.html) descriptor explicitly distinguishes percussive from sustained sounds using time above 40% of the envelope maximum. Sidetap combines that cue with late-to-impact energy and early-energy concentration; no single cue rejects an event by itself.
- Research on [on-device mechano-acoustic touch classification](https://doi.org/10.3390/app11114834) supports combining temporal and spectral features with a learned classifier. Sidetap learns from the taps of calibrated double and triple taps, and checks each sound against its nearest calibrated tap and against user-recorded negatives.

## Screen hierarchy

- **Desk:** the current gesture, each gesture's assigned action, one compact result strip, and first-run onboarding in place.
- **Calibration:** one gesture at a time: eight double taps, and then eight triple taps. Beginning setup is the explicit capture intent. A row of dots fills as Sidetap hears each tap of the current attempt, and an attempt counts only when it has exactly the gesture's taps and every tap is clean; otherwise Sidetap says what to change. Listening stops between the two gestures and starts again after a short transition, and a visible Start Listening control remains available after a pause. The final step shows the tap pace that Sidetap learned and surfaces Talking rejection capture as recommended.
- **Actions:** an editor with one row for each gesture: a double tap, a triple tap, and any gesture with more taps that the user adds. Native pickers progressively reveal only the fields needed for the selected action, including Shortcuts, app/file bookmarks, shell commands, recorded keyboard shortcuts, media keys, and screenshot destinations.
- **Diagnostics:** factual hardware and signal details in a form.

The sidebar keeps Desk, Calibration, and Actions in workflow order. The hardware and signal diagnostics live in a separate Advanced section.
