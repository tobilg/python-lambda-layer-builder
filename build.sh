#!/usr/bin/env bash

set -e

# Credits for initial version: https://github.com/robertpeteuil/build-lambda-layer-python

# AWS Lambda Layer Zip Builder for Python Libraries
#   requires: docker, _make.zip.sh, build_layer.sh (this script)
#     Launches docker container from lambci/lambda:build-pythonX.X image
#         where X.X is the python version (2.7, 3.6, 3.7) - defaults to 3.7
#     Executes build script "_make.zip.sh" within container to create zip
#         with libs specified in requirements.txt
#     Zip filename includes python version used in its creation

scriptname=$(basename "$0")
scriptbuildnum="1.0.1"
scriptbuilddate="2020-05-01"

# Used to set destination of zip
SUBDIR_MODE=""

# Display version
displayVer() {
  echo -e "${scriptname} v${scriptbuildnum} (${scriptbuilddate})"
}

# Display usage
usage() {
  echo -e "AWS Lambda Layer Builder for Python Libraries\n"
  echo -e "Usage: ${scriptname} [-p PYTHON_VER] [-n NAME] [-f] [-r] [-h] [-v]"
  echo -e "  -p PYTHON_VER\t: Python version to use: 2.7, 3.6, 3.7, 3.8 (default 3.7)"
  echo -e "  -n NAME\t: Name of the layer"
  echo -e "  -f REQ_PATH\t: Path to requirements file"
  echo -e "  -r\t\t: Raw mode, don't zip layer contents"
  echo -e "  -d\t\t: Don't install Python dependencies"
  echo -e "  -s\t\t: Don't strip .so files"
  echo -e "  -h\t\t: Help"
  echo -e "  -v\t\t: Display ${scriptname} version"
}

# Handle configuration
while getopts ":p:n:f:dsrhv" arg; do
  case "${arg}" in
    p)  PYTHON_VER=${OPTARG};;
    n)  NAME=${OPTARG};;
    f)  REQ_PATH=${OPTARG};;
    r)  RAW_MODE=true;;
    d)  NO_DEPS=true;;
    s)  STRIP=false;;
    h)  usage; exit;;
    v)  displayVer; exit;;
    \?) echo -e "Error - Invalid option: $OPTARG"; usage; exit;;
    :)  echo "Error - $OPTARG requires an argument"; usage; exit 1;;
  esac
done
shift $((OPTIND-1))

# Default Python to 3.7 if not set by CLI params
PYTHON_VER="${PYTHON_VER:-3.7}"
NAME="${NAME:-base}"
CURRENT_DIR=$(reldir=$(dirname -- "$0"; echo x); reldir=${reldir%?x}; cd -- "$reldir" && pwd && echo x); CURRENT_DIR=${CURRENT_DIR%?x}
BASE_DIR=$(basename $CURRENT_DIR)
PARENT_DIR=${CURRENT_DIR%"${BASE_DIR}"}
RAW_MODE="${RAW_MODE:-false}"
NO_DEPS="${NO_DEPS:-false}"
STRIP="${STRIP:-true}"

# Find location of requirements.txt
if [[ -f $REQ_PATH ]]; then
  if [[ ${REQ_PATH:0:1} != '/' ]]; then
    REQ_PATH="$(pwd)/${REQ_PATH}"
  fi
  echo "Using requirements.txt from command line input"
elif [[ -f "${CURRENT_DIR}/requirements.txt" ]]; then
  REQ_PATH="${CURRENT_DIR}/requirements.txt"
  echo "Using requirements.txt from script dir"
elif [[ -f "${PARENT_DIR}/requirements.txt" ]]; then
  REQ_PATH="${PARENT_DIR}/requirements.txt"
  SUBDIR_MODE="True"
  echo "Using requirements.txt from ../"
elif [[ -f "${PARENT_DIR}/function/requirements.txt" ]]; then
  REQ_PATH="${PARENT_DIR}/function/requirements.txt"
  SUBDIR_MODE="True"
  echo "Using requirements.txt from ../function"
else
  echo "Unable to find requirements.txt"
  exit 1
fi

# Find location of _clean.sh
if [[ -f "${CURRENT_DIR}/_clean.sh" ]]; then
  CLEAN_PATH="${CURRENT_DIR}/_clean.sh"
  echo "Using clean.sh from script dir"
elif [[ -f "${PARENT_DIR}/_clean.sh" ]]; then
  CLEAN_PATH="${PARENT_DIR}/_clean.sh"
  echo "Using clean.sh from ../"
elif [[ -f "${CURRENT_DIR}/$(dirname "${BASH_SOURCE[0]}")/_clean.sh" ]]; then
  CLEAN_PATH="${PARENT_DIR}/$(dirname "${BASH_SOURCE[0]}")/_clean.sh"
  echo "Using clean.sh from ../$(dirname "${BASH_SOURCE[0]}")"
else
  echo "Using default cleaning step"
fi

if [[ "$RAW_MODE" = true ]]; then
  echo "Using RAW mode"
else
  echo "Using ZIP mode"
fi

# Run build
docker run --rm -e PYTHON_VER="$PYTHON_VER" -e NAME="$NAME" -e RAW_MODE="$RAW_MODE" -e NO_DEPS="$NO_DEPS" -e STRIP="$STRIP" -e PARENT_DIR="${PARENT_DIR}" -e SUBDIR_MODE="$SUBDIR_MODE" -v "$CURRENT_DIR":/var/task -v "$REQ_PATH":/temp/build/requirements.txt -v "$CLEAN_PATH":/temp/build/_clean.sh "lambci/lambda:build-python${PYTHON_VER}" bash /var/task/_make.sh

# Move ZIP to parent dir if SUBDIR_MODE set
if [[ "$SUBDIR_MODE" ]]; then
  ZIP_FILE="${NAME}_python${PYTHON_VER}.zip"
  # Make backup of zip if exists in parent dir
  if [[ -f "${PARENT_DIR}/${ZIP_FILE}" ]]; then
    mv "${PARENT_DIR}/${ZIP_FILE}" "${PARENT_DIR}/${ZIP_FILE}.bak"
  fi
  if [[ "$RAW_MODE" != true ]]; then
    mv "${CURRENT_DIR}/${ZIP_FILE}" "${PARENT_DIR}"
  fi
fi