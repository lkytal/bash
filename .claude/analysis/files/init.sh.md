# File: init.sh
Generated: 2026-02-27
Language: Bash (Shell Script)
Lines: 18

## Purpose
A Linux environment initialization script that sets up a development-friendly shell environment. It installs essential packages, configures Zsh with Antigen plugin manager, installs directory navigation tools (autojump, fzf, zoxide), and switches the default shell to Zsh.

## Exports / Public API
N/A — This is an executable setup script, not a library.

## Key Steps
### 1. System Update & Package Installation
- Runs `apt update` and installs a comprehensive set of packages:
  - **Locale/i18n:** `language-pack-zh-hans`, `language-pack-zh-hans-base` (Chinese language support)
  - **Network:** `avahi-daemon`, `libnss-mdns`, `mdns-scan` (mDNS/Bonjour discovery)
  - **Dev tools:** `git`, `vim`, `wget`, `curl`, `python3`, `python-is-python3`
  - **Shell:** `zsh`
- Sets system locale to `en_US.UTF-8`

### 2. Zsh Configuration
- Downloads Antigen (Zsh plugin manager) from `git.io/antigen`
- Downloads `.zshrc` from the same GitHub repo (`lkytal/bash`) as the base Zsh config

### 3. Directory Navigation Tools
- **autojump:** Cloned from GitHub and installed via `install.py`
- **fzf:** Installed via `apt`
- **zoxide:** Installed via official install script

### 4. Shell Switch
- Changes the current user's default shell to `/usr/bin/zsh` using `chsh`

## Dependencies
### Internal
- `.zshrc`: Downloaded from `https://raw.githubusercontent.com/lkytal/bash/main/.zshrc` — the Zsh configuration file that pairs with this setup

### External
- **apt** (Debian/Ubuntu package manager): used for all system package installations
- **antigen** (Zsh plugin manager): downloaded from `git.io/antigen`
- **autojump** (https://github.com/wting/autojump): directory navigation tool
- **zoxide** (https://github.com/ajeetdsouza/zoxide): smarter cd command
- **fzf**: fuzzy finder

## Patterns
- Linear imperative setup script — no functions, no error handling, runs top-to-bottom
- Uses `sudo` for privileged operations, assumes Debian/Ubuntu environment
- Downloads remote resources directly (curl/wget) without checksum verification

## Notes
- **Requires sudo privileges** — will fail without root access
- **Debian/Ubuntu specific** — uses `apt` and assumes `/usr/bin/zsh` path
- **No error handling** — if any step fails, subsequent steps may also fail or produce unexpected results
- **No idempotency** — running multiple times will re-clone autojump and re-download files
- The script starts with `cd ~`, so all relative operations happen in the user's home directory
- The `git.io/antigen` short URL and remote `.zshrc` download mean the script depends on external network availability
