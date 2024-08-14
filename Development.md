## publish helm chart

helm dependency update chart/ace-mp
helm package chart/ace-mp
helm push ace-mp-v2024.7.4.tgz oci://ghcr.io/appscode-charts

## fmt

```sh
find . -path ./vendor -prune -o -name '*.sh' -exec shfmt -l -w -ci -i 2 {} \;
```

## update vcluster chart

helm fetch --untar --destination chart oci://ghcr.io/appscode-charts/vcluster-k0s --version 0.19.7
helm package chart/vcluster-k0s
helm push vcluster-k0s-0.19.7.tgz oci://ghcr.io/appscode-charts

helm fetch --untar --destination chart oci://ghcr.io/appscode-charts/vcluster --version 0.19.7
helm package chart/vcluster
helm push vcluster-0.19.7.tgz oci://ghcr.io/appscode-charts

---

echo 'fs.inotify.max_user_instances=100000' | sudo tee -a /etc/sysctl.conf
echo 'fs.inotify.max_user_watches=100000' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Create k3s cluster
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --disable=metrics-server" sh -s -

echo 'alias k=kubectl' >> ~/.bashrc
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc

# Recreate k3s cluster
k3s-uninstall.sh
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --disable=metrics-server" sh -s -
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
kubectl apply -f "https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools/raw/master/crd/app-crd.yaml"

---

## install vcluster cli

curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/download/v0.19.7/vcluster-linux-amd64" && sudo install -c -m 0755 vcluster /usr/local/bin && rm -f vcluster

---

wget https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools/raw/master/marketplace/deployer_helm_base/create_manifests.sh

---

## Bundle gcloud and curl cli

Copy install commands from gcloud stable docker file

- https://cloud.google.com/sdk/docs/downloads-docker#docker_image_options
- https://github.com/GoogleCloudPlatform/cloud-sdk-docker/blob/master/stable/Dockerfile

---

export REGISTRY=ghcr.io/appscode-gcp-mp
export APP_NAME=ace-mp
export TAG=v0.1.202474

git fetch origin
git checkout master
git reset --hard origin/master

docker build --push --tag $REGISTRY/$APP_NAME/deployer:$TAG . \
--build-arg CLOUD_SDK_VERSION=484.0.0 \
--build-arg SKIP_GCP=true

kubectl delete namespace ace
kubectl create namespace ace

mpdev install \
  --deployer=$REGISTRY/$APP_NAME/deployer:$TAG \
  --parameters='{"name": "ace-mp", "namespace": "ace", "reportingSecret": "gs://cloud-marketplace-tools/reporting_secrets/fake_reporting_secret.yaml", "installerURL": "https://appscode.com/links/installer/332800/gcp-mp/cquaibn2k5gs738o5afg-rwzm2sb2jv/archive.tar.gz"}'

kubectl get secret -n ace ace-mp-deployer-config -o go-template='{{index .data "values.yaml"}}' | base64 -d

kubectl logs -f -n ace job/ace-mp-deployer

kubectl logs -n ace job/ace-mp-deployer

kubectl get pods -n ace -o yaml | grep image: | sort | uniq

vcluster connect -n ace ace-mp

vcluster disconnect

vcluster connect ace-mp -n ace -- kubectl get hr -A
