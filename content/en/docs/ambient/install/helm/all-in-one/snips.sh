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
#          docs/ambient/install/helm/all-in-one/index.md
####################################################################################################
source "content/en/boilerplates/snips/gateway-api-install-crds.sh"

snip_configure_helm() {
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
}

snip_install_ambient_aio() {
helm install istio-ambient istio/ambient --namespace istio-system --create-namespace --wait
}

snip_install_ingress() {
helm install istio-ingress istio/gateway -n istio-ingress --create-namespace --wait
}

snip_configuration_3() {
helm show values istio/istiod
}

snip_show_components() {
helm ls -n istio-system
}

! IFS=$'\n' read -r -d '' snip_show_components_out <<\ENDSNIP
NAME            NAMESPACE       REVISION    UPDATED                                 STATUS      CHART           APP VERSION
istio-ambient      istio-system    1           2024-04-17 22:14:45.964722028 +0000 UTC deployed    ambient-1.27.0     1.27.0
ENDSNIP

snip_check_pods() {
kubectl get pods -n istio-system
}

! IFS=$'\n' read -r -d '' snip_check_pods_out <<\ENDSNIP
NAME                             READY   STATUS    RESTARTS   AGE
istio-cni-node-g97z5             1/1     Running   0          10m
istiod-5f4c75464f-gskxf          1/1     Running   0          10m
ztunnel-c2z4s                    1/1     Running   0          10m
ENDSNIP

snip_delete_ambient_aio() {
helm delete istio-ambient -n istio-system
}

snip_delete_ingress() {
helm delete istio-ingress -n istio-ingress
kubectl delete namespace istio-ingress
}

snip_delete_crds() {
kubectl get crd -oname | grep --color=never 'istio.io' | xargs kubectl delete
}

snip_delete_system_namespace() {
kubectl delete namespace istio-system
}
