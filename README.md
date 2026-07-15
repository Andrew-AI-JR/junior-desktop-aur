# junior-desktop (AUR)

Arch Linux packaging for [Junior Desktop](https://github.com/Andrew-AI-JR/Desktop-Releases).

- AUR package: https://aur.archlinux.org/packages/junior-desktop
- Upstream releases: https://github.com/Andrew-AI-JR/Desktop-Releases/releases

## Install

```bash
yay -S junior-desktop
# or
paru -S junior-desktop
```

## Manual build

```bash
makepkg -si
```

## Automation

`sync-aur.yml` keeps this mirror and the AUR package aligned with the latest
`Desktop-Releases` publish:

- `repository_dispatch` from `Desktop-Releases` on release publish
- hourly schedule as a fallback
- manual `workflow_dispatch`

Each run updates the GitHub mirror when needed, then syncs to AUR over SSH
(only committing when `PKGBUILD` / `.SRCINFO` differ).

### Required GitHub secrets (`junior-desktop-aur`)

| Secret | Description |
| --- | --- |
| `AUR_USERNAME` | AUR account username (`heyeddi`) |
| `AUR_EMAIL` | Email used for AUR commits |
| `AUR_SSH_PRIVATE_KEY` | Private SSH key registered on https://aur.archlinux.org/account/ |

### Required GitHub secret (`Desktop-Releases`)

| Secret | Description |
| --- | --- |
| `AUR_SYNC_TOKEN` | Fine-grained PAT with `Contents: Read` on this repo and `Actions: Write` on `Andrew-AI-JR/junior-desktop-aur` |
