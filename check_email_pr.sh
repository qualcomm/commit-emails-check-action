#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause

readlink -f / &> /dev/null || readlink() { greadlink "$@" ; } # for MacOS
MYPROG=$(readlink -f -- "$0")
MYDIR=$(dirname -- "$MYPROG")

debug() { echo "::debug::$1" >&2 ; } # message
error() { echo "::error::$1" >&2 ; } # message

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
    debug "Getting commits from $endpoint"
    local debug_opts=()
    [ -n "$RUNNER_DEBUG" ] && debug_opts=("--verbose" "--progress-meter" "--show-error")
    curl -L --no-progress-meter --fail-with-body \
        "${debug_opts[@]}" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$endpoint"
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

while [ $# -gt 0 ] ; do
    case "$1" in
        --test) shift ; TEST_MODE=("--verbose") ;;
        *) usage ;;
    esac
    shift
done

RESULT=0
custom_properties=$(get_custom_properties)
while read -r pr_commit ; do
    debug "Running check on: $pr_commit"
    "$MYDIR"/src/check_email.sh \
        --commit-json "$pr_commit" \
        --custom-properties-json "$custom_properties" \
        "${TEST_MODE[@]}" || RESULT=1
done < <(get_pr_commits | split_commits_and_add_metadata)

exit $RESULT
