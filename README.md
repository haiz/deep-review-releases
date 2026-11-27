# Deep Review

A macOS app that reviews and upgrades a document over many rounds, alternating between Claude and ChatGPT.

This repo holds only the installer and the releases (the `DeepReview.app.zip` file under Releases).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/haiz/deep-review-releases/main/install.sh | bash
```

The installer checks the requirements, downloads the latest release, installs it into `/Applications/DeepReview.app`, then prints the command to open the app:

```bash
open /Applications/DeepReview.app
```

Run the same command again to update. If Deep Review is running, the installer asks before quitting it.

## Requirements

- macOS 15 or later (Apple Silicon or Intel).
- Node 22 or later. Install with `brew install node`, or use nvm, fnm or volta.
- Google Chrome in `/Applications` or `~/Applications`: https://www.google.com/chrome/
- claude-dashboard with at least one Claude account logged in (recommended): without it ChatGPT turns still run, but Claude turns fail.

## Notes

The app is only ad-hoc signed. The installer clears the quarantine attribute, but if macOS still blocks the first launch, go to System Settings > Privacy & Security > Open Anyway.
