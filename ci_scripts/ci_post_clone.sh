#!/bin/sh
# Xcode Cloud runs this script after cloning the repository, from ci_scripts/.
# The Xcode project is not versioned: generate it from project.yml with XcodeGen.
set -eu

brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen
