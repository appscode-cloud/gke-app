#!/bin/bash

set -exo pipefail

export GCP_PROJECT=${GCP_PROJECT:-"appscode-testing"}
export GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS:-gcp-cred.json}
export REGION=${REGION:-us-central1}

#variables
BUCKET_NAME=""
PUBLIC_IP=""
RAND=$(head /dev/urandom | tr -dc 'a-z' | head -c 4)
GOOGLE_APPLICATION_CREDENTIALS_STRING=$(cat $GOOGLE_APPLICATION_CREDENTIALS | base64 -w 0)

function ace::gcp::install_gcloud() {
  echo "Installing Google Cloud SDK..."

  export DEBIAN_FRONTEND="noninteractive"
  apt-get -y update
  apt upgrade -y
  apt-get install jq unzip -y >/dev/null

  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  sudo apt-get install apt-transport-https ca-certificates gnupg -y
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

  sudo apt-get update && sudo apt-get install google-cloud-sdk -y >/dev/null
}

function ace::gcp::setup_gcloud() {
  gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
  gcloud config set project "$GCP_PROJECT"
}

function ace::gcp::create_bucket() {
  BUCKET_NAME="ace-bucket-$RAND"
  echo "Creating bucket: $BUCKET_NAME in project: $GCP_PROJECT and region: ${REGION}"

  gsutil mb -p "$GCP_PROJECT" -c STANDARD -l "${REGION}" gs://"$BUCKET_NAME"/
  if [ $? -eq 0 ]; then
    echo "Bucket $BUCKET_NAME created successfully."
  else
    echo "Failed to create bucket $BUCKET_NAME."
    exit
  fi
}

function ace::gcp::create_static_public_ip() {
  PUBLIC_IP=$(gcloud compute addresses create "ace-ip-$RAND" --global --ip-version IPV4 --format="get(address)")
}

function ace::gcp::finalize_installer() {
  resp=$(curl -X POST https://appscode.com/marketplace/api/v1/marketplaces/gcp/notification/resource?secret=72iuueq9sbiomgxgcbdbehfbhai1fqgg4dlpndxsh4rstoptvbvrkje88ob6cdkuv16nbpoym1/griswiujgga== \
    -H "Content-Type: application/json" \
    -d '{
              "eventType": "BIND",
              "bindingInfo": {
                "installerID": "'${INSTALLER_ID}'",
                "options": {
                  "infra": {
                    "dns": {
                      "provider": "none",
                      "targetIPs": ["'${PUBLIC_IP}'"]
                    },
                    "cloudServices": {
                      "objstore": {
                        "auth": {
                          "gcs": {
                            "GOOGLE_PROJECT_ID": "'${GCP_PROJECT}'",
                            "GOOGLE_SERVICE_ACCOUNT_JSON_KEY": "'${GOOGLE_APPLICATION_CREDENTIALS_STRING}'"
                          }
                        },
                        "bucket": "gs://'${BUCKET_NAME}'",
                        "prefix": "ace"
                      },
                      "provider": "gcs"
                    },
                    "kubestash": {
                      "backend": {
                        "gcs": {
                          "bucket": "gs://'${BUCKET_NAME}'",
                          "prefix": "ace"
                        },
                        "provider": "gcs"
                      },
                      "retentionPolicy": "keep-1mo",
                      "schedule": "0 */2 * * *",
                      "storageSecret": {
                        "create": true
                      }
                    }
                  }
                }
              }
            }')

  link=$(echo ${resp} | jq -r '.link')
  if [ ${link} == "null" ]; then exit; fi

  curl -L "${link}" -o "archive.zip"
  unzip archive.zip >/dev/null
}

function ace::gcp::init() {
  # ace::gcp::install_gcloud
  ace::gcp::setup_gcloud
  ace::gcp::create_bucket
  ace::gcp::create_static_public_ip
  ace::gcp::finalize_installer
}
