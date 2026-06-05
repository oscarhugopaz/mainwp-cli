#!/usr/bin/env bash
# scripts/release.sh - Tag a release, push it, and update the Homebrew tap.
#
# Usage: ./scripts/release.sh [version] [options]
#   version  defaults to auto-incrementing the patch number in bin/mainwp
#
# Steps:
#   1. Update MAINWP_VERSION in bin/mainwp
#   2. Run shellcheck, shfmt, and the smoke tests
#   3. Commit "Release <version>", push main, tag v<version>, push the tag
#   4. Download the release tarball from GitHub and compute its sha256
#   5. Rewrite url/sha256 in the tap's Formula/mainwp-cli.rb
#   6. Commit and push the tap update
#
# Options:
#   --tap-dir PATH    Path to homebrew-tap
#                    (default: ../homebrew-tap)
#   --brew-test      Run brew install/test/uninstall against the new
#                    formula before pushing the tap update
#   --yes, -y        Skip the confirmation prompt
#   --skip-tests     Skip the lint+smoke step (use when iterating)
#   --help, -h       Show this help

set -euo pipefail

usage() {
	cat <<'USAGE'
Usage:
  ./scripts/release.sh [version] [options]

Example:
  ./scripts/release.sh 0.3.0
  ./scripts/release.sh           # auto-increment patch from bin/mainwp

Options:
  --tap-dir PATH    Path to homebrew-tap
                    (default: ../homebrew-tap)
  --brew-test       Run brew install/test/uninstall against the new
                    formula before pushing the tap update
  --yes, -y         Skip the confirmation prompt
  --skip-tests      Skip shellcheck/shfmt/smoke (use when iterating)
  --help, -h        Show this help
USAGE
}

die() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

info() {
	printf '==> %s\n' "$*"
}

confirm() {
	local message="$1"
	if [[ "$ASSUME_YES" == true ]]; then
		return 0
	fi
	if [[ ! -t 0 ]]; then
		die "$message (re-run with --yes to continue non-interactively)"
	fi
	local reply
	read -r -p "$message [y/N] " reply
	case "$reply" in
	y | Y | yes | YES) return 0 ;;
	*) die "Release cancelled." ;;
	esac
}

require_clean_repo() {
	local repo_dir="$1" label="$2"
	if [[ -n "$(git -C "$repo_dir" status --short)" ]]; then
		git -C "$repo_dir" status --short >&2
		die "$label working tree is not clean. Commit or stash first."
	fi
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "'$1' is required."
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

# ---- option parsing ------------------------------------------------

VERSION=""
TAP_DIR=""
RUN_BREW_TEST=false
ASSUME_YES=false
SKIP_TESTS=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--tap-dir)
		[[ $# -ge 2 ]] || die "--tap-dir requires a path."
		TAP_DIR="$2"
		shift 2
		;;
	--brew-test)
		RUN_BREW_TEST=true
		shift
		;;
	--yes | -y)
		ASSUME_YES=true
		shift
		;;
	--skip-tests)
		SKIP_TESTS=true
		shift
		;;
	--help | -h)
		usage
		exit 0
		;;
	-*)
		die "Unknown option: $1"
		;;
	*)
		if [[ -z "$VERSION" ]]; then
			VERSION="$1"
			shift
		else
			die "Unexpected argument: $1"
		fi
		;;
	esac
done

# ---- auto-increment version ----------------------------------------

if [[ -z "$VERSION" ]]; then
	if [[ -f bin/mainwp ]]; then
		CURRENT=$(grep 'MAINWP_VERSION=' bin/mainwp | sed 's/MAINWP_VERSION="\([^"]*\)"/\1/')
		if [[ -n "$CURRENT" ]]; then
			IFS='.' read -r major minor patch <<<"$CURRENT"
			patch=$((patch + 1))
			VERSION="${major}.${minor}.${patch}"
			info "Auto-incrementing version: $CURRENT -> $VERSION"
		else
			die "Could not read MAINWP_VERSION from bin/mainwp"
		fi
	else
		die "bin/mainwp not found. Provide a version: ./scripts/release.sh <version>"
	fi
fi

VERSION="${VERSION#v}"
TAG="v$VERSION"
TAP_DIR="${TAP_DIR:-$REPO_ROOT/../homebrew-tap}"

# ---- preflight checks ----------------------------------------------

require_cmd git
require_cmd curl
require_cmd shasum

[[ -d "$TAP_DIR/.git" ]] || die "Tap repository not found at: $TAP_DIR"
[[ -f "$TAP_DIR/Formula/mainwp-cli.rb" ]] || die "Tap formula not found at: $TAP_DIR/Formula/mainwp-cli.rb"

CURRENT_BRANCH=$(git branch --show-current)
[[ "$CURRENT_BRANCH" == "main" ]] || die "Run releases from main (current branch: $CURRENT_BRANCH)."

TAP_BRANCH=$(git -C "$TAP_DIR" branch --show-current)
[[ "$TAP_BRANCH" == "main" ]] || die "Tap repo must be on main (current branch: $TAP_BRANCH)."

require_clean_repo "$REPO_ROOT" "mainwp-cli"
require_clean_repo "$TAP_DIR" "homebrew-tap"

info "Fetching tags from origin"
git fetch origin --tags

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	die "Local tag already exists: $TAG"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
	die "Remote tag already exists: $TAG"
fi

# ---- update version in source --------------------------------------

info "Setting MAINWP_VERSION=$VERSION in bin/mainwp"
RELEASE_VERSION="$VERSION" perl -0pi -e 's/MAINWP_VERSION="[^"]+"/MAINWP_VERSION="$ENV{RELEASE_VERSION}"/' bin/mainwp

# ---- lint and test -------------------------------------------------

if [[ "$SKIP_TESTS" == true ]]; then
	info "Skipping lint and smoke tests (--skip-tests)"
else
	require_cmd shellcheck
	require_cmd shfmt
	info "Running shellcheck"
	shellcheck bin/mainwp lib/*.sh lib/commands/*.sh
	info "Checking shfmt"
	shfmt -d bin lib
	info "Running smoke tests"
	./tests/smoke.sh
fi

# ---- commit, push, tag ---------------------------------------------

if [[ -n "$(git status --short)" ]]; then
	git add bin/mainwp
	git commit -m "Release $VERSION"
else
	info "No source changes to commit"
fi

RELEASE_COMMIT=$(git rev-parse --short HEAD)
confirm "Release $VERSION from commit $RELEASE_COMMIT and update the Homebrew tap?"

info "Pushing main"
git push origin main

info "Creating and pushing tag $TAG"
git tag "$TAG"
git push origin "$TAG"

# ---- compute sha256 of the release tarball -------------------------

info "Computing sha256 of $TAG tarball"
TARBALL_URL="https://github.com/oscarhugopaz/mainwp-cli/archive/refs/tags/$TAG.tar.gz"
TARBALL=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$TARBALL'" EXIT

SHA256=""
for attempt in 1 2 3 4 5 6 7 8 9 10; do
	if curl -fsSL -o "$TARBALL" "$TARBALL_URL"; then
		SHA256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
		[[ -n "$SHA256" ]] && break
	fi
	info "Tarball not yet available; retrying in $((attempt * 2))s..."
	sleep $((attempt * 2))
done
[[ -n "$SHA256" ]] || die "Failed to fetch $TARBALL_URL after 10 attempts"

info "sha256: $SHA256"

# ---- update the Homebrew formula -----------------------------------

FORMULA="$TAP_DIR/Formula/mainwp-cli.rb"
info "Updating $FORMULA"
perl -0pi -e "s|url \"https://github\\.com/oscarhugopaz/mainwp-cli/archive/refs/tags/v[^\"]+\"|url \"$TARBALL_URL\"|" "$FORMULA"
perl -0pi -e 's|sha256 "[a-f0-9]{64}"|sha256 "'"$SHA256"'"|' "$FORMULA"

# ---- optional: brew install/test/uninstall -------------------------

if [[ "$RUN_BREW_TEST" == true ]]; then
	require_cmd brew
	info "Testing Homebrew formula with brew"
	(
		cd "$TAP_DIR"
		brew install --build-from-source ./Formula/mainwp-cli.rb
		brew test ./Formula/mainwp-cli.rb
		brew uninstall mainwp-cli
	)
fi

# ---- commit and push the tap update --------------------------------

if [[ -n "$(git -C "$TAP_DIR" status --short)" ]]; then
	info "Committing tap update"
	git -C "$TAP_DIR" add Formula/mainwp-cli.rb
	git -C "$TAP_DIR" commit -m "mainwp-cli $VERSION"
	git -C "$TAP_DIR" push origin main
else
	info "Tap formula already up to date"
fi

info "Release $VERSION complete."
info "  - tag:        $TAG"
info "  - tarball:    $TARBALL_URL"
info "  - sha256:     $SHA256"
info "  - formula:    $FORMULA"
