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

Optional environment variables (defaults shown):

```bash
export GITEA_URL="http://gitea.example.com:3000"
export GITEA_SSH_HOST="gitea.example.com"
export GITEA_SSH_PORT="222"
export GITEA_OWNER_TYPE="org"
```

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

