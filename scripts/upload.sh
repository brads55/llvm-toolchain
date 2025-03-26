#!/bin/bash

set -eu

PROJECT=${1-}
CURDIR="$(realpath "$(dirname "$0")")"

. $CURDIR/common.sh

if [ -z "$PROJECT" ]; then
  echo "Must specify project" >&2
  exit 1
fi

if ( ! git -C "$ROOT_DIR" diff --quiet ); then
  echo "Working tree is dirty, commit changes" >&2
  exit 1
fi

if [ ! -e "$RELEASE_FILE"  ]; then
  echo "$RELEASE_FILE does not exist" >&2
  exit 1
fi

AWS_VENV="$ROOT_DIR/build/aws-venv"
AWS="$AWS_VENV/bin/aws"

if [ ! -e "$AWS" ]; then
  python3 -mvenv $AWS_VENV
  $AWS_VENV/bin/python -m pip install --upgrade pip awscli
fi

if ( ! $AWS sts get-caller-identity >/dev/null 2>&1); then
  $AWS configure
fi

VERSION=$(git log -1 --pretty=format:%H $PROJECT)

$AWS s3 cp "$RELEASE_FILE" s3://bazel-assets/$PROJECT/${OS}_${ARCH}/$VERSION.tar.gz
