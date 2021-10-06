#!/bin/bash

# Creates two k3d clusters: source (east), & west (target).
#

set -eu
set -x

export ORG_DOMAIN="${ORG_DOMAIN:-cluster.local}"

port=6440
for cluster in source target ; do
    if k3d cluster get "$cluster" >/dev/null 2>&1 ; then
        echo "Already exists: $cluster" >&2
    else
        k3d cluster create "$cluster" \
            --api-port="$((port++))" \
            --network=multicluster-example \
            --k3s-server-arg="--cluster-domain=$cluster.$ORG_DOMAIN" \
            --wait
    fi
done
