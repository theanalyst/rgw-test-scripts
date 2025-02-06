#!/bin/bash

TESTDIR="${TESTDIR:-~/awsv4tests}"
DOWNLOADDIR="${TESTDIR}/downloads"
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
       !  "$LATEST_AWS_BIN" --version > /dev/null 2>&1; then
        install_aws_cli
    fi

    echo_err "AWS CLI setup valid, proceeding with checks!"
}

main()
{
    validate_endpoint_url
    setup_dir_tree
    setup_aws_cli
}

main
