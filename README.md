# commit-emails-check-action

[![CI](https://github.com/qualcomm/commit-emails-check-action/actions/workflows/ci.yml/badge.svg)](https://github.com/qualcomm/commit-emails-check-action/actions/workflows/ci.yml)

Qualcomm PR email addresses checker

For each commit in a PR, validates that the commit's author and committer email
addresses are appropriate for the repo.

**NOTE:** This action should be used with `pull_request` events.

## Example Usage

```yaml
name: PR email addresses checker

on: pull_request

# If using this action on a private/internal repo, you must grant read access to PRs
permissions:
  pull-requests: read

jobs:
  pr-check-emails:
    runs-on: ubuntu-latest
    steps:
      - name: Check PR emails
        uses: qualcomm/commit-emails-check-action@main
```

## Email address policy

- Committer (in all cases) or Author (when commit is not an upstream cherry-pick)
  - Block `@.*qualcomm.com` except `@qti.qualcomm.com` and `@oss.qualcomm.com`
  - Block `<username>@quicinc.com` unless the custom repository property
    `allow-quicinc-authors` (for authors) or `allow-quicinc-committers` (for committers)
    is set to true
  - Block `quic_<username>@quicinc.com` (starting Jan 2026)
  - Block `@codeaurora.org`
- Author (when commit is an [upstream cherry-pick](#upstream-cherry_pick))
  - Block `@.*qualcomm.com` except `@qti.qualcomm.com` and `@oss.qualcomm.com`
  - Allow `<username>@quicinc.com`
  - Allow `quic_<username>@quicinc.com` if author date is before Jan 1 2026
  - Allow `@codeaurora.org` if author date is before Dec 4 2021

The action also includes a check for email address characters in the commit identity "name".
Malformed committer names are errors and malformed author names are warnings.

### Upstream cherry-pick

A commit is classified as an upstream cherry-pick if the commit message
contains any of the following:

- the footers `Git-Repo:` and `Git-Commit:`
- the footer `Patch-mainline:`
- the text `cherry picked from commit <commit-id>`

## Copyright and License

```text
Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
SPDX-License-Identifier: BSD-3-Clause
```
