#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)

run_non_pr_event_test() {
    local event output status
    event=$1

    if [ "$event" = "unset" ] ; then
        if output=$(env -u GITHUB_EVENT_NAME -u PULL_NUMBER -u COMMITS_COUNT \
            GITHUB_API_URL= \
            PATH="$ROOT_DIR/test/fake_bin:$PATH" \
            "$ROOT_DIR/check_email_pr.sh" 2>&1) ; then
            status=0
        else
            status=$?
        fi
    elif output=$(env -u PULL_NUMBER -u COMMITS_COUNT \
        GITHUB_API_URL= \
        GITHUB_EVENT_NAME="$event" \
        PATH="$ROOT_DIR/test/fake_bin:$PATH" \
        "$ROOT_DIR/check_email_pr.sh" 2>&1) ; then
        status=0
    else
        status=$?
    fi

    [ "$status" -eq 0 ]
    ! grep -q 'curl was called' <<< "$output"
    ! grep -q 'jq was called' <<< "$output"
    ! grep -q 'integer expression expected' <<< "$output"
}

run_pull_request_event_test() {
    local event output
    event=$1

    output=$(env -u TEST_MODE \
        PULL_NUMBER=1 \
        COMMITS_COUNT=2 \
        GITHUB_API_URL=https://api.example.com \
        GITHUB_EVENT_NAME="$event" \
        PATH="$ROOT_DIR/test/fake_bin/pr_target:$PATH" \
        "$ROOT_DIR/check_email_pr.sh" 2>&1)

    grep -q 'Running check on:' <<< "$output"
}

run_workflow_run_pull_request_test() {
    local event output status
    event=$1

    if output=$(env -u TEST_MODE \
        GITHUB_EVENT_PATH="$ROOT_DIR/test/workflow_run_event.json" \
        GITHUB_API_URL=https://api.example.com \
        GITHUB_EVENT_NAME=workflow_run \
        WORKFLOW_RUN_EVENT="$event" \
        PATH="$ROOT_DIR/test/fake_bin/workflow_run:$PATH" \
        "$ROOT_DIR/check_email_pr.sh" 2>&1) ; then
        status=0
    else
        status=$?
    fi

    [ "$status" -eq 0 ]
    [ "$(grep -c 'Running check on:' <<< "$output")" -eq 4 ]
}

run_workflow_run_non_pr_event_test() {
    local output status

    if output=$(env -u TEST_MODE -u PULL_NUMBER -u COMMITS_COUNT \
        GITHUB_EVENT_PATH="$ROOT_DIR/test/workflow_run_event.json" \
        GITHUB_API_URL= \
        GITHUB_EVENT_NAME=workflow_run \
        WORKFLOW_RUN_EVENT=push \
        PATH="$ROOT_DIR/test/fake_bin:$PATH" \
        "$ROOT_DIR/check_email_pr.sh" 2>&1) ; then
        status=0
    else
        status=$?
    fi

    [ "$status" -eq 0 ]
    ! grep -q 'curl was called' <<< "$output"
    ! grep -q 'jq was called' <<< "$output"
}

run_workflow_run_empty_pull_requests_test() {
    local output status

    if output=$(env -u TEST_MODE -u PULL_NUMBER -u COMMITS_COUNT \
        GITHUB_EVENT_PATH="$ROOT_DIR/test/workflow_run_empty_pull_requests_event.json" \
        GITHUB_API_URL=https://api.example.com \
        GITHUB_EVENT_NAME=workflow_run \
        WORKFLOW_RUN_EVENT=pull_request \
        PATH="$ROOT_DIR/test/fake_bin/workflow_run:$PATH" \
        "$ROOT_DIR/check_email_pr.sh" 2>&1) ; then
        status=0
    else
        status=$?
    fi

    [ "$status" -eq 0 ]
    grep -q 'no associated pull requests' <<< "$output"
}

for event in push workflow_dispatch schedule unset ; do
    run_non_pr_event_test "$event"
done
run_pull_request_event_test pull_request
run_pull_request_event_test pull_request_target
run_workflow_run_pull_request_test pull_request
run_workflow_run_pull_request_test pull_request_target
run_workflow_run_non_pr_event_test
run_workflow_run_empty_pull_requests_test
