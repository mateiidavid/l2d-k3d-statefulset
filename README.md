# Linkerd2 Multi-Cluster StatefulSet Demo

[upstream]: https://github.com/olix0r/l2-k3d-multi

Adapted from [olix0r/l2-k3d-multi][upstream], this demo creates two k3d
clusters (east and west), installs Linkerd and configures the multicluster
extension to include support for headless services.

- [`k3d:v4`](https://github.com/rancher/k3d/releases/tag/v4.1.1)
- [`smallstep/cli`](https://github.com/smallstep/cli/releases)
- [`linkerd:stable-2.10.0`+](https://github.com/linkerd/linkerd2/releases)

[`./create.sh`](./create.sh) initializes a set of clusters in `k3d`: 
_east_, and _west_.

[`./install.sh`](./install.sh) creates a temporary CA and installs Linkerd
into these clusters.

[`./link.sh`](./link.sh) links the two clusters to each other and deploys the
service mirror component with the new `-enable-headless-services` flag in order
to support (you guessed it) headless services.

[`./deploy.sh`](./deploy.sh) creates example statefulsets in the west cluster.
See [How to test](#how-to-test) below for a more in-depth explanation.


## How to run:

[linkerd]: https://github.com/linkerd/linkerd2
[branch]: https://github.com/linkerd/linkerd2/tree/matei/mcsset



1) The first step is to clone [linkerd/linkerd2][linkerd] and this repository.
`cd` into the repository and create the two k3d clusters. 
```sh
$ ./create.sh
```

2) In `linkerd2`, check out the StatefulSet [branch][branch] and build the docker images.
```sh
# Check out statefulset branch
# 
# zsh, bash, fish
$ git checkout matei/mcsset
$ bin/docker-build

# after images & cli have been built, set path to linkerd cli binary
# this will be used later to install the control plane & multicluster
# with the branch images
#
# bash, zsh
$ export LINKERD=$PWD/bin/linkerd
# fish
$ set -x LINKERD (pwd)/bin/linkerd

# import the images in the clusters
#
# bash, zsh
$ for cluster in east west ; do
    bin/image-load --k3d --cluster $cluster
  done
# fish
$ for cluster in east west
    bin/image-load --k3d-cluster $cluster
  end 
```

3) `cd` back into `l2d-k3d-statefulset` and install Linkerd and multicluster.
```sh
# Check path we set earlier is still valid
# should be something like /home/user/../linkerd2/bin/linkerd
# 
# zsh, bash, fish
echo $LINKERD

# Install Linkerd
#
./install.sh

# Link clusters
#
./link.sh

# Deploy manifests
#
./deploy.sh
```

...and done! You should be set up to export headless services using Linkerd and
the multicluster extension. You can verify the headless services we applied in
`west` have been exported:
```sh
# In east, check we see mirror services
# if ./deploy was run, we should see
# the following output
#
# bash, zsh, fish
$ kubectl --context=k3d-east get svc
NAME                            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes                      ClusterIP   10.43.0.1       <none>        443/TCP   25m
nginx-svc-west                  ClusterIP   10.43.30.116    <none>        80/TCP    22m
nginx-invalid-deploy-svc-west   ClusterIP   10.43.109.26    <none>        80/TCP    22m
nginx-set-0-west                ClusterIP   10.43.88.133    <none>        80/TCP    22m
nginx-set-1-west                ClusterIP   10.43.94.236    <none>        80/TCP    22m
nginx-set-2-west                ClusterIP   10.43.128.107   <none>        80/TCP    21m

# Test connectivity from east to west
# by curling nginx. Make sure curl is meshed.
# 
# fish, bash, zsh
$ kubectl --context=k3d-east exec curl -it -c curl -- bin/sh
  # curl instance 0 from statefulset by targeting DNS name
  $ curl http://nginx-set-0.nginx-svc-west.default.svc.east.cluster.local:80
  # should receive response
  # gateway in west should have logged the request redirect to nginx-svc.
```

From here, you can either experiment more with curl or try to export any
headless service to see how the feature holds and behaves. If out of ideas, the
next section outlines the tests I carried out and how they can be replicated,
based on the manifests included.

## How to test

This section outlines how to test this branch. When doing manual testing, I
came up with a few cases to check the service-mirror behaviour with the
headless service changes; mostly, these tests are related to how state is
reconciled bewtween the two clusters -- i.e can we create, export and delete
services without seeing errors? Does the validation logic work? These were the
questions that I had at the top of my head when going through the change
manually. All tests described here use the manifests from the [east](east/) and
[west](west/) directories.

**Note**: _in these tests, west is the `target` cluster and east is the `source`_.

1) **Test service-mirror behaviour**: based on
[nginx-statefulset](west/nginx-statefulset.yml). Should test general
functionality: creating, scaling and deleting a service.
   - can we apply the manifest and see the service mirror in `east`? Is it
     headless and does it have an endpoint mirror for each pod in the
     statefulset?
   - if we remove the export annotation from the service in `west`, will
     resources be cleaned up in `east`? What if we delete the original service?
   - if we re-export the service, will it be mirrored?
   - can we scale up the statefulset and see the instances mirrored in `east`?
   - can we scale down and see the resources deleted from `east`?

2) **Test svc-to-svc communication**: based on `nginx-statefulset` and
[curl](east/curl.yml). With our headless service exported and all of our
services meshed in both `east` and `west`, can we exec onto the curl pod in
`east`, fire off a request to the target cluster and get a response?
   - can we curl individual instances? e.g `curl http://nginx-set-1.nginx-svc-west.default.svc.east.cluster.local:80`
   - can we curl the headless svc itself and get a resp? e.g `curl http://nginx-svc-west.default.svc.east.cluster.local:80`
   - does the gateway in the target cluster (`west`) show the request has been routed?

3) **Test service-mirror validation logic**: (which is probably the least
tested behaviour from my side), based on
[nginx-no-ports](west/nginx-statefulset-no-ports.yml) and
[nginx-deployment](west/nginx-deployment.yml).
   - if we apply `nginx-no-ports` in `west` and we export it, can we confirm a
    `SkippedMirroring` event has been emitted against the service and it has
    not been exported to the source cluster?
   - if we apply `nginx-deployment` in `west` as a _headless service_, we expect
    it to be created as a `clusterIP` service, because it does not have any
    named addresses. Is this true? Is the service mirrored? Does deleting the
    service from `west` break the cluster? What about unexporting it.

These three tests should be enough to test general functionality: how a service
is validated, mirrored and how a request flows through the gateway based on all
of the changes that have happened outside of the multicluster extension.
