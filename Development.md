## publish helm chart

helm dependency update chart/ace-mp
helm package chart/ace-mp
helm push ace-mp-v2024.11.18.tgz oci://ghcr.io/appscode-charts

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
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --disable=metrics-server" sh -s - --tls-san "192.168.0.128"

echo 'alias k=kubectl' >> ~/.bashrc
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc

# Recreate k3s cluster
k3s-uninstall.sh
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --disable=metrics-server" sh -s - --tls-san "192.168.0.128"
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
kubectl apply -f "https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools/raw/master/crd/app-crd.yaml"

---

## install vcluster cli

curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/download/v0.20.0/vcluster-linux-amd64" && sudo install -c -m 0755 vcluster /usr/local/bin && rm -f vcluster


## Prepare gcp-mp host

- re/create k3s cluster
- install vcluster

- install docker
- install gcloud cli

- install crane

```
curl -sL "https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz" >/tmp/go-containerregistry.tar.gz
tar -zxvf /tmp/go-containerregistry.tar.gz -C /usr/local/bin
```

- https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools/blob/master/docs/mpdev-references.md

```bash
sudo su
cd

gcloud init
gcloud auth configure-docker

gcloud auth configure-docker us-docker.pkg.dev
```

- install mpdev

```
BIN_FILE="/usr/local/bin/mpdev"
docker run \
  gcr.io/cloud-marketplace-tools/k8s/dev \
  cat /scripts/dev > "$BIN_FILE"
chmod +x "$BIN_FILE"


mpdev doctor
```

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
export TAG=0.20241118.0

## Publish deployer image

- https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools/blob/master/docs/building-deployer.md#tagging-your-images

```
crane cp ghcr.io/appscode-gcp-mp/ace-mp/prometheus-operator:0.20241017.0 ghcr.io/appscode-gcp-mp/ace-mp/prometheus-operator:0.20241118.0

crane cp ghcr.io/appscode-gcp-mp/ace-mp/deployer:$TAG us-docker.pkg.dev/appscode-public/ace-mp/deployer:$TAG
TRACK_ID=$(echo "$TAG" | sed 's/\.[^.]*$//')
crane cp ghcr.io/appscode-gcp-mp/ace-mp/deployer:$TAG us-docker.pkg.dev/appscode-public/ace-mp/deployer:$TRACK_ID
```

## Dev workflow

git fetch origin
git checkout master
git reset --hard origin/master

docker build --push --tag $REGISTRY/$APP_NAME/deployer:$TAG . \
--build-arg CLOUD_SDK_VERSION=484.0.0 \
--build-arg SKIP_GCP=true

kubectl delete namespace ace
kubectl create namespace ace

mpdev verify \
  --deployer=$REGISTRY/$APP_NAME/deployer:$TAG \
  --wait_timeout=600

mpdev install \
  --deployer=$REGISTRY/$APP_NAME/deployer:$TAG \
  --parameters='{"name": "ace-mp", "namespace": "ace", "reportingSecret": "gs://cloud-marketplace-tools/reporting_secrets/fake_reporting_secret.yaml", "installerURL": "https://appscode.ninja/links/installer/937/tamal-gcp-mp/ct2erhf6tqec73et0v8g-w295wqvqsh/archive.tar.gz"}'

kubectl get secret -n ace ace-mp-deployer-config -o go-template='{{index .data "values.yaml"}}' | base64 -d

kubectl logs -f -n ace job/ace-mp-deployer

kubectl logs -n ace job/ace-mp-deployer

kubectl get pods -n ace -o yaml | grep image: | sort | uniq

vcluster connect -n ace ace-mp

vcluster disconnect

vcluster connect ace-mp -n ace -- kubectl get hr -A
