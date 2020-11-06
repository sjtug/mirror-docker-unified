#!/bin/bash

fatal() {
  echo "$1"
  exit 1
}

warn() {
  echo "$1"
}

# $LUG_source can either be <ubuntu> or <debian>
RSYNCSOURCE=$LUG_source

# Define where you want the mirror-data to be on your mirror
BASEDIR=$LUG_path

if [ ! -d ${BASEDIR} ]; then
  warn "${BASEDIR} does not exist yet, trying to create it..."
  mkdir -p ${BASEDIR} || fatal "Creation of ${BASEDIR} failed."
fi

# Download packages before .gz files
rsync --recursive --times --links --safe-links --hard-links \
  --stats \
  --exclude "Packages*" --exclude "Sources*" \
  --exclude "Release*" --exclude "InRelease" \
  --partial-dir=.rsync-partial \
  ${RSYNCSOURCE} ${BASEDIR} || fatal "First stage of sync failed."

# After successfully downloading packages, start to update .gz files
rsync --recursive --times --links --safe-links --hard-links \
  --stats --delete --delete-after \
  --partial-dir=.rsync-partial \
  ${RSYNCSOURCE} ${BASEDIR} || fatal "Second stage of sync failed."

