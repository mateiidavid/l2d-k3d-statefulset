#!/bin/bash

# Creates three k3d clusters: dev, east, & west.
#

set -eu
set -x

export ORG_DOMAIN="${ORG_DOMAIN:-k3d.example.com}"

port=6440
for cluster in dev east west ; do
    if k3d cluster get "$cluster" >/dev/null 2>&1 ; then
        echo "Already exists: $cluster" >&2
    else
        k3d cluster create "$cluster" \
            --image='latest' \
            --api-port="$((port++))" \
            --network=multicluster-example \
            --k3s-arg="--cluster-domain=$cluster.${ORG_DOMAIN}@server:0" \
            --wait
    fi
done
