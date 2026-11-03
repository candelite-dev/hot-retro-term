# Working without losing track of branches

A commit is a saved snapshot. A branch is a name pointing to a series of snapshots.
Switching branches changes the files on disk. A stash is saved work outside the
normal branch history; switching branches does not apply it automatically.

## A small workflow

Use `master` for integrated work. Keep one short-lived branch per change. Build and
test it, commit it, open a PR, merge it, then remove that branch only after confirming
it has no unique work. A branch named `feature` is not a second permanent master.

Before starting:

```bash
git status --short --branch
git stash list
git log -8 --oneline --decorate
```

If the working tree is clean, update `master` with `git pull --ff-only`, then create
a clearly named branch, for example `git switch -c fix/startup`. `--ff-only` stops
rather than inventing a merge when histories have diverged. Resolve that situation
before carrying on; do not use `reset --hard` to make the warning disappear.

After editing:

```bash
./scripts/dev.sh test
git diff --check
git diff --stat
git add <the-files-for-this-change>
git diff --cached
git commit -m "fix: describe the behavior that now works"
git push -u origin HEAD
```

Use `git diff --cached` to check what you are actually saving. Do not include build
directories, IDE indexes, or unrelated settings work. For a refactor, keep behavior
changes and the tests that justify them reviewable together.

## What was found on this machine

This is the local snapshot inspected on 2026-11-03, before applying the cleanup.
Remote-tracking names are cached local refs; this table is not a fresh remote fetch.

| Branch/ref | Meaning in the inspected history |
|---|---|
| `config-screen` | Checked out at `c70ca85`, the same commit as cached `origin/master` |
| `master` and `fix/qmltermwidget-cmake-pointer` | Both at `c5f2828`, one commit beyond `config-screen`; that commit only changes the terminal submodule pin |
| `feature` | At `890d177`, two commits ahead of its cached tracking branch; inspect merge ancestry before deleting |
| `wayland-transparency` | At `a3b2f67`; merged into `c70ca85` |
| `windows-port` | Separate work: 35 commits unique to it and 7 unique to `config-screen`; keep it until the Windows work has been reconciled |
| `stash@{0}` | `WIP: Milestone 1 SettingsStore`; includes settings-store sources, TOML library, docs, and tooling files |

The stash is preserved. Inspect it with `git stash show --stat --include-untracked`.
Restore it later on a dedicated settings branch using `git stash apply`, not `pop`,
so a failed/conflicting application does not remove the saved copy. Its CMake/QML
changes will need reviewing against this cleanup.

The cleanup does not merge the Windows port or delete old branches. Its POSIX
terminal engine is for macOS/Linux; Windows is a separate integration task.

## Dependencies and branches

Only KDSingleApplication remains a submodule. Use `git submodule update --init
--recursive` after a new clone. Do not use `git submodule update --remote` as a
routine build step: that changes the version you are building.

The terminal engine's files now travel with the app branch. Edits under
`qmltermwidget/` belong in the main repository's commit, just like edits under `app/`.
The original nested repository metadata is retained under the parent repository's
`.git/modules/` for recovery when the migration is applied.
