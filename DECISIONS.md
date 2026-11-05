# Decisions

Decisions about the Belfry project that affect users, with the reasoning, so they can be reviewed later. Newest first.

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
