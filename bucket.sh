#!/bin/bash

set -xeo pipefail

export DEBIAN_FRONTEND="noninteractive"
export GCP_PROJECT="appscode-testing"
export GOOGLE_APPLICATION_CREDENTIALS=gcp-cred.json
export REGION="us-central1"

apt-get -y update
apt upgrade -y


#variables
BUCKET_NAME=""
PUBLIC_IP=""

install_gcloud() {
    echo "Installing Google Cloud SDK..."

    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    sudo apt-get install apt-transport-https ca-certificates gnupg -y
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

    sudo apt-get update && sudo apt-get install google-cloud-sdk -y >/dev/null
}
setup_gcloud(){
    apt-get install jq -y >/dev/null
    gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
    gcloud config set project "$GCP_PROJECT"
}

create_bucket() {
    RAND=$(head /dev/urandom | tr -dc 'a-z' | head -c 4)
    BUCKET_NAME="ace-bucket-$RAND"
    install_gcloud
    setup_gcloud
    echo "Creating bucket: $BUCKET_NAME in project: $GCP_PROJECT and region: ${REGION}"

    gsutil mb -p "$GCP_PROJECT" -c STANDARD -l "${REGION}" gs://"$BUCKET_NAME"/
    if [ $? -eq 0 ]; then
        echo "Bucket $BUCKET_NAME created successfully."
    else
        echo "Failed to create bucket $BUCKET_NAME."
        exit
    fi
}

webhook() {

    resp=$(curl -X POST https://appscode.com/marketplace/api/v1/marketplaces/aws/notification/resource?secret=vstktmgwvkxyrsrfmt5tr0i66qpxkeoeaejjr3gyxkeywkm/00kyfahzvxjkfyb/qn5tgxgt9s/xb6vsamhh4w== \
        -H "Content-Type: application/json" \
        -d '{
              "eventType": "BIND",
              "accountId": "'${ACCOUNT_ID}'",
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
                          "s3": {
                            "AWS_ACCESS_KEY_ID": "'${AWS_ACCESS_KEY_ID}'",
                            "AWS_SECRET_ACCESS_KEY": "'${AWS_SECRET_ACCESS_KEY}'"
                          }
                        },
                        "bucket": "s3://'${BUCKET_NAME}'?s3ForcePathStyle=true",
                        "endpoint": "s3.amazonaws.com",
                        "prefix": "ace",
                        "region": "'${REGION}'"
                      },
                      "provider": "s3"
                    },
                    "kubestash": {
                      "backend": {
                        "provider": "s3",
                        "s3": {
                          "bucket": "s3://'${BUCKET_NAME}'",
                          "endpoint": "s3.amazonaws.com",
                          "prefix": "ace",
                          "region": "'${REGION}'"
                        }
                      },
                      "retentionPolicy": "keep-1mo",
                      "schedule": "0 */2 * * *",
                      "storageSecret": {
                        "create": true
                      }
                    }
                  },
                  "initialSetup": {
                    "cluster": {
                      "region": "'${REGION}'"
                    },
                    "subscription": {
                      "aws": {
                        "customer-identifier": "demo-customer-identifier"
                      }
                    }
                  }
                }
              }
            }')

    link=$(echo ${resp} | jq -r '.link')
    if [ ${link} == "null" ]; then   exit ; fi

    mkdir new
    cd new
    curl -L "${link}" -o "archive.zip"
    unzip archive.zip >/dev/null
    cd ..
}

init(){
    create_bucket
}
init