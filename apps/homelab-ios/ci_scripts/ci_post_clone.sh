#!/bin/sh
# Xcode Cloud runs this after cloning, before it builds.
#
# The .xcodeproj is generated from project.yml and gitignored (ADR-0003's
# amendment), so it does not exist in a fresh clone and Xcode Cloud would have
# nothing to build without this.
#
# Note the ordering caveat: this makes *builds* work, but Xcode Cloud's initial
# workflow setup in App Store Connect scans the repository for a project before
# any script has run. If setup cannot see one, generate it locally once
# (`make ios-generate` from apps/homelab-menubar) and point the workflow at it.
set -eu

brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH/apps/homelab-ios"
xcodegen generate

echo "Generated $(pwd)/Homelab.xcodeproj"
