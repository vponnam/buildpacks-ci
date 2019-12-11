#!/usr/bin/env bash

set -euo pipefail

generate_diff() {
  >&2 echo "Generating diff"

  version="$(cat version/number)"

  tar xf pack/*-linux.tgz -C pack

  gcloud --no-user-output-enabled auth activate-service-account --key-file <(echo "$GCP_SERVICE_ACCOUNT_KEY")
  gcloud --no-user-output-enabled --quiet auth configure-docker

  released_cnb_details="$(./pack/pack --no-color inspect-builder "cloudfoundry/cnb:$TAG" | grep -v 'Cannot connect to the Docker daemon')"
  rc_cnb_details="$(./pack/pack --no-color inspect-builder "gcr.io/cf-buildpacks/builder-rcs:${version}-${TAG}" | grep -v 'Cannot connect to the Docker daemon')"

  set +e
  diff="$(diff -u <(echo "$released_cnb_details") <(echo "$rc_cnb_details") | tail -n +3)"
  set -e

  >&2 echo -e "Diff:\n$diff"
  echo "$diff"
}

create_or_get_story() {
  filter="label:$TAG AND label:builder-release AND -state:accepted"
  response="$(curl -s -X GET \
    -H "X-TrackerToken: $TRACKER_API_TOKEN" \
    -H "Accept: application/json" \
    -G --data-urlencode "filter=$filter" \
    "https://www.pivotaltracker.com/services/v5/projects/$TRACKER_PROJECT_ID/stories"
  )"

  if [[ "$response" == '[]' ]]; then
    >&2 echo "Story does not exist"

    response="$(curl -s -X POST \
      -H "X-TrackerToken: $TRACKER_API_TOKEN" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"Release builder $TAG\", \"labels\": [\"$TAG\", \"builder-release\"]}" \
      "https://www.pivotaltracker.com/services/v5/projects/$TRACKER_PROJECT_ID/stories"
    )"

    id="$(echo "$response" | jq -r .id)"

    >&2 echo "Story created with id #$id"
    echo "$id"
  elif [[ "$(echo "$response" | jq -r '. | length')" == 1 ]]; then
    id="$(echo "$response" | jq -r .[0].id)"

    >&2 echo "Story found with id #$id"
    echo "$id"
  else
    >&2 printf "Invalid stories response:\n%s\n" "$response"
    exit 1
  fi
}

update_story() {
  story_id=$1
  description=$2

  >&2 echo "Converting description to JSON-wrapped markdown"

  markdown_description="$(printf '```diff\n%s\n```' "$description")"
  jq -n --arg description "$markdown_description" '{description: $description}' > story-data

  >&2 echo "Updating story description"

  curl -s -X PUT \
    -H "X-TrackerToken: $TRACKER_API_TOKEN" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d @story-data \
    "https://www.pivotaltracker.com/services/v5/projects/$TRACKER_PROJECT_ID/stories/$story_id"
}

main() {
  diff="$(generate_diff)"
  story_id="$(create_or_get_story)"
  update_story "$story_id" "$diff"
}

main
