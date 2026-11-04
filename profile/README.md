# Belfry

**Belfry** is a community continuation of [AWX](https://github.com/ansible/awx): a web UI, REST API and task engine for running Ansible automation at scale, together with a Kubernetes operator to deploy it.

Upstream AWX releases have been paused since version 2.19.1 (July 2024). Belfry aims to keep a working, regularly released, fully open distribution available, built and hosted entirely on GitHub.

> **Status: early setup.** The repositories currently contain the imported upstream history. Rebranding, pinned dependencies and the first build pipelines are in progress. There are no Belfry releases yet.

## Repositories

| Repository | Description | Based on |
|---|---|---|
| [belfry](https://github.com/belfry-project/belfry) | Core application: REST API, task engine, Ansible collection and CLI | [ansible/awx](https://github.com/ansible/awx) |
| [belfry-operator](https://github.com/belfry-project/belfry-operator) | Kubernetes operator to deploy and manage Belfry | [ansible/awx-operator](https://github.com/ansible/awx-operator) |
| [belfry-ee](https://github.com/belfry-project/belfry-ee) | Default execution environment image | [ansible/awx-ee](https://github.com/ansible/awx-ee) |
| [belfry-ui](https://github.com/belfry-project/belfry-ui) | Web user interface | [ansible/ansible-ui](https://github.com/ansible/ansible-ui) |
| [helm-charts](https://github.com/belfry-project/helm-charts) | Helm chart for the operator | [ansible-community/awx-operator-helm](https://github.com/ansible-community/awx-operator-helm) |
| [image-mirror](https://github.com/belfry-project/image-mirror) | Mirrors third-party container images to `ghcr.io/belfry-project` | — |

## Where things will live

- **Container images:** `ghcr.io/belfry-project/*`
- **Helm charts and documentation:** GitHub Pages
- **Ansible collection and CLI:** GitHub Releases

## Credits and trademarks

Belfry builds on the work of the AWX, AWX Operator and Ansible UI contributors, and keeps their full commit history and licenses.

Belfry is an independent project. It is not affiliated with, endorsed by or sponsored by Red Hat, Inc. or the Ansible project. AWX and Ansible are trademarks of Red Hat, Inc.
