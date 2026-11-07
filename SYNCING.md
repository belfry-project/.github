# Syncing with upstream

Belfry's repositories are standalone copies of their upstream projects, with the full history. Upstream changes are brought in by **merging** the upstream branch into `main` (never by rebasing or cherry-picking), so every upstream commit keeps its SHA and `git log` shows exactly what came from upstream and when.

| Belfry repository | Upstream | Upstream branch | Notes |
| --- | --- | --- | --- |
| [belfry](https://github.com/belfry-project/belfry) | [ansible/awx](https://github.com/ansible/awx) | `devel` | Also watches the `django-ansible-base` commit pinned in `requirements/requirements_git.txt` |
| [belfry-operator](https://github.com/belfry-project/belfry-operator) | [ansible/awx-operator](https://github.com/ansible/awx-operator) | `devel` | |
| [belfry-ee](https://github.com/belfry-project/belfry-ee) | [ansible/awx-ee](https://github.com/ansible/awx-ee) | `devel` | |
| [belfry-ui](https://github.com/belfry-project/belfry-ui) | [ansible/ansible-ui](https://github.com/ansible/ansible-ui) | `main` | Upstream `main` (the AWX UI) is frozen since 2024-09. Upstream development continues on `devel`, which is the AAP platform UI with an unrelated history; it is not merged |
| [helm-charts](https://github.com/belfry-project/helm-charts) | [ansible-community/awx-operator-helm](https://github.com/ansible-community/awx-operator-helm) | `main` | |

## The weekly check

Each of these repositories runs `.github/workflows/upstream-check.yml` every Monday (and on demand from the Actions tab). It calls the shared workflow [`upstream-check.yml`](.github/workflows/upstream-check.yml), which compares `main` with the upstream branch and keeps one issue labelled **`upstream-sync`** in that repository up to date: it lists the upstream commits that are not merged yet, opens the issue when there are some, comments when the list changes and closes the issue once everything is merged.

The check only reads upstream. It never merges, pushes or opens anything outside the Belfry repository; merging is always done by hand, as below.

## Merging upstream by hand

Once per clone, add the upstream remote **without tags and with pushing disabled**. Upstream's version tags would clash with Belfry's (see [DECISIONS.md](DECISIONS.md), "Upstream version tags are prefixed"), and Belfry never pushes to upstream:

```bash
git clone https://github.com/belfry-project/belfry.git && cd belfry
git remote add upstream https://github.com/ansible/awx.git
git config remote.upstream.tagOpt --no-tags
git remote set-url --push upstream DISABLED
```

Then, for each sync (example for belfry, `devel`; use the branch from the table):

```bash
git fetch origin
git fetch --no-tags upstream devel

# What is new upstream
base=$(git merge-base origin/main upstream/devel)
git log --oneline "$base"..upstream/devel
git diff --stat "$base" upstream/devel

# Merge it on a branch
git switch -c sync/upstream-$(date +%Y-%m-%d) origin/main
git merge --no-ff upstream/devel
# resolve conflicts (see below), then
git add <files> && git commit       # or: git merge --continue
```

Write a merge commit message that lists what came in, for example:

```text
Merge upstream ansible/awx devel (2026-11-07)

Brings in the 2 commits upstream added since a498310675:

- 85ad07ed6 fix: bump urllib3 to 2.8.0 (#16775)
- fe6cd9d45 Fix EDITABLE_DEPENDENCIES=true make docker-compose (#16767)

Conflicts: none.
```

Push the branch and open a pull request against `main`:

```bash
git push -u origin sync/upstream-$(date +%Y-%m-%d)
gh pr create -R belfry-project/belfry --base main --label dependencies \
  --title "Merge upstream ansible/awx devel ($(date +%Y-%m-%d))" --body-file pr.md
```

The pull request description lists the upstream commits (notable fixes and security changes first) and, for each conflict, which side was kept and why. Write upstream issue and pull request numbers as code (`` `#16775` ``) or as plain text, not as `ansible/awx#16775` or links: those would add "mentioned this" references to the upstream pull requests.

**Merge the pull request with a merge commit** (`gh pr merge <n> -R belfry-project/<repo> --merge --delete-branch`), not with rebase or squash, which would rewrite the upstream commits. Never force-push.

### Resolving conflicts

Belfry's decisions win; upstream fixes are kept wherever they do not contradict them. Check [DECISIONS.md](DECISIONS.md) when in doubt. Typical cases:

- **Removed upstream files** (upstream-only workflows, issue labelers, Dependabot configuration): keep them deleted (`git rm <file>`).
- **Rebrand** (name "Belfry", no AWX logo, Belfry links): keep Belfry's text; take upstream's other changes to the same file.
- **Images and runtimes** (AlmaLinux 10, Python 3.14, PostgreSQL 18, Redis 8, image names under `ghcr.io/belfry-project`): keep Belfry's.
- **Dependency pins** (`requirements/*.txt`, `package-lock.json`, `requirements.yml`, `_build/requirements.txt`): keep the newer version of each package. If upstream adds or changes a requirement, regenerate the lock file the way the repository documents (in belfry: `requirements/README.md`) instead of editing the conflict by hand.
- **Workflows**: Belfry's CI and release workflows are its own. Keep Belfry's version and apply an upstream change only when it fixes something Belfry also does.

Let CI run on the pull request: in belfry the full `ci.yml`, in belfry-operator molecule and the upgrade test.

### After merging

1. Update the upstream base in [`build.py`](https://github.com/belfry-project/belfry-project.github.io/blob/main/build.py) of the website (`BELFRY_UPSTREAM_BASE` for belfry, `BELFRY_REPOS` for the others) to the upstream commit that was merged (`git rev-parse --short=10 upstream/devel`). The comparison page counts upstream commits up to that base and Belfry commits after it.
2. If the sync changes something users notice, add an entry to [`changes.yml`](https://github.com/belfry-project/belfry-project.github.io/blob/main/changes.yml).
3. The next weekly check closes the `upstream-sync` issue (or run the check by hand: `gh workflow run upstream-check.yml -R belfry-project/<repo>`).

## Pinned dependencies

`django-ansible-base` is developed for Red Hat's Ansible Automation Platform, and its interfaces can change without notice. belfry pins it by commit in `requirements/requirements_git.txt`, and the weekly check lists its new `devel` commits in the same issue. Before bumping the pin, read those commits for changes to settings, RBAC, the resource registry and the plugin interfaces that Belfry uses.
