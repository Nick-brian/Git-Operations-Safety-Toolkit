# Git Operations Safety Toolkit

A collection of interactive Bash utilities for safer Git and GitHub operations.

This project grew out of practical troubleshooting involving GitHub SSH authentication and the recovery of a remote branch after an unwanted change.

The goal is to make potentially risky Git operations more deliberate, understandable, and verifiable.

> **Project status: Experimental**
>
> These scripts are initial implementations. They have not yet undergone comprehensive automated testing or broad environment compatibility testing. Review the code and test in a disposable repository before using them on important projects.

## Tools

### 1. Git Recovery Script

`scripts/git-recovery.sh`

An interactive utility designed to help restore a remote Git branch from another remote branch while preserving the previous target-branch state.

The script guides the user through:

- Checking whether the current directory is a Git repository.
- Selecting the remote, target branch, and source branch.
- Checking the remote GitHub SSH connection.
- Fetching remote references.
- Identifying the current source and target commit hashes.
- Creating and verifying a recovery branch for the existing target.
- Requiring an explicit confirmation before restoration.
- Restoring the target branch using `git push --force-with-lease`.
- Verifying the resulting remote branch references.

**Important:** This operation changes a remote branch reference. It does not restore or clean the local working directory.

### 2. GitHub SSH Setup Script

`scripts/github-ssh-setup.sh`

An interactive utility that helps configure SSH authentication for GitHub.

It guides the user through:

- Checking for required tools.
- Detecting an existing Ed25519 SSH key.
- Generating a key when needed.
- Checking the SSH agent and attempting to load the key.
- Displaying the public key for manual addition to GitHub.
- Testing GitHub SSH authentication.
- Optionally configuring Git to translate GitHub HTTPS URLs into SSH URLs.
- Displaying the configured Git remotes.

The script does not upload private keys or ask for GitHub passwords or personal access tokens.

## Requirements

- Linux environment with Bash.
- Git.
- OpenSSH client.
- Network access to GitHub.
- A GitHub account.
- Permission to push to the repository when performing remote recovery.

The scripts are intended for Linux environments. Compatibility with other operating systems and distributions still needs to be tested.

## Getting started

Clone the repository:

```bash
git clone https://github.com/Nick-brian/git-operations-safety-toolkit.git
cd git-operations-safety-toolkit
```

Make the scripts executable:

```bash
chmod +x scripts/*.sh
```

### Configure GitHub SSH authentication

Run:

```bash
./scripts/github-ssh-setup.sh
```

Follow the prompts. When asked to add your public key to GitHub, do so through your GitHub account settings.

### Recover a remote branch

Run:

```bash
./scripts/git-recovery.sh
```

Run this from the local Git repository you intend to work with.

Read every prompt carefully. Confirm that the remote, target branch, source branch, and recovery point are correct before authorizing the operation.

## Safety considerations

Branch recovery can overwrite the remote target branch's current history.

Before using the recovery script:

1. Confirm that you are working with the correct repository.
2. Identify the intended source and target branches.
3. Check whether other contributors have pushed changes.
4. Preserve important work and verify the recovery point.
5. Understand what `--force-with-lease` does before confirming.
6. Test the procedure in a disposable repository first.

`--force-with-lease` provides protection against overwriting an unexpected remote update, but it does not make every recovery operation risk-free.

The SSH setup script's optional URL rewrite is a global Git configuration change. It can affect GitHub remotes across repositories for your user account, not just the repository where the script is run.

Never share or commit private SSH keys, access tokens, passwords, `.env` files, or other credentials.

## Project structure

```text
git-operations-safety-toolkit/
├── scripts/
│   ├── git-recovery.sh
│   └── github-ssh-setup.sh
├── tests/
├── docs/
├── README.md
├── LICENSE
├── SECURITY.md
├── CHANGELOG.md
└── .gitignore
```

The `tests/` and `docs/` directories will be populated as the project develops.

## Development roadmap

- [x] Initial Git recovery script.
- [x] Initial GitHub SSH setup script.
- [x] Interactive prompts and safety confirmations.
- [ ] Disposable-repository testing.
- [ ] Automated test coverage.
- [ ] Improved input and remote-host validation.
- [ ] Additional failure-handling and verification.
- [ ] Documented compatibility testing.
- [ ] First stable release.

## Contributions

Issues, suggestions, and improvements are welcome.

If you identify a failure case, security concern, or compatibility problem, please describe the environment and steps needed to reproduce it.

## License

MIT License — see [LICENSE](LICENSE).

---

**Maintainer:** [Nick Brian](https://github.com/Nick-brian)

**Focus areas:** Git, GitHub, Bash automation, operational safety, and DevSecOps.
