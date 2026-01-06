# Bitbucket Cloud to Gitea Git Migration (SSH)

This script migrates Git repositories from Bitbucket Cloud to Gitea using Git over SSH only. It clones each repo with `git clone --mirror` and pushes to Gitea with `git push --mirror`. The process is resumable and will auto-create missing repositories in Gitea.

## What it does

- Git-only migration (no Bitbucket API usage)
- SSH-based clone and push
- Auto-creates repos in Gitea when missing
- Skips repos already completed
- Resumes after failure using state files
- Prints progress and timing

## Requirements

- Bash (macOS default Bash 3.2 compatible)
- Git
- curl
- SSH access to Bitbucket and Gitea

## Configuration

Set required environment variables:

```bash
export BB_WORKSPACE="example-workspace"
export GITEA_OWNER="example-user"
export GITEA_TOKEN="example-token"
```

If any required variables are missing and the script is run in a terminal, it will prompt for them and explain where to get the values. In non-interactive shells, it will fail fast.

Optional environment variables (defaults shown):

```bash
export GITEA_URL="http://gitea.example.com:3000"
export GITEA_SSH_HOST="gitea.example.com"
export GITEA_SSH_PORT="222"
export GITEA_OWNER_TYPE="org"
```

If optional variables are not set, the script will prompt for them and you can press Enter to accept the defaults.

Defaults if not set:

- `GITEA_URL` = `http://localhost:3000`
- `GITEA_SSH_HOST` = `localhost`
- `GITEA_SSH_PORT` = `22`
- `GITEA_OWNER_TYPE` = `user`

## Directory layout

The script expects the following structure:

```
.
├── bb_to_gitea.sh
├── repos.txt
└── .bb-migrate-state/
    ├── done.txt
    └── fail.txt
```

- `repos.txt` must be next to `bb_to_gitea.sh`
- Migration state is stored in `.bb-migrate-state/` next to the script

## Usage

1. Put one repo slug per line in `repos.txt` (no URLs, just repo names).
2. Export the required environment variables.
3. Run:

```bash
./bb_to_gitea.sh
```

## Resume behavior

- Completed repos are tracked in `.bb-migrate-state/done.txt`
- Failed repos are recorded in `.bb-migrate-state/fail.txt`
- Re-running the script skips anything already in `done.txt`

## Limitations

This script only migrates Git data. It does not migrate:

- Issues
- Pull requests
- Wikis
- Permissions

## Author Notes

This script exists to handle real-world Bitbucket restrictions where API access is unavailable. It favors reliability, portability, and auditability over complexity.

## Author

- <img src="https://cdn.simpleicons.org/googlechrome/000000" alt="web" width="16" height="16"> Jon Munson - https://www.jonmunson.co.uk
- <img src="https://s.magecdn.com/social/tc-x.svg" alt="x" width="16" height="16"> @jonmunson - https://x.com/jonmunson
- <img src="https://s.magecdn.com/social/tc-linkedin.svg" alt="linkedin" width="16" height="16"> https://www.linkedin.com/in/jonmunson/
- <img src="https://cdn.simpleicons.org/buymeacoffee/FFDD00" alt="buy me a coffee" width="16" height="16"> https://buymeacoffee.com/jonmunson
