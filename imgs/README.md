helm template oci://ghcr.io/appscode-charts/cert-manager-csi-driver-cacerts \
  --version v2024.7.28 \
  --values=/Users/tamal/go/src/go.bytebuilders.dev/gke-app/imgs/cert-manager-csi-driver-cacerts.yaml

helm template oci://ghcr.io/appscode-charts/vcluster-k0s \
  --values=/Users/tamal/go/src/go.bytebuilders.dev/gke-app/imgs/vcluster.yaml
