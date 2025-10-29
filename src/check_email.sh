#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#####################################################################
# This script is used to verify that the correct Author and Committer email
# addresses are used for commits to Proprietary and Open Source repositories.
########################################################################

debug() { [ "$VERBOSE" = "true" ] && echo "::debug::$1" >&2 ; } # message
error() { echo "::error::$1" >&2 ; HAS_ERRORS=1 ; } # message
warning() { echo "::warning::$1" >&2 ; } # message

json_val_by_key() { # json key > value
    echo "$1" | jq -r "$2 // empty"
}

has_email_characters() { echo "$1" | grep -q "[@<>]" ; } # name

in_allowlist() { # email
    echo "$COMMIT_JSON" | jq -e --arg email "$1" \
        '.extra_allowed_emails? | contains([$email])' > /dev/null
}

is_caf() { [[ "$1" =~ @codeaurora\.org$ ]] ; } # email_address
is_quicinc() { [[ "$1" =~ @quicinc\.com$ ]] ; } # email_address
is_quic_username() { [[ "$1" =~ ^quic_.*@quicinc\.com$ ]] ; } # email_address
is_any_qualcomm_com() { [[ "$1" =~ @.*qualcomm\.com$ ]] ; } # email_address
is_qti() { [[ "$1" =~ @qti\.qualcomm\.com$ ]] ; } # email_address
is_oss() { [[ "$1" =~ @oss\.qualcomm\.com$ ]] ; } # email_address

is_current_or_past_qc_email() { # email_address
    is_caf "$1" || is_quicinc "$1" || is_any_qualcomm_com "$1"
}

is_upstream_commit() {
    local commit_msg=$(json_val_by_key "$COMMIT_JSON" ".commit.message")
    contains_upstream_commit_footers "$commit_msg" || \
        contains_cherry_picked_from_text "$commit_msg"
}

contains_upstream_commit_footers() { # commit_msg
    echo "$1" | grep -i -q 'Patch-mainline[[:space:]]*:' && return
    echo "$1" | grep -i -q 'Git-repo[[:space:]]*:' && \
        echo "$1" | grep -i -q 'Git-commit[[:space:]]*:'
}

contains_cherry_picked_from_text() { # commit_msg
    echo "$1" | grep -E -i -q 'cherry picked from commit [a-f0-9]{40}'
}

is_author_date_before() { # cutoff_date
    local cutoff_date=$(convert_to_epoch_sec_if_needed "$1")
    [ "$(convert_to_epoch_sec_if_needed "$AUTHOR_DATE")" -lt "$cutoff_date" ]
}
is_committer_date_after() { # cutoff_date
    local cutoff_date=$(convert_to_epoch_sec_if_needed "$1")
    [ "$(convert_to_epoch_sec_if_needed "$COMMITTER_DATE")" -gt "$cutoff_date" ]
}

is_quicinc_allowed() { # role
    local property
    case "$1" in
        Committer) property="allow-quicinc-committers" ;;
        Author) property="allow-quicinc-authors" ;;
        *) return 2 ;; # Not a valid role, programming error
    esac
    echo "$CUSTOM_PROPERTIES_JSON" | jq -e --arg property "$property" \
        'any(.[]; .property_name == $property and .value == "true")' > /dev/null
}

convert_to_epoch_sec_if_needed() { # date-string (possibly already epoch_seconds)
    local first_git_commit=1112911993
    if [ "$1" -gt "$first_git_commit" ] 2> /dev/null ; then
        # already an integer and more recent than the first git commit, assume
        # valid epoch_seconds
        echo "$1"
        return
    fi
    date +%s -d "$1"
}

isPropValid() { # email_address role
    local addr=$1 role=$2 ; shift 2
    # Allow @qti.qualcomm.com
    if is_qti "$addr" ; then
        return 0
    fi
    # Allow <username>@quicinc.com
    if is_quicinc "$addr" && ! is_quic_username "$addr" ; then
        return 0
    fi
    # Allow more authors for upstream cherry-picks
    if [ "Author" == "$role" ] && is_upstream_commit "$COMMIT" ; then
        isOssValid "$addr" 'Author'
        return
    fi
    return 1
}

isOssValid() { # email_address role
    local addr=$1 role=$2 ; shift 2
    case "$role" in
        Committer)
            isOssValidEmailAddr "$addr" "$role"
            return ;;
        Author)
            isOssValidEmailAddr "$addr" "$role" || \
                (is_upstream_commit "$COMMIT" && isValidUpstreamAuthor "$addr")
            return ;;
        *) return 2 ;; # Not a valid role, programming error
    esac
}

isOssValidEmailAddr() { # email_address role
    local addr=$1 ; shift 1
    local role=$1 ; shift 1
    # Block @.*qualcomm.com
    if is_any_qualcomm_com "$addr" ; then
        # except @qti.qualcomm.com and @oss.qualcomm.com
        is_qti "$addr" || is_oss "$addr"
        return
    fi
    # Block <username>@quicinc.com unless the corresponding custom repo properties
    # are set to true
    if is_quicinc "$addr" && ! is_quic_username "$addr" && ! is_quicinc_allowed "$role" ; then
        return 1
    fi
    # Block quic_<username>@quicinc.com (starting Jan 1 2026)
    if is_quic_username "$addr" && is_committer_date_after "2025-12-31" ; then
        return 1
    fi
    if is_caf "$addr" ; then
        return 1
    fi

    # Not blocked by any rule above, so allow
    return 0
}

isValidUpstreamAuthor() { # email_address
    local regex addr=$1 ; shift 1
    if is_current_or_past_qc_email "$addr" ; then
        if is_caf "$addr" ; then
            is_author_date_before "2021-12-04"
            return
        fi
        if is_quicinc "$addr" ; then
            return 0
        fi
        return 1
    fi
    # external domain
    return 0
}

usage() { # error_message [error_code]
    local prog=$(basename -- "$0")
    cat <<EOF

    usage: $prog --commit-json <json_string> \
        [--custom-properties-json <json_string>] [--verbose]

    The input provided to --commit-json should contain this structure (additional
    properties will be ignored):
{
  "commit": {
    "author": {
      "name": "Cal the Coder",
      "email": "cal@example.com",
      "date": "2011-04-14T16:00:49Z"
    },
    "committer": {
      "name": "Cal Coder",
      "email": "cal@example.com",
      "date": "2011-04-14T16:07:25Z"
    },
    "message": "Fix all the bugs"
  },
  "extra_allowed_emails": ["foo@example.com"],
  "license_type": "OPEN_SOURCE"
}

  The "date" values should be either epoch seconds or a format like ISO 8061
  parseable by the \`date\` command.

    The input provided to --custom-properties-json should contain this structure:
[
  {
    "property_name": "Require-commit-email-check",
    "value": "true"
  },
  {
    "property_name": "allow-quicinc-authors",
    "value": "true"
  },
  {
    "property_name": "allow-quicinc-committers",
    "value": "true"
  }
]

EOF

    [ $# -gt 0 ] && error "$@"
    [ $# -gt 1 ] && exit $2
    exit 10
}

HAS_ERRORS=0
VERBOSE=false
CUSTOM_PROPERTIES_JSON="[]"
while [ $# -gt 0 ] ; do
    case "$1" in
        --test-function) shift ; "$@" ; exit ;;
        --commit-json) shift ; COMMIT_JSON=$1 ;;
        --custom-properties-json) shift ; CUSTOM_PROPERTIES_JSON=$1 ;;
        --verbose) VERBOSE=true ;;
        *) usage ;;
    esac
    shift
done

# Proprietary or Open Source
if ! REPO_EMAIL_TYPE=$(json_val_by_key "$COMMIT_JSON" ".license_type") || \
        [ -z "$REPO_EMAIL_TYPE" ] ; then
    error "Cannot determine project license type. Must provide 'license_type' \
        as either 'PROPRIETARY' or 'OPEN_SOURCE'."
    exit
fi

COMMITTER_DATE=$(json_val_by_key "$COMMIT_JSON" ".commit.committer.date")
COMMITTER_EMAIL=$(json_val_by_key "$COMMIT_JSON" ".commit.committer.email")
COMMITTER_NAME=$(json_val_by_key "$COMMIT_JSON" ".commit.committer.name")
debug "Committer is: $COMMITTER_NAME <$COMMITTER_EMAIL> , date: $COMMITTER_DATE"

AUTHOR_DATE=$(json_val_by_key "$COMMIT_JSON" ".commit.author.date")
AUTHOR_EMAIL=$(json_val_by_key "$COMMIT_JSON" ".commit.author.email")
AUTHOR_NAME=$(json_val_by_key "$COMMIT_JSON" ".commit.author.name")
debug "Author is: $AUTHOR_NAME <$AUTHOR_EMAIL> , date: $AUTHOR_DATE"

# Check for malformed names
#
if has_email_characters "$COMMITTER_NAME" ; then
    error "Malformed name for Committer: $COMMITTER_NAME"
fi
if has_email_characters "$AUTHOR_NAME" ; then
    if ! is_current_or_past_qc_email "$AUTHOR_EMAIL" || is_upstream_commit "$COMMIT" ; then
        error "This looks like a 3rd-party commit. Either commit message \
has 3rd-party patch tag(s) or Author: $AUTHOR_EMAIL is external."
    else
        warning "Unusual or external email for Author: $AUTHOR_NAME"
    fi
fi

# Check for valid OPEN_SOURCE email addresses
#
if [ "$REPO_EMAIL_TYPE" = "OPEN_SOURCE" ] ; then
    # Check committer address
    if ! in_allowlist "$COMMITTER_EMAIL" ; then
        if ! isOssValid "$COMMITTER_EMAIL" 'Committer' ; then
            error "Invalid email for Committer: $COMMITTER_EMAIL"
        fi
    fi

    # Check author address
    if ! in_allowlist "$AUTHOR_EMAIL" ; then
        if ! isOssValid "$AUTHOR_EMAIL" 'Author' ; then
            error "Invalid email for Author: $AUTHOR_EMAIL"
        fi
    fi
fi

# Check for valid PROPRIETARY email addresses
#
if [ "$REPO_EMAIL_TYPE" = "PROPRIETARY" ] ; then
    # Check committer address
    if ! in_allowlist "$COMMITTER_EMAIL" ; then
        if ! isPropValid "$COMMITTER_EMAIL" 'Committer' ; then
            error "Invalid email for Committer: $COMMITTER_EMAIL"
        fi
    fi

    # Check author address
    if ! in_allowlist "$AUTHOR_EMAIL" ; then
        if ! isPropValid "$AUTHOR_EMAIL" 'Author' ; then
            error "Invalid email for Author: $AUTHOR_EMAIL"
        fi
    fi
fi

exit $HAS_ERRORS
