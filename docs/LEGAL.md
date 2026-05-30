# License Notes

This is a practical engineering summary, not legal advice.

## AutoCut / Apache-2.0

The upstream `mli/autocut` repository in this checkout is licensed under the
Apache License, Version 2.0. Apache-2.0 is a permissive open-source license that
allows use, modification, distribution, sublicensing, and distribution of
derivative works, as long as the license conditions are followed.

For this project, the important obligations are:

- Keep a copy of the Apache-2.0 license in the distribution.
- Preserve upstream copyright, patent, trademark, and attribution notices that
  apply to the source.
- Mark modified files with a prominent notice that they were changed.
- Include the upstream `NOTICE` contents if the upstream work provides a NOTICE
  file. This checkout does not contain an upstream NOTICE file, but this fork
  adds its own `NOTICE` for clarity.
- Do not imply that upstream maintainers endorse this fork.

This means wrapping AutoCut in a macOS app is generally compatible with
Apache-2.0, including for a public open-source release, provided the attribution
and notice obligations are kept.

## AutoCut, Not AutoCAD

This repository uses AutoCut. It does not integrate with Autodesk AutoCAD. If a
future version adds AutoCAD or Autodesk SDK usage, that would require a separate
license review.

## Dependencies

The source repository does not bundle FFmpeg, Python wheels, Whisper model
weights, or a Python runtime. If a release later ships a complete binary app
bundle, review the exact bundled artifacts and include their license texts.

FFmpeg deserves special care because its effective license depends on build
configuration and enabled codecs.

## Practical Release Position

For a source-only public release, the current low-risk path is:

- Keep this repository under Apache-2.0.
- Keep `LICENSE`, `NOTICE`, `CHANGES.md`, and `THIRD_PARTY_NOTICES.md`.
- Make clear that this is derived from `mli/autocut`.
- Do not commit private media or generated project files.
- Do not bundle FFmpeg or model weights until their exact license obligations
  are reviewed for that distribution format.
