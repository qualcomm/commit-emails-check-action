#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause

readlink -f / &> /dev/null || readlink() { greadlink "$@" ; } # for MacOS
MYPROG=$(readlink -f -- "$0")
MYDIR=$(dirname -- "$MYPROG")

debug() { echo "::debug::$1" >&2 ; } # message
error() { echo "::error::$1" >&2 ; } # message

# Make an authenticated request to the GitHub REST API.
github_api_get() {
    local endpoint=$1
    debug "Getting data from $endpoint"
    local debug_opts=()
    [ -n "$RUNNER_DEBUG" ] && debug_opts=("--verbose" "--progress-meter" "--show-error")
    curl -L --no-progress-meter --fail-with-body \
        "${debug_opts[@]}" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$endpoint"
}

# https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#get-a-pull-request
get_pr_metadata() {
    local endpoint="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/pulls/$PULL_NUMBER"
    local metadata
    metadata=$(github_api_get "$endpoint") || return 1
    COMMITS_COUNT=$(jq -r '.commits // empty' <<< "$metadata")
    if [ -z "$COMMITS_COUNT" ] ; then
        error "Cannot determine commit count for pull request $PULL_NUMBER"
        return 1
    fi
}

# https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#list-commits-on-a-pull-request
get_pr_commits() {
    if [ -n "$TEST_MODE" ] ; then
        debug "Using list_commits test data"
        cat "$MYDIR"/test/pr_list_commits.json
        return
    fi
    [ "$COMMITS_COUNT" -gt 100 ] && debug "Needs pagination"
    # TODO: Handle paginated results
    # https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api?apiVersion=2022-11-28#using-link-headers
    local endpoint="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/pulls/$PULL_NUMBER/commits?per_page=$COMMITS_COUNT"
    github_api_get "$endpoint"
}

# https://docs.github.com/en/rest/repos/custom-properties?apiVersion=2022-11-28#get-all-custom-property-values-for-a-repository
get_custom_properties() {
    if [ -n "$TEST_MODE" ] ; then
        debug "Using custom_properties test data"
        cat "$MYDIR"/test/custom_properties.json
        return
    fi
    local endpoint="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/properties/values"
    debug "Getting custom properties from $endpoint"
    local debug_opts=()
    [ -n "$RUNNER_DEBUG" ] && debug_opts=("--verbose" "--progress-meter" "--show-error")
    curl -L --no-progress-meter --fail-with-body \
        "${debug_opts[@]}" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$endpoint"
}

split_commits_and_add_metadata() {
    jq -c '.[] |= . + {"extra_allowed_emails": [], "license_type": "OPEN_SOURCE"} | .[]'
}

usage() { # error_message [error_code]
    local prog=$(basename -- "$0")
    cat <<EOF

    usage: $prog [--test]

EOF
    [ $# -gt 0 ] && error "$@"
    [ $# -gt 1 ] && exit $2
    exit 10
}

is_pr_event() {
    case "${GITHUB_EVENT_NAME:-}" in
        pull_request|pull_request_target) return 0 ;;
        workflow_run)
            case "${WORKFLOW_RUN_EVENT:-}" in
                pull_request|pull_request_target) return 0 ;;
            esac
            return 1
            ;;
        *) return 1 ;;
    esac
}

get_pr_numbers() {
    if [ "${GITHUB_EVENT_NAME:-}" = "workflow_run" ] ; then
        jq -r '.workflow_run.pull_requests[]?.number // empty' "$GITHUB_EVENT_PATH"
    else
        echo "$PULL_NUMBER"
    fi
}

check_pr_commits() {
    local result=0
    while read -r pr_commit ; do
        debug "Running check on: $pr_commit"
        "$MYDIR"/src/check_email.sh \
            --commit-json "$pr_commit" \
            --custom-properties-json "$custom_properties" \
            "${TEST_MODE[@]}" || result=1
    done < <(get_pr_commits | split_commits_and_add_metadata)
    return "$result"
}

TEST_MODE=()
while [ $# -gt 0 ] ; do
    case "$1" in
        --test) shift ; TEST_MODE=("--verbose") ;;
        *) usage ;;
    esac
    shift
done

if [ "${#TEST_MODE[@]}" -eq 0 ] && ! is_pr_event ; then
    debug "Skipping email check for non-PR event: ${GITHUB_EVENT_NAME:-unknown}"
    exit 0
fi

if [ "${#TEST_MODE[@]}" -gt 0 ] ; then
    custom_properties=$(get_custom_properties)
    check_pr_commits
    exit $?
fi

if [ "${GITHUB_EVENT_NAME:-}" = "workflow_run" ] && \
        { [ -z "${GITHUB_EVENT_PATH:-}" ] || [ ! -r "$GITHUB_EVENT_PATH" ]; } ; then
    error "Cannot read workflow_run event payload"
    exit 1
fi

PR_NUMBERS=$(get_pr_numbers) || {
    error "Cannot determine pull requests from workflow_run event payload"
    exit 1
}

if [ -z "$PR_NUMBERS" ] ; then
    debug "Skipping email check: workflow_run has no associated pull requests"
    exit 0
fi

RESULT=0
custom_properties=$(get_custom_properties)
while read -r PULL_NUMBER ; do
    [ -n "$PULL_NUMBER" ] || continue
    if [ "${GITHUB_EVENT_NAME:-}" = "workflow_run" ] ; then
        get_pr_metadata || {
            RESULT=1
            continue
        }
    fi
    check_pr_commits || RESULT=1
done <<< "$PR_NUMBERS"

exit $RESULT
