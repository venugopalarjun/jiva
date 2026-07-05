# Repo policy — this is a PUBLIC distribution repo

This GitHub repo (`jiva`) is **public**. It exists for exactly two things:

1. **The website** — the landing page served via GitHub Pages (`index.html`, plus `README.md`).
2. **The download** — the latest `Jiva.dmg`, attached to the newest GitHub **Release** (never committed to the repo tree).

**Nothing else belongs here.** In particular, do **not** commit:

- Source code, build scripts, or the `app/` project
- Transcripts, dictations, logs, notes, or any recorded data
- Tokens, keys, certificates, or `.env` files
- Internal docs (STATUS, ROADMAP, DECISIONS, specs, etc.)

All publishing goes through `publish.sh`, which only pushes the whitelisted
website files and (re)uploads `Jiva.dmg` to Releases. A `.gitignore` whitelist
is committed here as a second line of defense — it ignores everything except the
approved public files, so a stray private file can't be committed by accident.

## Releasing a new version

From the project root on your Mac:

```
bash app/make-app.sh          # build Jiva.app
bash app/package-dmg.sh       # -> ~/Desktop/Jiva-<version>.dmg
bash website/publish.sh       # push site + upload newest DMG as Jiva.dmg
```

The download link stays stable across versions:
`https://github.com/<owner>/jiva/releases/latest/download/Jiva.dmg`
