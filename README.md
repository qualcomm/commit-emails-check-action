# commit-emails-check-action

[![CI](https://github.com/qualcomm/commit-emails-check-action/actions/workflows/ci.yaml/badge.svg)](https://github.com/qualcomm/commit-emails-check-action/actions/workflows/ci.yaml)

Qualcomm PR email addresses checker

For each commit in a PR, validates that the commit's author and committer email
addresses are appropriate for the repo.

**NOTE:** This action should be used with `pull_request` events.

## Example Usage

```yaml
name: PR email addresses checker

on:
  pull_request:
    branches: ["main"]

jobs:
  pr-check-emails:
    runs-on: ubuntu-latest
    steps:
      - name: Check PR emails
        uses: qualcomm/commit-emails-check-action@main
```

## Copyright and License

```text
Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
SPDX-License-Identifier: BSD-3-Clause
```
