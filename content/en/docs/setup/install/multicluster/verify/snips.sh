#!/bin/bash
# shellcheck disable=SC2034,SC2153,SC2155,SC2164

# Copyright Istio Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

####################################################################################################
# WARNING: THIS IS AN AUTO-GENERATED FILE, DO NOT EDIT. PLEASE MODIFY THE ORIGINAL MARKDOWN FILE:
#          docs/setup/install/multicluster/verify/index.md
####################################################################################################

snip_verify_multicluster_1() {
istioctl remote-clusters --context="${CTX_CLUSTER1}"
}

! IFS=$'\n' read -r -d '' snip_verify_multicluster_1_out <<\ENDSNIP
NAME         SECRET                                        STATUS      ISTIOD
cluster1                                                   synced      istiod-7b74b769db-kb4kj
cluster2     istio-system/istio-remote-secret-cluster2     synced      istiod-7b74b769db-kb4kj
ENDSNIP

snip_deploy_the_helloworld_service_1() {
kubectl create --context="${CTX_CLUSTER1}" namespace sample
kubectl create --context="${CTX_CLUSTER2}" namespace sample
}

snip_deploy_the_helloworld_service_2() {
kubectl label --context="${CTX_CLUSTER1}" namespace sample \
    istio-injection=enabled
kubectl label --context="${CTX_CLUSTER2}" namespace sample \
    istio-injection=enabled
}

snip_deploy_the_helloworld_service_3() {
kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/helloworld/helloworld.yaml \
    -l service=helloworld -n sample
kubectl apply --context="${CTX_CLUSTER2}" \
    -f samples/helloworld/helloworld.yaml \
    -l service=helloworld -n sample
}

snip_deploy_helloworld_v1_1() {
kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/helloworld/helloworld.yaml \
    -l version=v1 -n sample
}

snip_deploy_helloworld_v1_2() {
kubectl get pod --context="${CTX_CLUSTER1}" -n sample -l app=helloworld
}

! IFS=$'\n' read -r -d '' snip_deploy_helloworld_v1_2_out <<\ENDSNIP
NAME                            READY     STATUS    RESTARTS   AGE
helloworld-v1-86f77cd7bd-cpxhv  2/2       Running   0          40s
ENDSNIP

snip_deploy_helloworld_v2_1() {
kubectl apply --context="${CTX_CLUSTER2}" \
    -f samples/helloworld/helloworld.yaml \
    -l version=v2 -n sample
}

snip_deploy_helloworld_v2_2() {
kubectl get pod --context="${CTX_CLUSTER2}" -n sample -l app=helloworld
}

! IFS=$'\n' read -r -d '' snip_deploy_helloworld_v2_2_out <<\ENDSNIP
NAME                            READY     STATUS    RESTARTS   AGE
helloworld-v2-758dd55874-6x4t8  2/2       Running   0          40s
ENDSNIP

snip_deploy_curl_1() {
kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/curl/curl.yaml -n sample
kubectl apply --context="${CTX_CLUSTER2}" \
    -f samples/curl/curl.yaml -n sample
}

snip_deploy_curl_2() {
kubectl get pod --context="${CTX_CLUSTER1}" -n sample -l app=curl
}

! IFS=$'\n' read -r -d '' snip_deploy_curl_2_out <<\ENDSNIP
NAME                             READY   STATUS    RESTARTS   AGE
curl-754684654f-n6bzf            2/2     Running   0          5s
ENDSNIP

snip_deploy_curl_3() {
kubectl get pod --context="${CTX_CLUSTER2}" -n sample -l app=curl
}

! IFS=$'\n' read -r -d '' snip_deploy_curl_3_out <<\ENDSNIP
NAME                             READY   STATUS    RESTARTS   AGE
curl-754684654f-dzl9j            2/2     Running   0          5s
ENDSNIP

snip_verifying_crosscluster_traffic_1() {
kubectl exec --context="${CTX_CLUSTER1}" -n sample -c curl \
    "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sample -l \
    app=curl -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.sample:5000/hello
}

! IFS=$'\n' read -r -d '' snip_verifying_crosscluster_traffic_2 <<\ENDSNIP
Hello version: v2, instance: helloworld-v2-758dd55874-6x4t8
Hello version: v1, instance: helloworld-v1-86f77cd7bd-cpxhv
...
ENDSNIP

snip_verifying_crosscluster_traffic_3() {
kubectl exec --context="${CTX_CLUSTER2}" -n sample -c curl \
    "$(kubectl get pod --context="${CTX_CLUSTER2}" -n sample -l \
    app=curl -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.sample:5000/hello
}

! IFS=$'\n' read -r -d '' snip_verifying_crosscluster_traffic_4 <<\ENDSNIP
Hello version: v2, instance: helloworld-v2-758dd55874-6x4t8
Hello version: v1, instance: helloworld-v1-86f77cd7bd-cpxhv
...
ENDSNIP
