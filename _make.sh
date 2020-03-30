#!/usr/bin/env bash

set -e

# Credits for initial version: https://github.com/robertpeteuil/build-lambda-layer-python

# AWS Lambda Layer Zip Builder for Python Libraries
#   This script is executed inside a docker container by the "build_layer.sh" script
#   It builds the zip file with files in lambda layers dir structure
#     /python/lib/pythonX.X/site-packages

scriptname=$(basename "$0")
scriptbuildnum="1.0.0"
scriptbuilddate="2020-03-29"

### Variables
CURRENT_DIR=$(reldir=$(dirname -- "$0"; echo x); reldir=${reldir%?x}; cd -- "$reldir" && pwd && echo x); CURRENT_DIR=${CURRENT_DIR%?x}
PYTHON="python${PYTHON_VER}"
ZIP_FILE="${NAME}_${PYTHON}.zip"

echo "Building layer: ${NAME} for ${PYTHON}"

# Delete build dir
rm -rf /tmp/build

# Create build dir
mkdir -p /tmp/build

# Create virtual environment and activate it
virtualenv -p $PYTHON /tmp/build
source /tmp/build/bin/activate

# Install requirements
pip install -r /temp/build/requirements.txt --no-cache-dir

# Create staging area in dir structure req for lambda layers
mkdir -p "/tmp/base/python/lib/${PYTHON}"

# Move dependancies to staging area
mv "/tmp/build/lib/${PYTHON}/site-packages" "/tmp/base/python/lib/${PYTHON}"

# Remove unused stuff
cd "/tmp/base/python/lib/${PYTHON}/site-packages"
echo "Original layer size: $(du -sh . | cut -f1)"
rm -rf easy-install*
rm -rf wheel*
rm -rf setuptools*
rm -rf virtualenv*
rm -rf pip*
find . -type d -name "tests" -exec rm -rf {} +
find . -type d -name "test" -exec rm -rf {} +
find . -type d -name "__pycache__" -exec rm -rf {} +
find -name "*.so" -not -path "*/PIL/*" | xargs strip
find -name "*.so.*" -not -path "*/PIL/*" | xargs strip
find . -name '*.pyc' -delete
if [[ -f "/temp/build/_clean.sh" ]]; then
    echo "Running custom cleaning script"
    source /temp/build/_clean.sh $PWD
fi
echo "Final layer size: $(du -sh . | cut -f1)"

# Delete .pyc files from staging area
cd "/tmp/base/python/lib/${PYTHON}"
find . -name '*.pyc' -delete

# Produce output
if [[ "$RAW_MODE" = true ]]; then
    # Copy raw files to layer directory
    rm -rf "${CURRENT_DIR}/layer"
    mkdir -p "${CURRENT_DIR}/layer"
    cp -R /tmp/base/. "${CURRENT_DIR}/layer"
    echo "Raw layer contents have been copied to the 'layer' subdirectory"
else
    # Add files from staging area to zip
    cd /tmp/base
    zip -q -r "${CURRENT_DIR}/${ZIP_FILE}" .
    echo "Zipped layer size: $(ls -s --block-size=1048576 ${CURRENT_DIR}/${ZIP_FILE} | cut -d' ' -f1)M"
fi

echo -e "\n${NAME} layer creation finished"