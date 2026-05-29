# Security And Privacy

## Reporting Issues

Please open a private security advisory or contact the maintainer privately for
security-sensitive issues. Avoid attaching private audio files, transcripts, or
project files to public issues.

## Local Data

The default AutoCut Studio workflow runs locally:

- Source audio is read from the file path you choose.
- Transcripts and project state are stored in local `.autocutproj.json` files.
- Preview playback uses the local source audio.
- Export writes a local MP3 file.

The legacy AutoCut CLI still supports an optional OpenAI Whisper API mode. That
mode is not used by the macOS app MVP. If you enable it manually, audio may be
sent to the configured API provider.

## Secrets

Do not commit `.env` files, API keys, transcripts from private recordings, or
generated project files. The repository `.gitignore` excludes common local
artifacts, including `.env`, `.venv`, `.codex`, `dist`, `*.autocutproj.json`,
and common AutoCut export outputs.
