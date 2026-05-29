# Development

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e ".[dev]"
brew install ffmpeg
```

The macOS app expects the backend Python at `.venv/bin/python` when launched
from the generated app bundle.

## Build And Run

```bash
./script/build_and_run.sh
```

Useful modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

The script creates `dist/AutoCutStudio.app`. The bundle is generated output and
should not be committed.

## Tests

Focused local checks:

```bash
PYTHONPATH=test:. python test/test_app_project.py
swift test --package-path macos/AutoCutStudio
```

Backend smoke checks:

```bash
python -m autocut.app_backend probe --media test/media/test005.mp3
python -m autocut.app_backend transcribe \
  --media test/media/test005.mp3 \
  --lang en \
  --model base \
  --vad 0 \
  --progress
```

The full legacy AutoCut test suite includes Whisper transcription tests and may
download or load model weights, so it is slower than the focused app tests.

## Release Checklist

Before publishing a public repository:

- Run the focused Python and Swift tests.
- Run a secret/path scan:

  ```bash
  rg -n --hidden -S "<local-user>|<private-file-name>|<api-key-prefix>" \
    -g '!/.git/**' \
    -g '!/.venv/**' \
    -g '!/macos/AutoCutStudio/.build/**' \
    -g '!/dist/**' \
    .
  ```

- Confirm no private audio, transcript, `.autocutproj.json`, app bundle, or
  virtual environment files are staged.
- Confirm `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md` are present.
- If distributing a prebuilt app bundle, review licenses for bundled Python,
  FFmpeg, Whisper model weights, and wheels.
