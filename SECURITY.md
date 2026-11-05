# Security policy

## Reporting a vulnerability

Please report security vulnerabilities **privately**, through GitHub's private vulnerability reporting: open the **Security** tab of the affected repository and choose **Report a vulnerability**.

- [belfry](https://github.com/belfry-project/belfry/security/advisories/new): the application, API, collection and CLI
- [belfry-operator](https://github.com/belfry-project/belfry-operator/security/advisories/new): the Kubernetes operator
- [belfry-ee](https://github.com/belfry-project/belfry-ee/security/advisories/new): the execution environment image
- [helm-charts](https://github.com/belfry-project/helm-charts/security/advisories/new): the Helm chart
- [belfry-ui](https://github.com/belfry-project/belfry-ui/security/advisories/new): the web UI

Do not report vulnerabilities in public issues, pull requests or discussions.

## What to include

- A short, descriptive title
- The affected repository, image or component, and the affected versions or image digests
- A description of the vulnerability, and steps to reproduce it
- The impact: what an attacker can do, and under which conditions
- A suggested fix, if you have one

## What to expect

- We aim to acknowledge a report within five working days.
- We investigate, keep you informed, and agree on a disclosure date with you.
- Fixes are released as soon as possible, and are announced in a GitHub security advisory, with a CVE where appropriate. We credit reporters who want to be credited.

Belfry is a community project maintained by volunteers, so these are goals rather than guarantees.

## Vulnerabilities that also affect AWX

Belfry is based on [AWX](https://github.com/ansible/awx), so a vulnerability may also affect AWX or Ansible. If it does, we tell you, and with your agreement coordinate disclosure with the Ansible security team (security@ansible.com).

Vulnerabilities in third-party dependencies should be reported to that project. Please also tell us if Belfry is affected, so we can update it.

## Supported versions

| Version | Supported |
|---|---|
| Images built from `main` (`:main`, `:latest`) | Yes, until the first release |
| Belfry releases | Planned from 1.0: the latest release receives security fixes |

Known vulnerabilities in the published images are scanned daily and shown on [belfry-project.github.io](https://belfry-project.github.io/).
