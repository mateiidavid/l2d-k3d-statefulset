#!/bin/bash

# Creates two k3d clusters: (source) east, & (target) west.
#

set -eu
set -x

ORG_DOMAIN="${ORG_DOMAIN:-cluster.local}"
LINKERD="${LINKERD:-linkerd}"

case $(uname) in
	Darwin)
		# host_platform=darwin
        CA_DIR=$(mktemp -d k3d-ca.XXXXX)
		;;
	Linux)
		# host_platform=linux
        CA_DIR=$(mktemp --tmpdir="${TMPDIR:-/tmp}" -d k3d-ca.XXXXX)
		;;
	*)
		echo "Unknown operating system: $(uname)"
        exit 1
		;;
esac

# Generate the trust roots. These never touch the cluster. In the real world
# we'd squirrel these away in a vault.
step certificate create \
    "identity.linkerd.$ORG_DOMAIN" \
    "$CA_DIR/ca.crt" "$CA_DIR/ca.key" \
    --profile root-ca \
    --no-password  --insecure --force

for cluster in source target ; do
    # Check that the cluster is up and running.
    while ! "$LINKERD" --context="k3d-$cluster" check --pre ; do :; done

    # Create issuing credentials. These end up on the cluster (and can be
    # rotated from the root).
    crt="$CA_DIR/$cluster-issuer.crt"
    key="$CA_DIR/$cluster-issuer.key"
    domain="$cluster.$ORG_DOMAIN"
    step certificate create "identity.linkerd.$domain" \
        "$crt" "$key" \
        --ca="$CA_DIR/ca.crt" \
        --ca-key="$CA_DIR/ca.key" \
        --profile=intermediate-ca \
        --not-after 8760h --no-password --insecure

    # Install Linkerd into the cluster.
    "$LINKERD" --context="k3d-$cluster" install \
            --proxy-log-level="linkerd=debug,warn" \
            --cluster-domain="$domain" \
            --identity-trust-domain="$domain" \
            --identity-trust-anchors-file="$CA_DIR/ca.crt" \
            --identity-issuer-certificate-file="$crt" \
            --identity-issuer-key-file="$key" |
        kubectl --context="k3d-$cluster" apply -f -

    # Wait some time and check that the cluster has started properly.
    sleep 30
    while ! "$LINKERD" --context="k3d-$cluster" check ; do :; done

    kubectl --context="k3d-$cluster" create ns linkerd-multicluster
    sleep 2

    # Setup the multicluster components on the server
    "$LINKERD" --context="k3d-$cluster" multicluster install |
        kubectl --context="k3d-$cluster" apply -f -
done
