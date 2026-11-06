# Releasing Belfry

A Belfry release is a GitHub release with the same tag in four repositories, created in this order:

1. [belfry-ee](https://github.com/belfry-project/belfry-ee): the execution environment image
2. [belfry](https://github.com/belfry-project/belfry): the application image, the `awx.awx` collection and awxkit
3. [belfry-operator](https://github.com/belfry-project/belfry-operator): the operator image and its install manifest
4. [helm-charts](https://github.com/belfry-project/helm-charts): the Helm chart

The operator deploys `belfry:<its version>` and `belfry-ee:<its version>` by default, so the images it needs must exist before it is released, and the chart installs the operator image of its version.

Publishing a release runs `.github/workflows/release.yml` in that repository. [`tools/release.sh`](tools/release.sh) creates the releases in order, waits for each workflow and verifies the result.

## Versions and tags

- Tags are **`X.Y.Z`** for final releases and **`X.Y.Z-rc.N`** for release candidates, **without a `v` prefix** (see [DECISIONS.md](DECISIONS.md)). The workflows refuse other tags.
- A release candidate is a GitHub **pre-release**; a final release is not (the workflows check this). Release candidates never get `:latest` and do not become the "latest" GitHub release.
- Image tags: `:X.Y.Z` or `:X.Y.Z-rc.N`; final releases also move `:latest`. `:latest` is the newest final release, `:main` the newest build of `main`.
- Python packages use the PEP 440 form of the version: `1.0.0-rc.1` becomes `1.0.0rc1` (awxkit file names and the version the belfry API reports). The collection keeps `1.0.0-rc.1`.
- The chart version and `appVersion` are the release version. On `main`, `helm-charts/.helm/starter/Chart.yaml` stays at version `0.1.0` and appVersion `main`; the release workflow sets both from the tag, so nothing is committed for a release.

## What each release workflow does

All image builds run natively on `ubuntu-latest` (amd64) and `ubuntu-24.04-arm` (arm64), push `<tag>-amd64` and `<tag>-arm64`, and then call the shared workflow [`release-image.yml`](.github/workflows/release-image.yml), which merges them into one multi-arch image, checks both architectures, attests build provenance and an SPDX SBOM, scans the image with Trivy, attaches `<image>-<version>.spdx.json`, `<image>-<version>-trivy.json` and `-trivy.md` to the release and adds an image section with the scan summary to the release notes.

| Repository | Builds and checks | Release assets |
| --- | --- | --- |
| belfry-ee | EE image, labelled with the version | SBOM, Trivy scan |
| belfry | Image built with `SETUPTOOLS_SCM_PRETEND_VERSION=<PEP 440 version>`; checks that `awx.__version__` in the image is exactly that version. Builds the collection with namespace `awx` and awxkit | SBOM, Trivy scan, `awx-awx-<version>.tar.gz`, `awxkit-<pep440>.tar.gz`, `awxkit-<pep440>-py3-none-any.whl`, `SHA256SUMS` (the packages have provenance attestations) |
| belfry-operator | Checks that `belfry:<version>` and `belfry-ee:<version>` exist; image built with `DEFAULT_AWX_VERSION` and `OPERATOR_VERSION` = version and checked; runs molecule (kind) and the AWX 24.6.1 upgrade test against the release images | SBOM, Trivy scan, `belfry-operator.yaml` (CRDs, RBAC and the operator in namespace `awx`, image pinned), `belfry-operator.yaml.sha256` |
| helm-charts | Checks that `belfry-operator:<version>` exists; generates the chart from belfry-operator at the tag, lints and installs it into kind | `belfry-operator-<version>.tgz`, added to the Helm repository index on `gh-pages` with chart-releaser |

## Dry run

Every release workflow has a manual `dry_run` mode (the default for manual runs). It builds everything from the selected branch as for a release, but publishes only the throwaway tag `:release-test` and no release or release assets (the SBOM, scans, packages, manifest and chart are kept as workflow artifacts). The operator's dry run deploys `belfry:release-test` and `belfry-ee:release-test`, so run the repositories in order:

```bash
tools/release.sh --dry-run            # all four, in order, from main
# or one at a time:
gh workflow run release.yml -R belfry-project/belfry-ee --ref main -f version=1.0.0-rc.1 -f dry_run=true
```

Do a dry run before each release (it takes about an hour, mostly the belfry build and the operator tests).

## Procedure

Immutable releases must stay disabled in the four repositories: the workflows attach their assets after the release is published.

Prerequisites: `gh` logged in with permission to create releases in all four repositories, `curl` and `jq`; optionally `docker` (to check the version inside the images), `helm` and `yq`.

1. Check that `main` is green in all four repositories and that everything for the release is merged. The tag is created on the current `main` of each repository; `release.sh` shows the commits and failed checks before it asks to continue.
2. Run a dry run: `tools/release.sh --dry-run`.
3. Release:

   ```bash
   tools/release.sh 1.0.0-rc.1     # release candidate
   tools/release.sh 1.0.0          # final release
   ```

   For each repository in order it creates the release (`--generate-notes`, title `Belfry <version>`, pre-release for `-rc.N`), waits for its release workflow and verifies the result. GitHub sometimes does not start the workflow for a published release: if no run has appeared 5 minutes after the release was published, `release.sh` says so, starts it itself with `gh workflow run release.yml -R belfry-project/<repo> --ref main -f version=<version> -f dry_run=false` (which builds from the release tag) and watches that run instead. It does not start a second run: it also finds manual runs of the release (it reads their version and `dry_run` from the log of the run's first step), so a rerun with `--from` picks up the run it started earlier, and it cancels a late `release` run that is still waiting for the other one (the workflows share a concurrency group per release). With `--dry-run` it only prints that command. The checks:

   - the GitHub release exists, is published and is (not) a pre-release;
   - the image exists for linux/amd64 and linux/arm64 and is annotated with the version;
   - `gh attestation verify` succeeds for the build provenance and the SBOM, signed by the shared workflow for that repository and the release tag;
   - `:latest` is the release (final) or is not (release candidate);
   - the version inside the image (`awx.__version__`, the operator's `DEFAULT_AWX_VERSION`/`OPERATOR_VERSION`), if docker is available (the workflows check this too);
   - the release assets listed above;
   - the chart version is in `https://belfry-project.github.io/helm-charts/index.yaml` (and `helm show chart` works, if helm is available).

4. Review the release notes (generated from pull request labels, see `.github/release.yml` in each repository; the image section is added by the workflow) and edit them if needed.
5. Add an entry for the release to `changes.yml` in belfry-project.github.io if users need to know about something specific.

`tools/release.sh --verify <version>` repeats the checks for an existing release.

### 1.0.0-rc.1

```bash
tools/release.sh --dry-run
tools/release.sh 1.0.0-rc.1
```

Then test the release candidate: install it with the manifest or with Helm (`--devel --version 1.0.0-rc.1`), upgrade an AWX 24.6.1 test instance, and run some jobs. Fix problems on `main` and release `1.0.0-rc.2` and so on.

### 1.0.0

When the last release candidate is good and `main` has no changes since then other than fixes found in it:

```bash
tools/release.sh --dry-run
tools/release.sh 1.0.0
```

This tags `main` again (so `1.0.0` may contain fixes after the last release candidate), moves `:latest` of the three images to `1.0.0` and makes 1.0.0 the latest GitHub release and the default chart version.

## When something fails

- **A workflow fails:** `release.sh` stops and prints the run. If the failure is unrelated to the release (a flaky test, a registry timeout), rerun the failed jobs (`gh run rerun <id> -R belfry-project/<repo> --failed`) and then `tools/release.sh <version> --from <repo>`: earlier repositories are only verified, the existing release is not created again, and a finished run is not waited for again. A rerun overwrites the image tag and the release assets (`--clobber`) and replaces the image section of the release notes.
- **The release is wrong** (the code needs a fix): for a release candidate, fix `main` and release the next `-rc.N`. Do not move a published tag. If a release has to be withdrawn, mark it in its notes, and for a final release publish `X.Y.Z+1`. Deleting a release (`gh release delete <tag> -R <repo> --cleanup-tag`) does not delete its images; a package admin removes them in the package settings.
- **A workflow needs to run again for an existing release** (for example after fixing the workflow on `main`): `gh workflow run release.yml -R belfry-project/<repo> --ref main -f version=<tag> -f dry_run=false`. It builds from the release tag, not from `main`. Then `tools/release.sh <version> --from <repo>` watches that run (the newest run of the release) and continues.
- **GitHub did not start the release workflow:** `release.sh` starts it itself (see step 3). Do not start dry runs of a repository while it releases it: a manual run is matched by its version and `dry_run` input only once its first step has finished.

## Release outputs

For a version `V` (`1.0.0`, or `1.0.0-rc.1` for a release candidate; `P` is its PEP 440 form, `1.0.0rc1`):

- Images (linux/amd64 and linux/arm64):
  - `ghcr.io/belfry-project/belfry:V`
  - `ghcr.io/belfry-project/belfry-ee:V`
  - `ghcr.io/belfry-project/belfry-operator:V`
  - `:latest` of each: the newest final release; `:main`: the newest build of `main`
- Operator install manifest (namespace `awx`):
  `kubectl apply --server-side -f https://github.com/belfry-project/belfry-operator/releases/download/V/belfry-operator.yaml`
  (newest final release: `https://github.com/belfry-project/belfry-operator/releases/latest/download/belfry-operator.yaml`)
- Helm: `helm repo add belfry https://belfry-project.github.io/helm-charts/`, chart `belfry/belfry-operator`, version `V`
  (`helm install belfry-operator belfry/belfry-operator -n awx --create-namespace --version V`; release candidates need `--devel` in `helm search`)
- Collection: `ansible-galaxy collection install https://github.com/belfry-project/belfry/releases/download/V/awx-awx-V.tar.gz`
- awxkit: `pip install https://github.com/belfry-project/belfry/releases/download/V/awxkit-P-py3-none-any.whl`
- Verify an image:
  `gh attestation verify oci://ghcr.io/belfry-project/belfry:V --repo belfry-project/belfry --signer-repo belfry-project/.github --source-ref refs/tags/V`
  (add `--predicate-type https://spdx.dev/Document/v2.3` for the SBOM; for the others use `--repo belfry-project/belfry-ee` or `belfry-project/belfry-operator`)
- Verify a package: `gh attestation verify awx-awx-V.tar.gz --repo belfry-project/belfry`
