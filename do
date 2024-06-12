#!/usr/bin/env bash

set -eu -o pipefail

reportDir="test-reports"
GORELEASER_VERSION="v1.26.2"

# This variable is used, but shellcheck can't tell.
# shellcheck disable=SC2034
help_build="Build the Go binaries and archives"
build() {
    set -x

    [[ -f ./bin/goreleaser ]] || install-go-bin "github.com/goreleaser/goreleaser@latest"

    VERSION="${GORELEASER_VERSION}" \
    BUILD_VERSION="${BUILD_VERSION:-dev}" ./bin/goreleaser \
        --clean \
        --config "${BUILD_CONFIG:-./.goreleaser/binaries.yaml}" \
        --skip=validate "$@"

    echo "${BUILD_VERSION:-dev}" | tee ./target/version.txt
}

# This variable is used, but shellcheck can't tell.
# shellcheck disable=SC2034
help_dev_binary="Build and push the Docker images and manifests"
images() {
    set -x

    [[ -f ./bin/goreleaser ]] || install-go-bin "github.com/goreleaser/goreleaser@latest"

    SKIP_PUSH="${SKIP_PUSH:-true}" \
        VERSION="${GORELEASER_VERSION}" \
        ./bin/goreleaser \
        --clean \
        --config "${BUILD_CONFIG:-./.goreleaser/dockers.yaml}" \
        --skip=validate "${@}"
}

# This variable is used, but shellcheck can't tell.
# shellcheck disable=SC2034
help_lint="Run golanci-lint to lint go files."
lint() {
    if [ ! -d "./bin" ]; then
        install-devtools
    fi
    eval "./bin/golangci-lint run ${1:-}"
}

# This variable is used, but shellcheck can't tell.
# shellcheck disable=SC2034
help_lint_report="Run golanci-lint to lint Go files and generate an XML report."
lint-report() {
    output="${reportDir}/lint.xml"
    echo "Storing results as JUnit XML in ${output}" >&2
    mkdir -p "${reportDir}"

    lint "--timeout 5m --out-format junit-xml | tee ${output}"
}

# This variable is used, but shellcheck can't tell.
# shellcheck disable=SC2034
help_go_mod_tidy="Run 'go mod tidy' to clean up module files."
go-mod-tidy() {
    go mod tidy -v
}

# Attempt to download go binary tools from github correctly
# go binary releases are somewhat consistent thanks to goreleaser
# however they're not actually that consistent, so this is a pain
# if this is causing more problems than it solves, throw it away
install-github-binary() {
    local org=$1     # github org
    local repo=$2    # github repo == binary name
    local vs=$3      # version separator in tarball filename
    local winext=$4  # archive extension on windows
    local version=$5 # desired version number

    if ./bin/$repo --version | grep "$version" >/dev/null; then
        return
    fi

    local os=$(go env GOHOSTOS)
    local arch=$(go env GOARCH)

    local ext='.tar.gz'
    if [[ "$os" = "windows" ]]; then
        local ext="$winext"
    fi

    local unpack='tar xvzf'
    if [[ "$ext" = ".zip" ]]; then
        local unpack='unzip'
    fi

    local tmp=$(mktemp -d ${TMPDIR:-/tmp/}do-install-github-binary.XXXXXX)
    trap "{ rm -rf $tmp; }" EXIT

    set -x
    mkdir -p ./bin

    curl --fail --location --output "$tmp/download" \
        "https://github.com/$org/$repo/releases/download/v${version}/${repo}${vs}${version}${vs}${os}${vs}${arch}${ext}"

    pushd "$tmp"
    $unpack "$tmp/download"
    popd

    local binary=$(find "$tmp" -name "$repo*" -type f)
    chmod +x "$binary"
    mv "$binary" ./bin/
}

install-go-bin() {
    for pkg in "${@}"; do
        GOBIN="${PWD}/bin" go install "${pkg}" &
    done
    wait
}

help_install_devtools="Install tools that other tasks expect into ./bin"
install-devtools() {
    install-github-binary golangci golangci-lint '-' '.zip' 1.55.2
    install-github-binary gotestyourself gotestsum '_' '.tar.gz' 1.10.0

    if [[ "${CI:-}" == "true" ]]; then
        echo "Run GoReleaser via bash script in CI"
        curl -sfL https://goreleaser.com/static/run -o ./bin/goreleaser --create-dirs && chmod +x ./bin/goreleaser
    else
        echo "Installing GoReleaser via go install"
        install-go-bin "github.com/goreleaser/goreleaser@latest"
    fi
}

help-text-intro() {
    echo "
DO

A set of simple repetitive tasks that adds minimally
to standard tools used to build and test the service.
(e.g. go and docker)
"
}

### START FRAMEWORK ###
# Do Version 0.0.4

# This variable is used, but shellcheck can't tell.
# shellcheck disable=SC2034
help_completion="Print shell completion function for this script.

Usage: $0 completion SHELL"
completion() {
    local shell
    shell="${1-}"

    if [ -z "$shell" ]; then
        echo "Usage: $0 completion SHELL" 1>&2
        exit 1
    fi

    case "$shell" in
    bash)
        (
            echo
            echo '_dotslashdo_completions() { '
            # shellcheck disable=SC2016
            echo '  COMPREPLY=($(compgen -W "$('"$0"' list)" "${COMP_WORDS[1]}"))'
            echo '}'
            echo 'complete -F _dotslashdo_completions '"$0"
        )
        ;;
    zsh)
        cat <<EOF
_dotslashdo_completions() {
  local -a subcmds
  subcmds=()
  DO_HELP_SKIP_INTRO=1 $0 help | while read line; do
EOF
        cat <<'EOF'
    cmd=$(cut -f1  <<< $line)
    cmd=$(awk '{$1=$1};1' <<< $cmd)

    desc=$(cut -f2- <<< $line)
    desc=$(awk '{$1=$1};1' <<< $desc)

    subcmds+=("$cmd:$desc")
  done
  _describe 'do' subcmds
}

compdef _dotslashdo_completions do
EOF
        ;;
    fish)
        cat <<EOF
complete -e -c do
complete -f -c do
for line in (string split \n (DO_HELP_SKIP_INTRO=1 $0 help))
EOF
        cat <<'EOF'
  set cmd (string split \t $line)
  complete -c do  -a $cmd[1] -d $cmd[2]
end
EOF
        ;;
    esac
}

list() {
    declare -F | awk '{print $3}'
}

# This variable is used, but shellcheck can't tell.
# shellcheck disable=SC2034
help_help="Print help text, or detailed help for a task."
help() {
    local item
    item="${1-}"
    if [ -n "${item}" ]; then
        local help_name
        help_name="help_${item//-/_}"
        echo "${!help_name-}"
        return
    fi

    if [ -z "${DO_HELP_SKIP_INTRO-}" ]; then
        type -t help-text-intro >/dev/null && help-text-intro
    fi
    for item in $(list); do
        local help_name text
        help_name="help_${item//-/_}"
        text="${!help_name-}"
        [ -n "$text" ] && printf "%-30s\t%s\n" "$item" "$(echo "$text" | head -1)"
    done
}

case "${1-}" in
list) list ;;
"" | "help") help "${2-}" ;;
*)
    if ! declare -F "${1}" >/dev/null; then
        printf "Unknown target: %s\n\n" "${1}"
        help
        exit 1
    else
        "$@"
    fi
    ;;
esac
### END FRAMEWORK ###
