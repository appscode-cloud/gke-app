# https://github.com/GoogleCloudPlatform/cloud-sdk-docker/blob/0767e4f8324c664412b39529d5641bab54a7ef5a/stable/Dockerfile#L1-L20

FROM debian:12 AS builder

ARG CLOUD_SDK_VERSION
ENV CLOUD_SDK_VERSION=$CLOUD_SDK_VERSION
ARG INSTALL_COMPONENTS

RUN apt-get update -qqy && apt-get -qqy upgrade && \
    apt-get install -qqy \
        curl \
        ca-certificates \
        lsb-release \
        gnupg && \
    export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    apt-get update && \
    apt-get install -y --no-install-recommends google-cloud-cli=${CLOUD_SDK_VERSION}-0 $INSTALL_COMPONENTS &&\
    rm -rf /root/.cache/pip/ && \
    find / -name '*.pyc' -delete && \
    find / -name '*__pycache__*' -delete

RUN set -x \
  && curl -fsSL -o /ymerge https://github.com/gomodules/ymerge/releases/download/v0.1.0/ymerge-linux-amd64 \
  && chmod +x /ymerge



FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm/onbuild

ARG SKIP_GCP
ENV SKIP_GCP=$SKIP_GCP

# https://github.com/GoogleCloudPlatform/cloud-sdk-docker/blob/0767e4f8324c664412b39529d5641bab54a7ef5a/stable/Dockerfile#L22C1-L39C25
COPY --from=builder /usr/lib/google-cloud-sdk /usr/lib/google-cloud-sdk

ENV PATH=$PATH:/usr/lib/google-cloud-sdk/bin
# Create a non-root user
RUN groupadd -r -g 1000 cloudsdk && \
    useradd -r -u 1000 -m -s /bin/bash -g cloudsdk cloudsdk
RUN if [ `uname -m` = 'x86_64' ]; then echo -n "x86_64" > /tmp/arch; else echo -n "arm" > /tmp/arch && \
    apt-get update -qqy && apt-get -qqy upgrade && apt-get install -qqy \
        python3-dev \
        python3-crcmod; fi;
RUN gcloud --version && \
    gcloud config set core/disable_usage_reporting true && \
    gcloud config set component_manager/disable_update_check true && \
    gcloud config set metrics/environment docker_image_stable && \
    rm -rf /root/.cache/pip/ && \
    find / -name '*.pyc' -delete && \
    find / -name '*__pycache__*' -exec rm -r {} \+
VOLUME ["/root/.config"]

COPY --from=builder /ymerge /bin/ymerge
COPY create_manifests.sh /bin/create_manifests.sh
COPY create_resources.sh /bin/create_resources.sh

RUN set -x \
  && apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl unzip \
  && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /tmp/*
