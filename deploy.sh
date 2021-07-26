#!/bin/bash

# Deploys test manifests to east and west

set -eu
set -x

# Annotate default namespaces to automatically inject workloads.
for cluster in east, west ; do
  kubectl --context=k3d-$cluster annotate ns default "config.linkerd.io/inject=enabled"
done

# Deploy 'curl' pod in cluster east; used to test traffic from source
# to target cluster.
#
echo "Applying curl to east"
kubectl --context=k3d-east apply -f "./east/curl.yml"

# Deploy an 'nginx-set' statefulset, along with a headless 'nginx-svc' to 
# cluster west;  used as poc app to mirror a headless service from target to 
# source. The service is already exported.
# curling this from source cluster should work.
# 
echo "Applying statefulset to west"
kubectl --context=k3d-west apply -f "./west/nginx-statefulset.yml"
sleep 2

# Deploy two invalid headless services: 'nginx-no-ports' & 'nginx-invalid-deploy-svc'
# nginx-no-ports: should not be exported in east and have an event associated in west
# nginx-invalid-deploy-svc: should not be exported in east as headless but as clusterIP
#
echo "Applying invalid exported headless service manifests"
kubectl --context=k3d-west apply -f "./west/nginx-statefulset-no-ports.yml"
kubectl --context=k3d-west annotate svc nginx-no-ports "mirror.linkerd.io/exported=\"true\""
sleep 2
kubectl --context=k3d-west apply -f "./west/nginx-deployment.yml"

echo "Done!"

