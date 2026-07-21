# Jiva

Fully-local meeting intelligence for Mac. Jiva records your meetings, transcribes both sides with speaker labels, summarizes live in a floating overlay, and types hands-free dictation — all on-device. No cloud, no account, nothing ever leaves your computer.

**[⬇ Download Jiva for Mac](https://github.com/venugopalarjun/jiva/releases/latest/download/Jiva.dmg)** &nbsp;·&nbsp; Apple silicon · macOS 26+ · ~240 MB

## Install

Recommended — one command in Terminal (downloads, verifies, installs to ~/Applications, and opens Jiva):

```
curl -fsSL https://jiva.works/install.sh | bash
```

Prefer to do it by hand? Download and drag **Jiva** to Applications, then unlock it once (it's notarization-pending, so macOS blocks the first open):

```
xattr -dr com.apple.quarantine /Applications/Jiva.app
```

Either way, on first open a setup window walks you through permissions and the model download. Homebrew users: `brew install --cask venugopalarjun/jiva/jiva`.

## What it does

- **Live transcription** of both sides of a call, on-device
- **Speaker labels** — knows who said what
- **Glass overlay** with a live summary over any app
- **Hold-to-talk dictation** — speak anywhere, it types
- **Auto-record** when a meeting starts

## Privacy

Everything runs locally on your Mac. Your audio, transcripts, and summaries are never uploaded anywhere.
