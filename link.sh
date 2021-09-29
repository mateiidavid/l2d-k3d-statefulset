#!/bin/sh

set -eu

ORG_DOMAIN="${ORG_DOMAIN:-cluster.local}"
LINKERD="${LINKERD:-linkerd}"


# Generate credentials so the service-mirror
#
# Unfortunately, the credentials have the API server IP as addressed from
# localhost and not the docker network, so we have to patch that up.
fetch_credentials() {
    cluster="$1"
    # Grab the LB IP of cluster's API server & replace it in the secret blob:
    lb_ip=$(kubectl --context="k3d-$cluster" get svc -n kube-system traefik \
        -o 'go-template={{ (index .status.loadBalancer.ingress 0).ip }}')
    
    # shellcheck disable=SC2001  
    echo "$($LINKERD --context="k3d-$cluster" \
            multicluster link --set "enableHeadlessServices=true" \
            --cluster-name="$cluster" \
            --log-level="debug" \
            --api-server-address="https://${lb_ip}:6443")" 
}

# East (source) & West (target) get access to each other.
fetch_credentials source | kubectl --context=k3d-target apply -n linkerd-multicluster -f -

fetch_credentials target | kubectl --context=k3d-source apply -n linkerd-multicluster -f -

sleep 10
for c in source target ; do
    $LINKERD --context="k3d-$c" mc check
done
