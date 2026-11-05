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

# find_run <repo> <since>: id of the newest release workflow run for this release
find_run() {
  local repo=$1 since=$2
  if $dry_run; then
    gh run list -R "${ORG}/${repo}" --workflow release.yml --event workflow_dispatch --branch main \
      --json databaseId,createdAt --jq "[.[] | select(.createdAt >= \"${since}\")] | .[0].databaseId // empty"
  else
    gh run list -R "${ORG}/${repo}" --workflow release.yml --event release --branch "$version" \
      --json databaseId --jq '.[0].databaseId // empty'
  fi
}

wait_for_run() {
  local repo=$1 since=$2 run="" conclusion
  for _ in $(seq 1 60); do
    run=$(find_run "$repo" "$since")
    [ -n "$run" ] && break
    sleep 5
  done
  [ -n "$run" ] || die "no release workflow run appeared in ${repo}"
  echo "Workflow run: https://github.com/${ORG}/${repo}/actions/runs/${run}"
  conclusion=$(gh run view "$run" -R "${ORG}/${repo}" --json status,conclusion --jq 'if .status == "completed" then .conclusion else "" end')
  if [ -z "$conclusion" ]; then
    gh run watch "$run" -R "${ORG}/${repo}" --interval 30 --exit-status > /dev/null || true
    conclusion=$(gh run view "$run" -R "${ORG}/${repo}" --json conclusion --jq .conclusion)
  fi
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
    args=(--target "${targets[$repo]}" --title "Belfry ${version}" --generate-notes)
    if $prerelease; then args+=(--prerelease --latest=false); else args+=(--latest); fi
    gh release create "$version" -R "${ORG}/${repo}" "${args[@]}"
  fi
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
