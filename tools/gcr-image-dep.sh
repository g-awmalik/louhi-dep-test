#!/bin/bash

IFS=$'\n\t'
set -eou pipefail
MODE="DRYRUN"

if [[ "$#" -lt 2 || "${1}" == '-h' || "${1}" == '--help' ]]; then
  cat >&2 <<"EOF"
gcr-image-dep.sh deprecates all non-latest config-sdk images once a new
version is released. It does so by prefixing the existing image tags with
"deprecated-".
This script is meant to be run by the Louhi service account.
USAGE:
  gcr-image-dep.sh REPOSITORY CURRENT_VERSION [DEPERECATE]
EOF
  exit 1
fi

if [[ "$#" -eq 2 ]]; then
  echo ">>> executing in DRY RUN mode; use the DEPRECATE arg for deprecating the images <<<"
elif [[ "$#" -eq 3 && "${3}" == 'DEPRECATE' ]]; then
  MODE="DEPRECATE"
fi

main(){
  local cnt=0
  IMAGE="${1}"
  CURRENT_VERSION="${2}"

  # the number of images to skip deprecation prior to the current image
  # context: http://go/im-louhi-updates-dep
  local num_current_images=3

  # get the creation date of the current image and format it to a timestamp string
  # that can be used for comparison
  local curr_image_timestamp=$(gcloud container images list-tags ${IMAGE} \
    --filter="tags=(public-image-${CURRENT_VERSION},${CURRENT_VERSION})" --format='get(timestamp.datetime)' | sed 's/ /T/g')

  if [[ -z "$curr_image_timestamp" ]]; then
    echo "config-sdk image with version ${CURRENT_VERSION} not found." >&2
    return 1
  fi

  # we're only looking for tags that don't have the "deprecated-" prefix
  for digest_tags in $(gcloud container images list-tags ${IMAGE} --limit=999999 --sort-by=~TIMESTAMP \
    --filter="-tags=public-image-${CURRENT_VERSION} AND -tags ~ ^deprecated-public-image AND timestamp.datetime<${curr_image_timestamp}" --format='get[separator=","](digest,tags[0])'); do
    let cnt+=1
    if [ $cnt -lt $num_current_images ]; then
      continue
    fi

    if [[ "$MODE" == "DRYRUN" ]]; then
      echo "to deprecate:" $digest_tags
    elif [[ "$MODE" == "DEPRECATE" ]]; then
      (
        IFS=',' read -a split_digest_tag <<< $digest_tags
        dep_tag_prefix="deprecated-"
        if [[ ${split_digest_tag[1]} != public-image-* ]]; then
          dep_tag_prefix="deprecated-public-image-"
        fi

        gcloud container images untag "${IMAGE}:${split_digest_tag[1]}" --quiet
        gcloud container images add-tag "${IMAGE}@${split_digest_tag[0]}" "${IMAGE}:${dep_tag_prefix}${split_digest_tag[1]}" --quiet

        echo "Deprecated:" ${IMAGE}:${split_digest_tag[1]}
      )
    fi
  done
  if [[ $cnt -lt $num_current_images ]]; then
    echo "No images to deprecate in ${IMAGE}." >&2
    return 0
  fi

  let dep_cnt=cnt-num_current_images+1
  echo "Deprecated ${dep_cnt} images in ${IMAGE}." >&2
}

main "${1}" "${2}"
