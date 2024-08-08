#!/bin/bash

set -xeo pipefail

export DEBIAN_FRONTEND="noninteractive"
export GCP_PROJECT="appscode-testing"
export GOOGLE_APPLICATION_CREDENTIALS=gcp-cred.json
export REGION="us-central1"

apt-get -y update
apt upgrade -y


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
    fi
}

init(){
    create_bucket
}
init