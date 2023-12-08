#!/bin/bash

help() {
  echo "
Usage:
$0 [-i -r -n]

Flags:
  -i   Image to be used by the application
  -U   Docker username to pull image (Just set if the image is private)
  -P   Docker password to pull image (Just set if the image is private)
  -r   Helm release name
  -n   Namespace to install helm release
"
}

namespace="default"

while getopts i:U:Pr:n:h flag
do
  case "${flag}" in
    i) image_name=${OPTARG};;
    U) docker_username=${OPTARG};;
    P)
      read -s -p "Docker password: " docker_password;;
    r) release_name=${OPTARG};;
    n) namespace=${OPTARG};;
    h)
      help
      exit 0;
  esac
done

echo
echo "Iniating terraform..."
terraform -chdir=infrastructure/terraform/dev init
echo

echo "Creating infrastructure..."
terraform -chdir=infrastructure/terraform/dev apply -auto-approve
echo

image_pull_secret=""

if [[ "$docker_username" != "" && "$docker_password" != "" ]]; then
  image_pull_secret="--set imagePullSecret.registry=https://index.docker.io/v1/,\
imagePullSecret.username=$docker_username,\
imagePullSecret.password=$docker_password"
fi

echo "Installing application stack..."
helm upgrade -n $namespace --create-namespace --wait \
--install $release_name ./infrastructure/helm \
--set app.image=$image_name,webserver.port=80 $image_pull_secret
echo

webserver_url=$(kubectl get svc -n $namespace -o \
custom-columns=:.metadata.name -l \
component="webserver-service")

echo "Testing stack scalability and availability during load peaks (press ctrl+c to stop)"
kubectl run -i --tty load-generator --rm -n $namespace \
--image=busybox:1.28 --restart=Never -- \
/bin/sh -c "while sleep 0.01; do wget -q -O- http://$webserver_url/posts; done"