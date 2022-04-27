#!/bin/bash

# Deploys test manifests to east and west

set -eu
set -x
LINKERD="${LINKERD:-linkerd}"

# Annotate default namespaces to automatically inject workloads.
for cluster in east west ; do
  kubectl --context=k3d-$cluster get ns default -o yaml \
  | $LINKERD --context=k3d-$cluster inject - \
  | kubectl --context=k3d-$cluster apply -f - 
done
sleep 2

# Deploy 'curl' pod in cluster east; used to test traffic from source
# to target cluster.
#
echo "Applying curl to east"
kubectl --context=k3d-east apply -f "./east/curl.yml"

# Deploy an 'nginx-set' statefulset, along with a headless 'nginx-svc' to 
# cluster west;  used as poc app to mirror a headless service from target to 
# source.
# 
echo "Applying statefulset to west"
kubectl --context=k3d-west apply -f "./west/nginx-statefulset.yml"
sleep 2

echo "Done!"

