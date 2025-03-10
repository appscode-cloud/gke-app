#!/bin/bash
#
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eox pipefail

for i in "$@"; do
  case $i in
    --mode=*)
      mode="${i#*=}"
      shift
      ;;
    *)
      >&2 echo "Unrecognized flag: $i"
      exit 1
      ;;
  esac
done

[[ -z "$NAME" ]] && echo "NAME must be set" && exit 1
[[ -z "$NAMESPACE" ]] && echo "NAMESPACE must be set" && exit 1

echo "Creating the manifests for the kubernetes resources that build the application \"$NAME\""

data_dir="/data"
manifest_dir="$data_dir/manifest-expanded"
mkdir -p "$manifest_dir"

if [[ "$mode" = "test" ]]; then
  test_data_dir="/data-test"
  mkdir -p "/data-test"
fi

function extract_manifest() {
  data=$1
  extracted="$data/extracted"
  data_chart="$data/chart"
  mkdir -p "$extracted"

  # Expand the chart template.
  if [[ -d "$data_chart" ]]; then
    for chart in $(find "$data_chart" -maxdepth 1 -type f -name "*.tar.gz"); do
      chart_manifest_file=$(basename "$chart" | sed 's/.tar.gz$//')
      mkdir "$extracted/$chart_manifest_file"
      tar xfC "$chart" "$extracted/$chart_manifest_file"
    done
  fi
}

extract_manifest "$data_dir"

# Overwrite the templates using the test templates
if [[ "$mode" = "test" ]]; then
  extract_manifest "$test_data_dir"

  if [[ ! -e "$data_dir/extracted" ]]; then
    echo "$LOG_SMOKE_TEST No test charts declared."
    continue
  fi

  overlay_test_files.py \
    --manifest "$data_dir/extracted" \
    --test_manifest "$test_data_dir/extracted" |
    awk '{print "SMOKE_TEST "$0}'
fi

# Log information and, at the same time, catch errors early and separately.
# This is a work around for the fact that process and command substitutions
# do not propagate errors.
echo "=== values.yaml ==="
/bin/print_config.py --output=yaml
echo "==================="

skipGCP=$(/bin/print_config.py --output=yaml |
  python -c 'import sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(y["skipGCP"])')
SKIP_GCP=false
if [ "$skipGCP" = "true" ]; then
  SKIP_GCP=true
fi

echo "=== prepare reporting secret values ==="
REPORTING_SECRET=$(/bin/print_config.py --output=yaml |
  python -c 'import sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(y["reportingSecret"])')
cat >plugin-config.yaml <<EOF
vcluster:
  plugin:
    ace:
      config:
        reportingSecret: "${REPORTING_SECRET}"
EOF
cat >reportingsecret-values.yaml <<EOF
helm:
  releases:
    ace:
      enabled: true
      values:
        platform-api:
          settings:
            skipGCPMarketplaceMeteringService: ${SKIP_GCP}
            secretName:
              gcpMarketplaceReportingSecret: "${REPORTING_SECRET}"
EOF

echo "=== download installer archive ==="
INSTALLER_URL=$(/bin/print_config.py --output=yaml |
  python -c 'import sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(y["installerURL"])')

wget $INSTALLER_URL
tar -xzvf archive.tar.gz

source ./env.sh
export INSTALLER_ID=$(echo $INSTALLER_URL | awk -F '[/]' '{ print $8 }')

if [ "$SKIP_GCP" = true ]; then
  export PUBLIC_IP=$(/bin/print_config.py --output=yaml |
    python -c 'import sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(y["publicIP"])')
  export BUCKET_NAME=$(/bin/print_config.py --output=yaml |
    python -c 'import sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(y["bucketName"])')

  source /bin/create_resources.sh
  ace::gcp::setup_gcloud
  ace::gcp::finalize_installer
else
  source /bin/create_resources.sh
  ace::gcp::setup_gcloud
  ace::gcp::create_bucket
  ace::gcp::create_static_public_ip
  ace::gcp::finalize_installer
fi

# Run helm expansion.
for chart in "$data_dir/extracted"/*; do
  /bin/print_config.py --output=yaml |
    python -c 'import sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(yaml.dump(y["flux2"], default_flow_style=False))' >flux-overrides.yaml
  ymerge ./flux-values.yaml ./flux-overrides.yaml >flux-merged.yaml

  echo "=== flux-merged.yaml ==="
  cat flux-merged.yaml
  echo "==================="

  /bin/print_config.py --output=yaml |
    python -c 'import sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(yaml.dump(y["ace-installer"], default_flow_style=False))' >installer-overrides.yaml
  ymerge ./values.yaml ./reportingsecret-values.yaml "$chart/chart/installer-static-overrides.yaml" ./installer-overrides.yaml >installer-merged.yaml

  echo "=== installer-merged.yaml ==="
  cat ./installer-merged.yaml
  echo "==================="

  chart_manifest_file=$(basename "$chart" | sed 's/.tar.gz$//').yaml
  helm template "$NAME" "$chart/chart" \
    --namespace="$NAMESPACE" \
    --include-crds \
    --values=./plugin.yaml \
    --values=./plugin-config.yaml \
    --values=./ace-mp.yaml \
    --values=<(/bin/print_config.py --output=yaml) \
    --values="$chart/chart/static-overrides.yaml" \
    --set-file vcluster.experimental.deploy.vcluster.helm[0].values=./flux-merged.yaml \
    --set-file vcluster.experimental.deploy.vcluster.helm[1].values=./installer-merged.yaml \
    >"$manifest_dir/$chart_manifest_file"

  if [[ "$mode" != "test" ]]; then
    process_helm_hooks.py \
      --manifest "$manifest_dir/$chart_manifest_file"
  else
    process_helm_hooks.py --deploy_tests \
      --manifest "$manifest_dir/$chart_manifest_file"
  fi

  ensure_k8s_apps_labels.py \
    --manifest "$manifest_dir/$chart_manifest_file" \
    --appname "$NAME"
done
