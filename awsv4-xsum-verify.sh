#!/bin/bash

TESTDIR="${TESTDIR:-~/awsv4tests}"
DOWNLOADDIR="${TESTDIR}/downloads"
LOGDIR="${TESTDIR}/logs-$(date -Iseconds)"
CLI_BROKEN_VERSION="2.23.0"
CLI_BASE_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64"
CLI_LATEST_URL="${CLI_BASE_URL}.zip"
CLI_BROKEN_URL="${CLI_BASE_URL}-${CLI_BROKEN_VERSION}.zip"
CLI_BROKEN_ZIP="${DOWNLOADDIR}/cli-broken.zip"
CLI_LATEST_ZIP="${DOWNLOADDIR}/cli-latest.zip"
BROKEN_BASE_DIR="${TESTDIR}/brokencli"
LATEST_BASE_DIR="${TESTDIR}/latestcli"
BROKEN_BIN_DIR="${BROKEN_BASE_DIR}/bin"
LATEST_BIN_DIR="${LATEST_BASE_DIR}/bin"
BROKEN_INSTALL_DIR="${BROKEN_BASE_DIR}/install"
LATEST_INSTALL_DIR="${LATEST_BASE_DIR}/install"

BROKEN_AWS_BIN="${BROKEN_BIN_DIR}/aws"
LATEST_AWS_BIN="${LATEST_BIN_DIR}/aws"

TEST_LOG_FILE="${LOGDIR}/test.log"
TEST_CLI_LOG_FILE="${LOGDIR}/cli.log"

S3_BUCKET="s3v4checksumcheck"

echo_err()
{
    echo "$@" 1>&2;
}

error_exit()
{
    echo_err "$@";
    exit 1
}

check_https()
{
    local endpoint_url=$1
    if [[ ! $endpoint_url == https* ]]; then
        error_exit "aws endpoint url: $endpoint_url not https, this script will not run!"
    fi
}

validate_endpoint_url()
{
    if [[ -z "${AWS_ENDPOINT_URL}" ]]; then
        check_https $(aws configure get endpoint_url)
    else
         check_https "$AWS_ENDPOINT_URL"
    fi
}

setup_dir_tree()
{
    mkdir -p "$TESTDIR"
    mkdir -p "$DOWNLOADDIR"
    mkdir -p "$LOGDIR"
}


download_aws_cli()
{
    echo_err "Downloading clis..."
    curl "${CLI_LATEST_URL}" -o "${CLI_LATEST_ZIP}"
    curl "${CLI_BROKEN_URL}" -o "${CLI_BROKEN_ZIP}"
}


install_aws_cli()
{
    if [[ -f "${CLI_BROKEN_ZIP}" && -f "${CLI_LATEST_ZIP}" ]]; then
       echo_err "Skipping download of packages"
    else
        download_aws_cli
    fi

    rm -fr "$BROKEN_BASE_DIR" && unzip -q "$CLI_BROKEN_ZIP" -d "$BROKEN_BASE_DIR"
    rm -fr "$LATEST_BASE_DIR" && unzip -q "$CLI_LATEST_ZIP" -d "$LATEST_BASE_DIR"

    "$BROKEN_BASE_DIR/aws/install" -i "$BROKEN_INSTALL_DIR" -b "$BROKEN_BIN_DIR"
    "$LATEST_BASE_DIR/aws/install" -i "$LATEST_INSTALL_DIR" -b "$LATEST_BIN_DIR"
}

setup_aws_cli()
{
    if [[ ! -f "${BROKEN_AWS_BIN}" || ! -f "${LATEST_AWS_BIN}" ]]; then
        echo_err "AWS_CLI binaries missing installing them"
        install_aws_cli
    fi

    if ! "$BROKEN_AWS_BIN" --version > /dev/null 2>&1 ||
       ! "$LATEST_AWS_BIN" --version > /dev/null 2>&1; then
        install_aws_cli
    fi

    echo_err "AWS CLI setup valid, proceeding with checks!"
}


setup_bucket()
{
    local bucket_name=$1
    local aws_bin="${2:-$LATEST_AWS_BIN}"

    if [[ -z "$bucket_name" ]]; then
       error_exit "No bucket provided! exiting!"
    fi

    if "$aws_bin" s3api head-bucket --bucket "$bucket_name" > /dev/null 2>&1; then
        echo_err "using existing bucket $bucket_name"
    else
        echo_err "creating bucket $bucket_name"
        if ! "$aws_bin" s3api create-bucket --bucket "$bucket_name"; then
            error_exit "unable to create bucket!"
        fi
    fi
}

declare -a TEST_RESULTS
log_fail()
{
    echo_err "FAIL ❌: $@"
    TEST_RESULTS+=("FAIL: $@")
}

log_success()
{
    echo_err "SUCCESS ✅: $@"
    TEST_RESULTS+=("SUCCESS: $@")
}

test_s3_ops()
{
    local bucket_name="${1}"
    local aws_base_dir="${2}"
    local aws_bin="${2}/bin/aws"
    local object_key="test-single-object"
    local dummy_obj="$TESTDIR/dummyobject"

    cd "$aws_base_dir"
    echo_err "Testing put object without env setting"
    "$aws_bin" put-object --bucket="$bucket_name" --key "$object_key" --body "$dummy_obj" --debug >> "$CLI_LOG" 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "s3api put-object passed with checksum verification (server fixed!) for $aws_bin"
    else
        log_fail "s3api put-object failed with checksum verification (server failed!) for $aws_bin"
    fi

    echo_err "Testing put object without env setting"
    "$aws_bin" cp "$dummy_obj" s3://"$bucket_name"/"$object_key-cp" --debug >> "$CLI_LOG" 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "s3 cp passed with checksum verification (server fixed!) for $aws_bin"
    else
        log_fail "s3 cp failed with checksum verification (server failed!) for $aws_bin"
    fi

    echo_err "Testing put object with env setting"
    AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED "$aws_bin" put-object --bucket="$bucket_name" --key "$object_key" --body "$dummy_obj" --debug >> "$CLI_LOG" 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "s3api put-object passed without checksum verification (client fixed!) for $aws_bin"
    else
        log_fail "s3api put-object failed without checksum verification (client fix fail!!!!) for $aws_bin"
    fi

    echo_err "Testing put object with env setting"
    AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED  "$aws_bin" cp "$dummy_obj" s3://"$bucket_name"/"$object_key-cp" --debug >> "$CLI_LOG" 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "s3 cp passed without checksum verification (client fixed!) for $aws_bin"
    else
        log_fail "s3 cp failed without checksum verification (client fix fail!!!!) for $aws_bin"
    fi

    echo_err "All tests competed for $aws_bin"
}

create_dummy_object()
{
    if [[ ! -f "$TESTDIR/dummyobject" ]]; then
        dd if=/dev/zero of="$TESTDIR/dummyobject" bs=1M count=50
    fi
}

main()
{
    validate_endpoint_url
    setup_dir_tree
    setup_aws_cli
    setup_bucket "$S3_BUCKET"
    create_dummy_object
    test_s3_ops "$S3_BUCKET" "$BROKEN_BASE_DIR"
    test_s3_ops "$S3_BUCKET" "$LATEST_BASE_DIR"
}

main
