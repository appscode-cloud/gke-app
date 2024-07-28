FROM alpine AS builder

RUN set -x \
  && wget -q -O /ymerge https://github.com/gomodules/ymerge/releases/download/v0.1.0/ymerge-linux-amd64 \
  && chmod +x /ymerge

FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm/onbuild

COPY --from=builder /ymerge /bin/ymerge

COPY create_manifests.sh /bin/create_manifests.sh
