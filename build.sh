#!/usr/bin/env bash

# If this script runs on MacOS set RUNS_ON_MACOS variable to TRUE

if [ -d virtual-environments ]; then
    (cd virtual-environments && git pull --ff-only)
else
    git clone https://github.com/actions/virtual-environments
fi

BUILD_DIRECTORY="./build"
TEMPLATE_DIRECTORY="./virtual-environments/images/linux"
UPSTREAM_TEMPLATE="${TEMPLATE_DIRECTORY}/ubuntu2004.json"
BUILDER_FILE="./builder-definition.json"
VARIABLES_FILE="./variables.json"


# AWS_MAX_ATTEMPTS defaults to 40; we need to wait much longer for the huge image we build.
export AWS_MAX_ATTEMPTS=800
# AWS_POLL_DELAY_SECONDS defaults to 2 to 5 seconds, depending on task. Set to 10s for very long wait times for image to be ready
export AWS_POLL_DELAY_SECONDS=10

mkdir -p "$BUILD_DIRECTORY"
rsync -aP --delete "${TEMPLATE_DIRECTORY}/" "${BUILD_DIRECTORY}/"

# Remove Azure VM Agent, use different command when executing on MacOS
if [[ $RUNS_ON_MACOS == 'TRUE' ]]; then
    echo "Runs on MacOS"
    ex '+g/waagent/d' -cwq "${BUILD_DIRECTORY}/scripts/installers/configure-environment.sh"
else
    sed '/waagent/ d' -i "${BUILD_DIRECTORY}/scripts/installers/configure-environment.sh"
fi

jq . < "$UPSTREAM_TEMPLATE" |
    jq --argjson builder "$(< "$BUILDER_FILE")" --argjson variables "$(< "$VARIABLES_FILE")" '. | .builders = [$builder] | .variables = $variables' |
    jq '. | del(."sensitive-variables") | del(.provisioners | last)' | jq '. += {"post-processors" : [{"type": "manifest", "output": "manifest.json"}]}' > "${BUILD_DIRECTORY}/packer-template.tmp.json"

(
    cd "$BUILD_DIRECTORY" || exit 1
    packer build packer-template.tmp.json
)
