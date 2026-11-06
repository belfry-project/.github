# Contributing to Belfry

Thank you for helping. Belfry is a community continuation of AWX, maintained by volunteers; every bug report, migration report, docs fix and pull request helps.

The [contributing guide](https://belfry-project.github.io/docs/contributing/) on the website has the repositories, the development environment and what CI runs. This page is the short version that applies to every repository in [belfry-project](https://github.com/belfry-project). A repository can have its own `CONTRIBUTING.md` with more detail.

## Issues

- Open bugs and feature requests in the repository of the component. If you are not sure which, use [belfry](https://github.com/belfry-project/belfry/issues).
- Include the Belfry version (`/api/v2/ping/`), the operator version, your Kubernetes distribution and the relevant logs.
- Migration reports from AWX are welcome, also when everything worked: open an issue in [belfry-operator](https://github.com/belfry-project/belfry-operator/issues).
- **Never report a vulnerability in a public issue.** See [SECURITY.md](SECURITY.md).

## Pull requests

- Branch from `main` and open the pull request against `main` (Belfry has no `devel` branch). For a large change, open an issue first to agree on the approach.
- Fill in the pull request template. belfry and belfry-operator have their own, with `##### SUMMARY` and `##### ISSUE TYPE` headings; belfry-operator's CI checks that the issue type is exactly one of the listed lines.
- Reference the issue: `Fixes #123` or `Part of #123`.
- **Keep diffs small and focused.** Belfry stays close to upstream AWX so that upstream changes can still be merged; avoid reformatting, renaming or moving code you do not need to change.
- Pull requests are usually merged with rebase, so keep the commits clean (squash fixups yourself).
- For changes users should know about, also add an entry to [`changes.yml`](https://github.com/belfry-project/belfry-project.github.io/blob/main/changes.yml), which feeds the [comparison page](https://belfry-project.github.io/).

## Commits

- Subject: imperative, at most about 72 characters (`Fix the job event cleanup for empty partitions`).
- Body: what changes and why, for a reader who does not know the context.
- No Developer Certificate of Origin sign-off is required (some files inherited from upstream mention one; Belfry does not enforce it).

## CI

All checks run on GitHub Actions and must pass before a pull request is merged. Run the fast checks locally first; in belfry that is `ruff check` and `ruff format --check` (configured in `pyproject.toml`). The [website](https://belfry-project.github.io/docs/contributing/#ci) lists what runs in each repository.

## Upstream projects

Belfry is based on [ansible/awx](https://github.com/ansible/awx), [ansible/awx-operator](https://github.com/ansible/awx-operator), [ansible/awx-ee](https://github.com/ansible/awx-ee), [ansible/ansible-ui](https://github.com/ansible/ansible-ui) and [ansible-community/awx-operator-helm](https://github.com/ansible-community/awx-operator-helm). Belfry does not open issues or pull requests in those projects on its own behalf; if you want a fix upstream too, contribute it there yourself, under their rules.

## Code of conduct

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
