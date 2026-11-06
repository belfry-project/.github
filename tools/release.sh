#!/usr/bin/env bash
# Release Belfry: create the GitHub releases of belfry-ee, belfry,
# belfry-operator and helm-charts in this order, wait for each release
# workflow, and verify what it published. See RELEASING.md.
#
#   tools/release.sh 1.0.0-rc.1          release candidate (pre-release, no :latest)
#   tools/release.sh 1.0.0               final release (also :latest)
#   tools/release.sh --dry-run           run every release workflow as a dry run
#                                        from main (publishes only :release-test)
#   tools/release.sh --verify 1.0.0      only verify an existing release
#
# Options:
#   --yes            do not ask for confirmation
#   --from <repo>    start at this repository (after fixing a failed step);
#                    earlier repositories are only verified
#
# Rerunning the script is safe: an existing release is not created again, a
# finished workflow run is not waited for again.
#
# Needs: gh (logged in, with access to create releases in belfry-project),
# curl, jq. Optional: docker (checks the version reported inside the images),
# helm (checks the chart through the Helm repository).

set -euo pipefail

ORG=belfry-project
REPOS=(belfry-ee belfry belfry-operator helm-charts)
HELM_REPO_URL=https://${ORG}.github.io/helm-charts/
CHART=belfry-operator
SIGNER_REPO=${ORG}/.github

dry_run=false
verify_only=false
assume_yes=false
from=""
version=""

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --verify) verify_only=true ;;
    --yes|-y) assume_yes=true ;;
    --from) from="$2"; shift ;;
    -h|--help) usage ;;
    -*) echo "Unknown option $1" >&2; usage 1 ;;
    *) version="$1" ;;
  esac
  shift
done

log() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok() { printf '  \033[32mok\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; failures=$((failures + 1)); }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
failures=0
state_dir=$(mktemp -d)
trap 'rm -rf "$state_dir"' EXIT

if $dry_run; then
  version=${version:-0.0.0-rc.0}
  tag=release-test
else
  [ -n "$version" ] || usage 1
  tag=$version
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] \
  || die "the version must be X.Y.Z or X.Y.Z-rc.N without a v prefix, got: $version"
if [[ "$version" == *-rc.* ]]; then prerelease=true; else prerelease=false; fi
py_version=${version/-rc./rc}

for cmd in gh curl jq; do command -v "$cmd" > /dev/null || die "$cmd is required"; done
gh auth status > /dev/null 2>&1 || die "gh is not logged in"

# --- registry helpers (anonymous pulls of the public ghcr.io images) -------

registry_token() {
  curl -fsS "https://ghcr.io/token?scope=repository:${ORG}/$1:pull" | jq -r .token
}

# manifest <image> <tag>: print the manifest (index) JSON, fail if missing
manifest() {
  curl -fsS -H "Authorization: Bearer $(registry_token "$1")" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://ghcr.io/v2/${ORG}/$1/manifests/$2"
}

# digest <image> <tag>
digest() {
  curl -fsS -o /dev/null -D - -H "Authorization: Bearer $(registry_token "$1")" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://ghcr.io/v2/${ORG}/$1/manifests/$2" | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" {print $2}'
}

# --- verification -----------------------------------------------------------

verify_image() {
  local repo=$1 image=$2 ref="ghcr.io/${ORG}/$2:${tag}" m platforms v
  if ! m=$(manifest "$image" "$tag"); then
    fail "$ref does not exist"
    return
  fi
  platforms=$(jq -r '[.manifests[] | select(.platform.os != "unknown") | .platform.os + "/" + .platform.architecture] | sort | join(" ")' <<< "$m")
  if [ "$platforms" = "linux/amd64 linux/arm64" ]; then ok "$ref is built for $platforms"; else fail "$ref platforms: '$platforms'"; fi

  v=$(jq -r '.annotations["org.opencontainers.image.version"] // ""' <<< "$m")
  if [ "$v" = "$version" ]; then ok "$ref is annotated with version $v"; else fail "$ref is annotated with version '$v'"; fi

  local verify_args=(--repo "${ORG}/${repo}" --signer-repo "$SIGNER_REPO")
  $dry_run || verify_args+=(--source-ref "refs/tags/${version}")
  if gh attestation verify "oci://${ref}" "${verify_args[@]}" > /dev/null 2>&1; then
    ok "$ref has a valid build provenance attestation from ${ORG}/${repo}"
  else
    fail "$ref: gh attestation verify oci://${ref} ${verify_args[*]} failed"
  fi
  if gh attestation verify "oci://${ref}" "${verify_args[@]}" --predicate-type https://spdx.dev/Document/v2.3 > /dev/null 2>&1; then
    ok "$ref has a valid SBOM attestation"
  else
    fail "$ref has no valid SBOM attestation"
  fi

  if ! $dry_run; then
    local d latest
    d=$(digest "$image" "$tag")
    latest=$(digest "$image" latest 2> /dev/null || true)
    if $prerelease; then
      if [ "$latest" != "$d" ]; then ok "${image}:latest is not this release candidate"; else fail "${image}:latest points to the release candidate"; fi
    else
      if [ "$latest" = "$d" ]; then ok "${image}:latest is ${version} (${d})"; else fail "${image}:latest is ${latest:-missing}, not ${version} (${d})"; fi
    fi
  fi

  if command -v docker > /dev/null && docker info > /dev/null 2>&1; then
    case "$image" in
      belfry)
        v=$(docker run --rm --pull always --entrypoint /var/lib/awx/venv/awx/bin/python "$ref" -c 'from awx import __version__; print(__version__)')
        [ "$v" = "$py_version" ] && ok "$ref reports version $v" || fail "$ref reports version $v, expected $py_version" ;;
      belfry-operator)
        v=$(docker run --rm --pull always --entrypoint env "$ref" | grep -E '^(DEFAULT_AWX_VERSION|OPERATOR_VERSION)=' | sort | tr '\n' ' ')
        [ "$v" = "DEFAULT_AWX_VERSION=${tag} OPERATOR_VERSION=${version} " ] && ok "$ref: $v" || fail "$ref: $v" ;;
    esac
  fi
}

verify_assets() {
  local repo=$1; shift
  local assets missing=()
  assets=$(gh release view "$version" -R "${ORG}/${repo}" --json assets --jq '.assets[].name')
  for a in "$@"; do grep -qxF "$a" <<< "$assets" || missing+=("$a"); done
  if [ ${#missing[@]} -eq 0 ]; then ok "${repo} release ${version} has: $*"; else fail "${repo} release ${version} is missing: ${missing[*]}"; fi
}

verify_release() {
  local repo=$1 json
  json=$(gh release view "$version" -R "${ORG}/${repo}" --json isPrerelease,isDraft,url) || { fail "no release ${version} in ${repo}"; return; }
  [ "$(jq -r .isDraft <<< "$json")" = false ] || fail "${repo} ${version} is still a draft"
  if [ "$(jq -r .isPrerelease <<< "$json")" = "$prerelease" ]; then ok "${repo} ${version}: pre-release=${prerelease} ($(jq -r .url <<< "$json"))"; else fail "${repo} ${version}: pre-release should be ${prerelease}"; fi
}

verify_chart() {
  local index
  if $dry_run; then
    ok "helm-charts dry run: the chart is a workflow artifact, nothing to check in the index"
    return
  fi
  index=$(curl -fsSL "${HELM_REPO_URL}index.yaml") || { fail "cannot fetch ${HELM_REPO_URL}index.yaml"; return; }
  if command -v yq > /dev/null; then
    if yq -e ".entries.\"${CHART}\"[] | select(.version == \"${version}\" and .appVersion == \"${version}\")" <<< "$index" > /dev/null 2>&1; then
      ok "${CHART} ${version} (appVersion ${version}) is in ${HELM_REPO_URL}index.yaml"
    else
      fail "${CHART} ${version} is not in ${HELM_REPO_URL}index.yaml"
    fi
  elif grep -q "version: ${version}\$" <<< "$index"; then
    ok "${CHART} ${version} is in ${HELM_REPO_URL}index.yaml"
  else
    fail "${CHART} ${version} is not in ${HELM_REPO_URL}index.yaml"
  fi
  if command -v helm > /dev/null; then
    local tmp; tmp=$(mktemp -d)
    if HELM_REPOSITORY_CONFIG="$tmp/repositories.yaml" HELM_REPOSITORY_CACHE="$tmp/cache" sh -c \
      "helm repo add belfry '${HELM_REPO_URL}' > /dev/null && helm show chart belfry/${CHART} --version '${version}'" > "$tmp/chart.yaml"; then
      ok "helm show chart belfry/${CHART} --version ${version}: appVersion $(awk '/^appVersion:/ {print $2}' "$tmp/chart.yaml")"
    else
      fail "helm cannot fetch belfry/${CHART} ${version}"
    fi
    rm -rf "$tmp"
  fi
}

verify_repo() {
  local repo=$1
  log "Verify ${repo} (${tag})"
  $dry_run || verify_release "$repo"
  case "$repo" in
    belfry-ee)
      verify_image "$repo" belfry-ee
      $dry_run || verify_assets "$repo" "belfry-ee-${version}.spdx.json" "belfry-ee-${version}-trivy.json" ;;
    belfry)
      verify_image "$repo" belfry
      $dry_run || verify_assets "$repo" "belfry-${version}.spdx.json" "belfry-${version}-trivy.json" \
        "awx-awx-${version}.tar.gz" "awxkit-${py_version}.tar.gz" "awxkit-${py_version}-py3-none-any.whl" SHA256SUMS ;;
    belfry-operator)
      verify_image "$repo" belfry-operator
      $dry_run || verify_assets "$repo" "belfry-operator-${version}.spdx.json" "belfry-operator-${version}-trivy.json" \
        belfry-operator.yaml belfry-operator.yaml.sha256 ;;
    helm-charts)
      $dry_run || verify_assets "$repo" "${CHART}-${version}.tgz"
      verify_chart ;;
  esac
}

# --- workflow runs ----------------------------------------------------------

# dispatch_inputs <repo> <run>: "<version> <dry_run>" of a manual run, read
# from the log of its "Determine the version" step (the run list does not show
# the inputs); nothing while that step has not finished
dispatch_inputs() {
  local repo=$1 run=$2 cache job
  cache="${state_dir}/${repo}-${run}"
  if [ ! -f "$cache" ]; then
    job=$(gh run view "$run" -R "${ORG}/${repo}" --json jobs \
      --jq '[.jobs[] | select(any(.steps[]; .name == "Determine the version" and .status == "completed"))] | .[0].databaseId // empty')
    [ -n "$job" ] || return 0
    gh run view "$run" -R "${ORG}/${repo}" --job "$job" --log \
      | sed -nE 's/.*Z (version|dry_run)=([^ ]*)$/\1 \2/p' \
      | awk '{a[$1] = $2} END {print a["version"], a["dry_run"]}' > "$cache"
  fi
  cat "$cache"
}

# release_runs <repo> <since>: the release workflow runs for this release,
# newest first, as "<id> <status>" lines: the runs of the `release: published`
# event for the tag and, because GitHub sometimes does not send that event,
# manual runs with this version and dry_run=false started since <since> (when
# the release was published).
release_runs() {
  local repo=$1 since=$2 id event status
  gh run list -R "${ORG}/${repo}" --workflow release.yml --limit 50 \
    --json databaseId,event,headBranch,createdAt,status \
    --jq "[.[] | select((.event == \"release\" and .headBranch == \"${version}\")
                     or (.event == \"workflow_dispatch\" and .createdAt >= \"${since}\"))]
          | sort_by(.createdAt) | reverse | .[] | \"\(.databaseId) \(.event) \(.status)\"" \
    | while read -r id event status; do
        if [ "$event" = release ] || [ "$(dispatch_inputs "$repo" "$id")" = "${version} false" ]; then
          echo "$id $status"
        fi
      done
}

# find_run <repo> <since>: id of the release workflow run for this release: the
# one in progress, else the newest
find_run() {
  local repo=$1 since=$2
  if $dry_run; then
    gh run list -R "${ORG}/${repo}" --workflow release.yml --event workflow_dispatch --branch main \
      --json databaseId,createdAt --jq "[.[] | select(.createdAt >= \"${since}\")] | .[0].databaseId // empty"
  else
    release_runs "$repo" "$since" | awk 'NR == 1 {newest = $1} $2 == "in_progress" {print $1; found = 1; exit} END {if (!found && newest) print newest}'
  fi
}

# poll_run <repo> <since> <deadline>: find_run until it finds a run or the
# deadline (epoch seconds) has passed
poll_run() {
  local repo=$1 since=$2 deadline=$3 run
  while :; do
    run=$(find_run "$repo" "$since")
    if [ -n "$run" ] || [ "$(date +%s)" -ge "$deadline" ]; then
      echo "$run"
      return
    fi
    sleep 5
  done
}

# cancel_duplicates <repo> <since> <run> [finished]: cancel the other runs for
# this release that wait to start, e.g. a late `release` event run after
# release.sh started the workflow itself. The release workflows have a
# concurrency group per release (helm-charts: one for all releases), so such a
# run waits for <run> and would then build and publish everything again. Runs
# in progress are only cancelled once <run> has finished (before that, find_run
# picks the run in progress).
cancel_duplicates() {
  local repo=$1 since=$2 run=$3 finished=${4:-} id status
  $dry_run && return
  while read -r id status; do
    [ -n "$id" ] && [ "$id" != "$run" ] && [ "$status" != completed ] || continue
    [ "$status" != in_progress ] || [ -n "$finished" ] || continue
    echo "Cancelling the duplicate release workflow run https://github.com/${ORG}/${repo}/actions/runs/${id} (${status})"
    gh run cancel "$id" -R "${ORG}/${repo}" > /dev/null || fail "cannot cancel run ${id} in ${repo}"
  done < <(release_runs "$repo" "$since")
}

wait_for_run() {
  local repo=$1 since=$2 run="" conclusion deadline
  local dispatch=(gh workflow run release.yml -R "${ORG}/${repo}" --ref main -f version="$version" -f dry_run=false)
  # Wait for the run up to 5 minutes after <since>: when the release was
  # published, or when the dry run was started.
  deadline=$(( $(jq -rn --arg t "$since" '$t | fromdateiso8601') + 300 ))
  run=$(poll_run "$repo" "$since" "$deadline")
  if [ -z "$run" ] && ! $dry_run; then
    printf '  \033[33mGitHub did not start the release workflow of %s for the published release.\033[0m\n' "$repo"
    echo "  Starting it: ${dispatch[*]}"
    "${dispatch[@]}"
    run=$(poll_run "$repo" "$since" $(( $(date +%s) + 300 )))
  fi
  [ -n "$run" ] || die "no release workflow run appeared in ${repo}"
  if $dry_run; then
    echo "  (For a release, if GitHub does not start the workflow for the published release, release.sh runs: ${dispatch[*]})"
  fi
  echo "Workflow run: https://github.com/${ORG}/${repo}/actions/runs/${run}"
  cancel_duplicates "$repo" "$since" "$run"
  conclusion=$(gh run view "$run" -R "${ORG}/${repo}" --json status,conclusion --jq 'if .status == "completed" then .conclusion else "" end')
  if [ -z "$conclusion" ]; then
    gh run watch "$run" -R "${ORG}/${repo}" --interval 30 --exit-status > /dev/null || true
    conclusion=$(gh run view "$run" -R "${ORG}/${repo}" --json conclusion --jq .conclusion)
  fi
  cancel_duplicates "$repo" "$since" "$run" finished
  if [ "$conclusion" != success ]; then
    gh run view "$run" -R "${ORG}/${repo}" | tail -25
    die "the release workflow of ${repo} ended with '${conclusion}'. Fix it (e.g. gh run rerun ${run} -R ${ORG}/${repo} --failed), then rerun this script with --from ${repo}"
  fi
  ok "release workflow of ${repo} succeeded"
}

# --- main ---------------------------------------------------------------------

if $verify_only; then
  for repo in "${REPOS[@]}"; do verify_repo "$repo"; done
  [ "$failures" -eq 0 ] && { log "All checks passed"; exit 0; } || die "${failures} check(s) failed"
fi

started=false
[ -z "$from" ] && started=true
declare -A targets

log "Preflight"
for repo in "${REPOS[@]}"; do
  sha=$(gh api "repos/${ORG}/${repo}/commits/main" --jq .sha)
  targets[$repo]=$sha
  status=$(gh api "repos/${ORG}/${repo}/commits/${sha}/check-runs?per_page=100" \
    --jq '[.check_runs[] | select(.conclusion != null and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral") | .name] | join(", ")')
  existing=$($dry_run || gh release view "$version" -R "${ORG}/${repo}" --json tagName --jq .tagName 2> /dev/null || true)
  printf '  %-16s main %s%s%s\n' "$repo" "${sha:0:12}" \
    "${status:+  failed checks: $status}" "${existing:+  (release ${existing} exists)}"
done
if $dry_run; then
  echo "Dry run of version ${version}: runs each release workflow on main with dry_run=true; publishes only :release-test, no releases."
else
  echo "Release ${version} ($($prerelease && echo 'release candidate: pre-release, no :latest' || echo 'final release: also :latest'))."
fi
if ! $assume_yes; then
  read -r -p "Continue? [y/N] " answer
  [ "$answer" = y ] || [ "$answer" = Y ] || exit 1
fi

for repo in "${REPOS[@]}"; do
  [ "$repo" = "$from" ] && started=true
  if ! $started; then
    verify_repo "$repo"
    continue
  fi
  log "${repo}"
  since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if $dry_run; then
    gh workflow run release.yml -R "${ORG}/${repo}" --ref main -f version="$version" -f dry_run=true
  elif gh release view "$version" -R "${ORG}/${repo}" > /dev/null 2>&1; then
    echo "Release ${version} exists in ${repo}"
  else
    # gh release create reuses an existing tag and ignores --target, so a tag
    # left over from the imported upstream history would release old code.
    if existing=$(gh api "repos/${ORG}/${repo}/commits/refs/tags/${version}" --jq .sha 2>/dev/null) \
        && [ "$existing" != "${targets[$repo]}" ]; then
      die "tag ${version} already exists in ${repo} at ${existing:0:10}, not at main ${targets[$repo]:0:10}; rename or remove it first"
    fi
    args=(--target "${targets[$repo]}" --title "Belfry ${version}" --generate-notes)
    if $prerelease; then args+=(--prerelease --latest=false); else args+=(--latest); fi
    gh release create "$version" -R "${ORG}/${repo}" "${args[@]}"
  fi
  # Runs for a release are matched from the time it was published, also when
  # it was created by an earlier invocation (--from).
  $dry_run || since=$(gh release view "$version" -R "${ORG}/${repo}" --json publishedAt --jq .publishedAt)
  wait_for_run "$repo" "$since"
  verify_repo "$repo"
  [ "$failures" -eq 0 ] || die "${failures} check(s) failed for ${repo}; fix them and rerun with --from ${repo}"
done

log "Done"
if $dry_run; then
  echo "All release workflows passed their dry run."
else
  echo "Belfry ${version} is released:"
  for repo in "${REPOS[@]}"; do echo "  https://github.com/${ORG}/${repo}/releases/tag/${version}"; done
fi
