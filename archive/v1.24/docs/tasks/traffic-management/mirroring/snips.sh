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
#          docs/tasks/traffic-management/mirroring/index.md
####################################################################################################
source "content/en/boilerplates/snips/gateway-api-support.sh"

snip_before_you_begin_1() {
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin-v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
      version: v1
  template:
    metadata:
      labels:
        app: httpbin
        version: v1
    spec:
      containers:
      - image: docker.io/kennethreitz/httpbin
        imagePullPolicy: IfNotPresent
        name: httpbin
        command: ["gunicorn", "--access-logfile", "-", "-b", "0.0.0.0:80", "httpbin:app"]
        ports:
        - containerPort: 80
EOF
}

snip_before_you_begin_2() {
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin-v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
      version: v2
  template:
    metadata:
      labels:
        app: httpbin
        version: v2
    spec:
      containers:
      - image: docker.io/kennethreitz/httpbin
        imagePullPolicy: IfNotPresent
        name: httpbin
        command: ["gunicorn", "--access-logfile", "-", "-b", "0.0.0.0:80", "httpbin:app"]
        ports:
        - containerPort: 80
EOF
}

snip_before_you_begin_3() {
kubectl create -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  labels:
    app: httpbin
spec:
  ports:
  - name: http
    port: 8000
    targetPort: 80
  selector:
    app: httpbin
EOF
}

snip_before_you_begin_4() {
cat <<EOF | kubectl create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: curl
spec:
  replicas: 1
  selector:
    matchLabels:
      app: curl
  template:
    metadata:
      labels:
        app: curl
    spec:
      containers:
      - name: curl
        image: curlimages/curl
        command: ["/bin/sleep","3650d"]
        imagePullPolicy: IfNotPresent
EOF
}

snip_creating_a_default_routing_policy_1() {
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
spec:
  hosts:
    - httpbin
  http:
  - route:
    - destination:
        host: httpbin
        subset: v1
      weight: 100
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
spec:
  host: httpbin
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
EOF
}

snip_creating_a_default_routing_policy_2() {
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: httpbin-v1
spec:
  ports:
  - port: 80
    name: http
  selector:
    app: httpbin
    version: v1
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin-v2
spec:
  ports:
  - port: 80
    name: http
  selector:
    app: httpbin
    version: v2
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin
spec:
  parentRefs:
  - group: ""
    kind: Service
    name: httpbin
    port: 8000
  rules:
  - backendRefs:
    - name: httpbin-v1
      port: 80
EOF
}

snip_creating_a_default_routing_policy_3() {
kubectl exec deploy/curl -c curl -- curl -sS http://httpbin:8000/headers
}

! IFS=$'\n' read -r -d '' snip_creating_a_default_routing_policy_3_out <<\ENDSNIP
{
  "headers": {
    "Accept": "*/*",
    "Content-Length": "0",
    "Host": "httpbin:8000",
    "User-Agent": "curl/7.35.0",
    "X-B3-Parentspanid": "57784f8bff90ae0b",
    "X-B3-Sampled": "1",
    "X-B3-Spanid": "3289ae7257c3f159",
    "X-B3-Traceid": "b56eebd279a76f0b57784f8bff90ae0b",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/default/sa/default;Hash=20afebed6da091c850264cc751b8c9306abac02993f80bdb76282237422bd098;Subject=\"\";URI=spiffe://cluster.local/ns/default/sa/default"
  }
}
ENDSNIP

snip_creating_a_default_routing_policy_4() {
kubectl logs deploy/httpbin-v1 -c httpbin
}

! IFS=$'\n' read -r -d '' snip_creating_a_default_routing_policy_4_out <<\ENDSNIP
127.0.0.1 - - [07/Mar/2018:19:02:43 +0000] "GET /headers HTTP/1.1" 200 321 "-" "curl/7.35.0"
ENDSNIP

snip_creating_a_default_routing_policy_5() {
kubectl logs deploy/httpbin-v2 -c httpbin
}

! IFS=$'\n' read -r -d '' snip_creating_a_default_routing_policy_5_out <<\ENDSNIP
<none>
ENDSNIP

snip_mirroring_traffic_to_httpbinv2_1() {
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
spec:
  hosts:
    - httpbin
  http:
  - route:
    - destination:
        host: httpbin
        subset: v1
      weight: 100
    mirror:
      host: httpbin
      subset: v2
    mirrorPercentage:
      value: 100.0
EOF
}

snip_mirroring_traffic_to_httpbinv2_2() {
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin
spec:
  parentRefs:
  - group: ""
    kind: Service
    name: httpbin
    port: 8000
  rules:
  - filters:
    - type: RequestMirror
      requestMirror:
        backendRef:
          name: httpbin-v2
          port: 80
    backendRefs:
    - name: httpbin-v1
      port: 80
EOF
}

snip_mirroring_traffic_to_httpbinv2_3() {
kubectl exec deploy/curl -c curl -- curl -sS http://httpbin:8000/headers
}

snip_mirroring_traffic_to_httpbinv2_4() {
kubectl logs deploy/httpbin-v1 -c httpbin
}

! IFS=$'\n' read -r -d '' snip_mirroring_traffic_to_httpbinv2_4_out <<\ENDSNIP
127.0.0.1 - - [07/Mar/2018:19:02:43 +0000] "GET /headers HTTP/1.1" 200 321 "-" "curl/7.35.0"
127.0.0.1 - - [07/Mar/2018:19:26:44 +0000] "GET /headers HTTP/1.1" 200 321 "-" "curl/7.35.0"
ENDSNIP

snip_mirroring_traffic_to_httpbinv2_5() {
kubectl logs deploy/httpbin-v2 -c httpbin
}

! IFS=$'\n' read -r -d '' snip_mirroring_traffic_to_httpbinv2_5_out <<\ENDSNIP
127.0.0.1 - - [07/Mar/2018:19:26:44 +0000] "GET /headers HTTP/1.1" 200 361 "-" "curl/7.35.0"
ENDSNIP

snip_cleaning_up_1() {
kubectl delete virtualservice httpbin
kubectl delete destinationrule httpbin
}

snip_cleaning_up_2() {
kubectl delete httproute httpbin
kubectl delete svc httpbin-v1 httpbin-v2
}

snip_cleaning_up_3() {
kubectl delete deploy httpbin-v1 httpbin-v2 curl
kubectl delete svc httpbin
}
