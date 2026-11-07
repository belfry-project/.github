# Decisions

Decisions about the Belfry project that affect users, with the reasoning, so they can be reviewed later. Newest first.

## 2026-11-06: PostgreSQL 18 for the managed database

The operator's managed database moves from PostgreSQL 15 (`quay.io/sclorg/postgresql-15-c9s`, supported until November 2027) to 18 (`quay.io/sclorg/postgresql-18-c10s`, supported until November 2030); sclorg publishes no 17. Existing installations are migrated on the first reconcile (a dump into a new PostgreSQL 18 instance, which needs a second volume of the same size and some downtime); external databases are not touched. Tested from AWX 24.6.1 and from belfry-operator 1.0.0, including backup and restore across versions ([belfry-operator#30](https://github.com/belfry-project/belfry-operator/pull/30)).

Unlike Belfry's own images (AlmaLinux 10, see above), the database keeps sclorg's CentOS Stream image: no maintained non-Stream image has the layout the operator relies on (`POSTGRESQL_*` variables, `run-postgresql`, `/var/lib/pgsql/data/userdata`, UID 26). AlmaLinux publishes only base images, Red Hat's `rhel10/postgresql` images fall under the RHEL EULA, sclorg's Fedora images follow Fedora's 13-month lifecycle, and the Docker library image has another layout, which would need other templates and another data migration. The image runs only PostgreSQL, built from the same packages as RHEL 10. Belfry deliberately uses this public image rather than building and maintaining its own: it is maintained and updated by sclorg, and a Belfry-built copy would add work without a gain for users. Installations that want another PostgreSQL 18 image with the same layout can set `postgres_image` and `postgres_image_version` in the `AWX` resource.

## 2026-11-06: AlmaLinux 10 and Python 3.14 for the images

The `belfry` image (and the development images built from the same Dockerfile), `belfry-ee` and the operator's `init-projects` container are based on **AlmaLinux 10** (`quay.io/almalinuxorg/almalinux:10`, `:10-minimal` for the init container), and Belfry runs on **Python 3.14**. AWX 24.6.1 uses CentOS Stream 9 and Python 3.11/3.12.

- **Why not stay on CentOS:** CentOS Stream is a rolling preview of the next RHEL minor release: packages land there before RHEL has released them, and there are no point releases to pin or test against. CentOS Stream 9 ends in 2027 and Stream 10 around 2030.
- **Why AlmaLinux 10:** a free, redistributable rebuild of RHEL 10 with point releases, security errata and support until 2035. It has the same package names as RHEL and CentOS, so AWX's Dockerfile keeps its structure, and RHEL-based clients run the same distribution family they know.
- **Alternatives considered:** Rocky Linux 10 (technically equivalent; we standardise on one of the two), Red Hat UBI 10 (its free repositories lack build packages the image needs, such as xmlsec1-devel, swig and libtool-ltdl-devel), Debian/Ubuntu (a rewrite of the Dockerfile without a gain), and Alpine or distroless images (no rsyslog or nginx in the base, and musl breaks prebuilt Python wheels).
- **Python 3.14:** the newest Python in EL 10, with upstream support until 2030. It is installed from the distribution (`python3.14`, `python3.14-psycopg2`), and `requirements.txt` is compiled for it.
- New major releases (AlmaLinux 11, a newer Python) are a manual change; Renovate only refreshes the digest of the pinned base images.

([belfry#36](https://github.com/belfry-project/belfry/pull/36), [belfry-ee#16](https://github.com/belfry-project/belfry-ee/pull/16), [belfry-operator#29](https://github.com/belfry-project/belfry-operator/pull/29))

## 2026-11-05: Release tags and `:latest`

Discussed in [belfry#7](https://github.com/belfry-project/belfry/issues/7); the procedure is in [RELEASING.md](RELEASING.md).

- **Tags:** `X.Y.Z` and `X.Y.Z-rc.N` for release candidates, **without a `v` prefix**, the same tag in belfry-ee, belfry, belfry-operator and helm-charts. The tag is used unchanged as the image tag, which is what the operator expects: it deploys `belfry:<DEFAULT_AWX_VERSION>` and `belfry-ee:<DEFAULT_AWX_VERSION>`, and upstream AWX, awx-ee and awx-operator tags have no prefix either, so existing tooling and docs keep working. `-rc.N` is semver pre-release syntax, so Helm treats release candidates as pre-releases, and it maps cleanly to PEP 440 (`1.0.0rc1`) for awxkit and the version the API reports.
- **Release candidates** are GitHub pre-releases and never get `:latest`.
- **`:latest`** of `belfry`, `belfry-ee` and `belfry-operator` is the **newest final release**, moved only by the release workflow. `:main` is the newest build of `main` (belfry-ee also `:main-<sha>`). Before, belfry-ee's `main` builds were also tagged `:latest`; `latest` for an image that is published by releases is commonly read as "newest stable release", and mixing both meanings would let a `main` build replace a release for anyone pulling `:latest`. Development and test defaults that meant "newest build" now use `:main` (awxkit's default EE image, belfry CI's operator test).
- **Default execution environments follow the Belfry version.** Released installations never run jobs in unreleased EE builds. In belfry-operator, "AWX EE (latest)", "AWX EE (<version>)" and the control plane EE all use `belfry-ee:<DEFAULT_AWX_VERSION>`: `belfry-ee:X.Y.Z` in a release, `belfry-ee:main` in a build of `main`. Belfry's own defaults (`GLOBAL_JOB_EXECUTION_ENVIRONMENTS`, `CONTROL_PLANE_EXECUTION_ENVIRONMENT`, for installations without the operator) do the same from the version of the image. We chose the version tag over `:latest` so that the EE of an installation only changes when it is upgraded, together with Belfry, and not whenever a new release is published; "AWX EE (latest)" keeps its upstream name so that job templates using it keep working. ([belfry-operator#19](https://github.com/belfry-project/belfry-operator/pull/19), [belfry#34](https://github.com/belfry-project/belfry/pull/34))
- **Chart version** = Belfry version, so `helm install --version 1.0.0` installs Belfry 1.0.0; the chart on `main` stays at `0.1.0`/`main` and is only published from releases.

## 2026-11-06: Upstream version tags are prefixed

The repositories were imported with their upstream history, including upstream's version tags. AWX's own first release was also `1.0.0` (2017), so releasing Belfry 1.0.0 reused that tag. In belfry the upstream tags are renamed `awx-<version>` (101 tags, `awx-1.0.0` … `awx-24.6.1`) and in belfry-operator `awx-operator-<version>` (69 tags), pointing at the same objects. Plain `X.Y.Z` and `X.Y.Z-rc.N` tags are Belfry's own. `tools/release.sh` stops when a version tag already exists at another commit. Do not push old local tags back (`git push --tags` from an old clone would recreate them): fetch with `git fetch --prune --prune-tags` first.

## 2026-11-05: Version, CRD API group and rebrand scope for 1.0

Discussed in [belfry#21](https://github.com/belfry-project/belfry/issues/21).

- **Version scheme:** releases start at **1.0.0**, with semantic versioning, instead of continuing AWX's numbering (24.x). Belfry is a separate product, and its compatibility promises start at 1.0.
- **Kubernetes CRD API group:** keep **`awx.ansible.com`** for 1.0. Existing `AWX`, `AWXBackup` and `AWXRestore` resources keep working when switching from awx-operator to belfry-operator. A rename can be reconsidered after 1.0, based on the upgrade test ([belfry-operator#13](https://github.com/belfry-project/belfry-operator/issues/13)); tracked in [belfry-operator#4](https://github.com/belfry-project/belfry-operator/issues/4).
- **Rebrand for 1.0:** the **minimum**: no AWX logo, and the name Belfry in the UI and docs ([belfry#9](https://github.com/belfry-project/belfry/issues/9)). Internals stay unchanged (the Python package `awx`, the API paths and the collection `awx.awx`). The rest is deferred to [belfry#23](https://github.com/belfry-project/belfry/issues/23).

## 2026-11-05: Redis 8

The operator and the development environment use the newest Redis release (8.10.3) instead of the floating Redis 7 tag, which is licensed under RSALv2/SSPL. Redis 8 can be used under the AGPLv3. See [belfry-operator#9](https://github.com/belfry-project/belfry-operator/issues/9).

## 2026-11-04: Hosting, repositories and name

- Everything is built and published on GitHub: images on ghcr.io, the site and charts on GitHub Pages, and the collection and CLI on GitHub Releases. There are no Quay, Galaxy or PyPI accounts.
- The repositories are standalone copies of the upstream repositories, with their full history, and not GitHub forks.
- The name Belfry refers to a bell tower, a nod to Ansible Tower, where AWX comes from. An EUIPO search found no conflicting mark for software; Belfry Medical GmbH's class 42 registration is to be checked.
