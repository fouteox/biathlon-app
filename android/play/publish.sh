#!/usr/bin/env bash
# Sends a release bundle to Google Play's internal testing track, with the store listings of
# play/listings, in one edit of the Google Play Developer API: the edit is created, filled, then
# committed, so Play applies all of it or none of it
# (https://developers.google.com/android-publisher/edits).
#
# Usage: publish.sh <bundle.aab>, with PLAY_ACCESS_TOKEN an OAuth 2.0 access token of the
# androidpublisher scope.
set -euo pipefail

bundle=$1
package=com.fouteox.biathlon
api=https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package
upload=https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package
listings=$(dirname "$0")/listings

call() {
  curl --fail-with-body --silent --show-error --header "Authorization: Bearer $PLAY_ACCESS_TOKEN" "$@"
}

edit=$(call --request POST "$api/edits" | jq --raw-output --exit-status .id)

version=$(call --request POST --header "Content-Type: application/octet-stream" --data-binary "@$bundle" \
  "$upload/edits/$edit/bundles?uploadType=media" | jq --raw-output --exit-status .versionCode)

call --request PUT --header "Content-Type: application/json" \
  --data "$(jq --null-input --arg version "$version" \
    '{track: "internal", releases: [{versionCodes: [$version], status: "completed"}]}')" \
  "$api/edits/$edit/tracks/internal" >/dev/null

# One listing per language folder, its texts without their files' final newline.
for folder in "$listings"/*/; do
  language=$(basename "$folder")
  call --request PUT --header "Content-Type: application/json" \
    --data "$(jq --null-input --arg language "$language" \
      --rawfile title "$folder/title.txt" \
      --rawfile short "$folder/short-description.txt" \
      --rawfile full "$folder/full-description.txt" \
      '{language: $language, title: ($title | rtrimstr("\n")),
        shortDescription: ($short | rtrimstr("\n")), fullDescription: ($full | rtrimstr("\n"))}')" \
    "$api/edits/$edit/listings/$language" >/dev/null
done

call --request POST "$api/edits/$edit:commit" >/dev/null
echo "Version $version is on the internal testing track."
