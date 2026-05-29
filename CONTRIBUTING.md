# Contributing

Thanks for helping improve AutoCut Studio.

## Development Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e ".[dev]"
brew install ffmpeg
```

Build and run the macOS app:

```bash
./script/build_and_run.sh
```

Run the focused test suite:

```bash
PYTHONPATH=test:. python test/test_app_project.py
swift test --package-path macos/AutoCutStudio
```

## Contribution Guidelines

- Keep podcast editing behavior covered by focused tests.
- Avoid committing generated audio, transcripts, `.autocutproj.json` files, app
  bundles, or local environment files.
- Preserve upstream AutoCut attribution and Apache-2.0 notices.
- For UI changes, keep the app usable with pointer, keyboard, and visible
  controls.
- For backend changes, keep stdout machine-readable JSON for Swift calls. Human
  logs should go to stderr.
