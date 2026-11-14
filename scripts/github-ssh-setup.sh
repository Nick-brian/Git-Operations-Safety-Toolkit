#!/usr/bin/env bash
#
# GitHub SSH Setup Assistant
# Safely prepares a default Ed25519 SSH key for GitHub and optionally
# configures Git to use SSH for GitHub HTTPS URLs.
#
# This script does not:
#   - ask for or store your GitHub password or personal access token
#   - upload your key to GitHub
#   - overwrite an existing private key
#   - change repository files, branches, commits, or history
#
set -Eeuo pipefail

readonly GITHUB_HOST="github.com"
readonly SSH_DIR="${HOME}/.ssh"
readonly KEY_FILE="${SSH_DIR}/id_ed25519"
readonly PUB_FILE="${KEY_FILE}.pub"

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
line()  { printf '%s\n' "------------------------------------------------------------"; }

pause_for_enter() {
    printf '\nPress Enter to continue...'
    read -r _
}

ask_yes_no() {
    local prompt="$1" answer
    while true; do
        read -r -p "${prompt} [y/N]: " answer
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) printf 'Please answer y or n.\n' ;;
        esac
    done
}

fail() {
    red "ERROR: $*"
    exit 1
}

bold "GitHub SSH Setup Assistant"
printf 'This assistant prepares SSH authentication for GitHub.com.\n'
printf 'It will explain each change and ask before making optional changes.\n'
line

# Basic environment checks
[[ -n "${HOME:-}" ]] || fail 'HOME is not set.'
command -v git >/dev/null 2>&1 || fail 'Git is not installed or is not in PATH.'
command -v ssh >/dev/null 2>&1 || fail 'OpenSSH client (ssh) is not installed.'
command -v ssh-keygen >/dev/null 2>&1 || fail 'ssh-keygen is not installed.'

printf 'Detected system: '
uname -s
printf 'Home directory: %s\n' "$HOME"
printf 'Git version: '
git --version

# Create the SSH directory with private permissions if necessary.
if [[ ! -d "$SSH_DIR" ]]; then
    if ask_yes_no "Create ${SSH_DIR} with secure permissions (700)?"; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        green "Created ${SSH_DIR}."
    else
        fail 'The SSH directory is required to continue.'
    fi
else
    chmod 700 "$SSH_DIR"
    green "SSH directory exists; permissions set to 700."
fi

line
bold "Step 1 — Check for an existing Ed25519 key"

if [[ -f "$KEY_FILE" ]]; then
    green "Found an existing private key: $KEY_FILE"
    if [[ -f "$PUB_FILE" ]]; then
        green "Found its public key: $PUB_FILE"
        chmod 600 "$KEY_FILE"
        chmod 644 "$PUB_FILE"
        printf 'The existing key will be kept. It will not be overwritten.\n'
    else
        yellow "The private key exists, but its .pub public-key file is missing."
        if ask_yes_no "Derive the public key from the existing private key?"; then
            # ssh-keygen may ask for the private key's passphrase.
            temp_pub="$(mktemp "${SSH_DIR}/id_ed25519.pub.XXXXXX")"
            if ssh-keygen -y -f "$KEY_FILE" > "$temp_pub"; then
                mv "$temp_pub" "$PUB_FILE"
                chmod 644 "$PUB_FILE"
                chmod 600 "$KEY_FILE"
                green "Public key recreated at $PUB_FILE."
            else
                rm -f "$temp_pub"
                fail 'Could not derive the public key. Your private key was not changed.'
            fi
        else
            fail 'A matching public key is needed to continue. No key was changed.'
        fi
    fi
elif [[ -f "$PUB_FILE" ]]; then
    red "Found $PUB_FILE but no matching private key at $KEY_FILE."
    red 'A public key alone cannot authenticate you. The script will not overwrite or delete either file.'
    fail 'Move or rename the orphaned public key yourself after checking what it belongs to, then run this assistant again.'
else
    yellow 'No default Ed25519 key was found.'
    printf 'Ed25519 is a modern SSH key type supported by GitHub.\n'
    printf 'The key will be created locally. Its private half stays on this computer.\n'
    if ask_yes_no "Generate a new key at $KEY_FILE?"; then
        comment="$(git config --global user.email 2>/dev/null || true)"
        if [[ -n "$comment" ]]; then
            read -r -p "Key comment/email [${comment}]: " entered_comment
            comment="${entered_comment:-$comment}"
        else
            read -r -p 'Optional key comment (often your GitHub email): ' comment
            comment="${comment:-github-ssh-key}"
        fi
        printf '\nYou may be asked to create a passphrase. A passphrase protects the key if the file is copied.\n'
        ssh-keygen -t ed25519 -C "$comment" -f "$KEY_FILE"
        [[ -s "$KEY_FILE" && -s "$PUB_FILE" ]] || fail 'Key generation did not produce both key files.'
        chmod 600 "$KEY_FILE"
        chmod 644 "$PUB_FILE"
        green "New Ed25519 key created."
    else
        fail 'No SSH key is available. Nothing was changed.'
    fi
fi

line
bold "Step 2 — Check whether an SSH agent is available"

if [[ -n "${SSH_AUTH_SOCK:-}" ]] && command -v ssh-add >/dev/null 2>&1; then
    if ssh-add -l >/dev/null 2>&1; then
        green 'An SSH agent is running and has at least one identity loaded.'
    else
        yellow 'An SSH agent is available, but it has no identities loaded (or its identity list is inaccessible).'
        if ask_yes_no "Add $KEY_FILE to the current SSH agent?"; then
            ssh-add "$KEY_FILE"
            green 'Key added to the current SSH agent.'
        else
            yellow 'Skipped adding the key. SSH may ask for its passphrase when connecting.'
        fi
    fi
else
    yellow 'No usable SSH agent was detected in this process.'
    printf 'That is not necessarily an error: SSH can read the default key file directly.\n'
    printf 'If your key has a passphrase and you want agent-based caching, run this in your terminal:\n'
    printf '  eval "$(ssh-agent -s)"\n'
    printf '  ssh-add %q\n' "$KEY_FILE"
    printf 'Those commands affect the terminal in which you run them; a child script cannot export its agent variables back to your shell.\n'
fi

line
bold "Step 3 — Add the public key to your GitHub account"

printf 'Your public key is below. It is safe to share with GitHub; never share the private key.\n\n'
cat "$PUB_FILE"
printf '\n'
printf 'Open GitHub → Settings → SSH and GPG keys → New SSH key.\n'
printf 'Choose an authentication key, give it a recognizable title, and paste the public key above.\n'
printf 'Official page: https://github.com/settings/ssh/new\n\n'

if command -v wl-copy >/dev/null 2>&1; then
    if ask_yes_no 'Copy the public key to the Wayland clipboard with wl-copy?'; then
        wl-copy < "$PUB_FILE"
        green 'Public key copied to clipboard.'
    fi
elif command -v xclip >/dev/null 2>&1; then
    if ask_yes_no 'Copy the public key to the X11 clipboard with xclip?'; then
        xclip -selection clipboard < "$PUB_FILE"
        green 'Public key copied to clipboard.'
    fi
elif command -v pbcopy >/dev/null 2>&1; then
    if ask_yes_no 'Copy the public key to the clipboard with pbcopy?'; then
        pbcopy < "$PUB_FILE"
        green 'Public key copied to clipboard.'
    fi
else
    yellow 'No supported clipboard utility was detected; copy the displayed public key manually.'
fi

printf '\nAfter adding the key on GitHub, return here and continue.\n'
pause_for_enter

line
bold "Step 4 — Test SSH authentication"

printf 'The next command contacts GitHub and checks whether your key is accepted:\n'
printf '  ssh -T git@github.com\n\n'
printf 'On the first connection, SSH may ask you to verify GitHub host authenticity.\n'
printf 'Do not accept an unexpected host key. Compare its fingerprint with GitHub'\''s official documentation first:\n'
printf '  https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints\n\n'
ssh_status=0
ssh -T -o ConnectTimeout=10 "git@${GITHUB_HOST}" || ssh_status=$?

# GitHub normally returns status 1 even after successful public-key authentication,
# because it does not provide interactive shell access. The visible message is decisive.
printf '\n'
if ask_yes_no 'Did the output say "successfully authenticated" and show your GitHub username?'; then
    green 'SSH authentication is confirmed.'
else
    yellow 'SSH authentication is not confirmed yet.'
    printf 'Common causes: the public key has not been added to GitHub, the wrong account/key was used,\n'
    printf 'network access to port 22 is blocked, or SSH is offering a different key.\n'
    printf 'You can inspect key selection with: ssh -vT git@github.com\n'
    printf 'Do not share private-key contents or unredacted debug logs publicly.\n'
fi

line
bold "Step 5 — Optional: make Git use SSH for GitHub HTTPS URLs"

printf 'Git can rewrite GitHub URLs that start with https://github.com/ to SSH URLs.\n'
printf 'This is a global Git setting: it applies to GitHub HTTPS URLs across your repositories,\n'
printf 'not just the repository you are currently in. It does not affect other hosting providers.\n\n'

rewrite_key='url.git@github.com:.insteadof'
existing_rewrites="$(git config --global --get-all "$rewrite_key" 2>/dev/null || true)"
if printf '%s\n' "$existing_rewrites" | grep -Fxq 'https://github.com/'; then
    green 'The global HTTPS-to-SSH rewrite is already configured.'
else
    printf 'Current matching rewrite values:\n'
    if [[ -n "$existing_rewrites" ]]; then
        printf '%s\n' "$existing_rewrites"
    else
        printf '(none)\n'
    fi
    if ask_yes_no 'Add the global GitHub HTTPS-to-SSH rewrite?'; then
        git config --global --add "$rewrite_key" 'https://github.com/'
        green 'Global rewrite added.'
    else
        yellow 'Skipped the global rewrite. You can still use SSH by setting a repository remote to git@github.com:OWNER/REPO.git.'
    fi
fi

line
bold "Step 6 — Review configured Git remotes (read-only)"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Current repository: %s\n' "$(git rev-parse --show-toplevel)"
    printf 'Configured remotes:\n'
    git remote -v || true
else
    printf 'You are not currently inside a Git repository; that is fine.\n'
fi

line
bold "Finished"
printf 'Key files:\n'
printf '  Private key: %s  (keep secret; never upload or share)\n' "$KEY_FILE"
printf '  Public key:  %s  (add this one to GitHub)\n' "$PUB_FILE"
printf '\nTo verify later, run: ssh -T git@github.com\n'
printf 'To inspect the global rewrite later, run:\n'
printf '  git config --global --get-all %q\n' "$rewrite_key"
printf '\nNo repository files, branches, commits, or history were changed by this assistant.\n'
