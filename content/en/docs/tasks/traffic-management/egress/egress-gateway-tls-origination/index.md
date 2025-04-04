---
title: Egress Gateways with TLS Origination
description: Describes how to configure an Egress Gateway to perform TLS origination to external services.
weight: 40
keywords: [traffic-management,egress]
aliases:
  - /docs/examples/advanced-gateways/egress-gateway-tls-origination/
  - /docs/examples/advanced-gateways/egress-gateway-tls-origination-sds/
  - /docs/tasks/traffic-management/egress/egress-gateway-tls-origination-sds/
owner: istio/wg-networking-maintainers
test: yes
---

The [TLS Origination for Egress Traffic](/docs/tasks/traffic-management/egress/egress-tls-origination/)
example shows how to configure Istio to perform {{< gloss >}}TLS origination{{< /gloss >}}
for traffic to an external service. The [Configure an Egress Gateway](/docs/tasks/traffic-management/egress/egress-gateway/)
example shows how to configure Istio to direct egress traffic through a
dedicated _egress gateway_ service. This example combines the previous two by
describing how to configure an egress gateway to perform TLS origination for
traffic to external services.

{{< boilerplate gateway-api-support >}}

## Before you begin

*   Setup Istio by following the instructions in the [Installation guide](/docs/setup/).

*   Start the [curl]({{< github_tree >}}/samples/curl) sample
    which will be used as a test source for external calls.

    If you have enabled [automatic sidecar injection](/docs/setup/additional-setup/sidecar-injection/#automatic-sidecar-injection), do

    {{< text bash >}}
    $ kubectl apply -f @samples/curl/curl.yaml@
    {{< /text >}}

    otherwise, you have to manually inject the sidecar before deploying the `curl` application:

    {{< text bash >}}
    $ kubectl apply -f <(istioctl kube-inject -f @samples/curl/curl.yaml@)
    {{< /text >}}

    Note that any pod that you can `exec` and `curl` from would do.

*   Create a shell variable to hold the name of the source pod for sending requests to external services.
    If you used the [curl]({{< github_tree >}}/samples/curl) sample, run:

    {{< text bash >}}
    $ export SOURCE_POD=$(kubectl get pod -l app=curl -o jsonpath={.items..metadata.name})
    {{< /text >}}

*   For macOS users, verify that you are using `openssl` version 1.1 or later:

    {{< text bash >}}
    $ openssl version -a | grep OpenSSL
    OpenSSL 1.1.1g  21 Apr 2020
    {{< /text >}}

    If the previous command outputs a version `1.1` or later, as shown, your `openssl` command
    should work correctly with the instructions in this task. Otherwise, upgrade your `openssl` or try
    a different implementation of `openssl`, for example on a Linux machine.

*   [Enable Envoy’s access logging](/docs/tasks/observability/logs/access-log/#enable-envoy-s-access-logging)
    if not already enabled. For example, using `istioctl`:

    {{< text bask >}}
    $ istioctl install <flags-you-used-to-install-Istio> --set meshConfig.accessLogFile=/dev/stdout
    {{< /text >}}

*   If you are NOT using the `Gateway API` instructions, make sure to
    [deploy the Istio egress gateway](/docs/tasks/traffic-management/egress/egress-gateway/#deploy-istio-egress-gateway).

## Perform TLS origination with an egress gateway

This section describes how to perform the same TLS origination as in the
[TLS Origination for Egress Traffic](/docs/tasks/traffic-management/egress/egress-tls-origination/) example,
only this time using an egress gateway. Note that in this case the TLS origination will
be done by the egress gateway, as opposed to by the sidecar in the previous example.

1.  Define a `ServiceEntry` for `edition.cnn.com`:

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: cnn
    spec:
      hosts:
      - edition.cnn.com
      ports:
      - number: 80
        name: http
        protocol: HTTP
      - number: 443
        name: https
        protocol: HTTPS
      resolution: DNS
    EOF
    {{< /text >}}

1.  Verify that your `ServiceEntry` was applied correctly by sending a request to [http://edition.cnn.com/politics](https://edition.cnn.com/politics).

    {{< text bash >}}
    $ kubectl exec "${SOURCE_POD}" -c curl -- curl -sSL -o /dev/null -D - http://edition.cnn.com/politics
    HTTP/1.1 301 Moved Permanently
    ...
    location: https://edition.cnn.com/politics
    ...
    {{< /text >}}

    Your `ServiceEntry` was configured correctly if you see _301 Moved Permanently_ in the output.

1.  Create an egress `Gateway` for _edition.cnn.com_, port 80, and a destination rule for
    sidecar requests that will be directed to the egress gateway.

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: istio-egressgateway
spec:
  selector:
    istio: egressgateway
  servers:
  - port:
      number: 80
      name: https-port-for-tls-origination
      protocol: HTTPS
    hosts:
    - edition.cnn.com
    tls:
      mode: ISTIO_MUTUAL
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-cnn
spec:
  host: istio-egressgateway.istio-system.svc.cluster.local
  subsets:
  - name: cnn
    trafficPolicy:
      loadBalancer:
        simple: ROUND_ROBIN
      portLevelSettings:
      - port:
          number: 80
        tls:
          mode: ISTIO_MUTUAL
          sni: edition.cnn.com
EOF
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: cnn-egress-gateway
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: https-listener-for-tls-origination
    hostname: edition.cnn.com
    port: 80
    protocol: HTTPS
    tls:
      mode: Terminate
      options:
        gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-cnn
spec:
  host: cnn-egress-gateway-istio.default.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    portLevelSettings:
    - port:
        number: 80
      tls:
        mode: ISTIO_MUTUAL
        sni: edition.cnn.com
EOF
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

4) Configure route rules to direct traffic through the egress gateway:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: direct-cnn-through-egress-gateway
spec:
  hosts:
  - edition.cnn.com
  gateways:
  - istio-egressgateway
  - mesh
  http:
  - match:
    - gateways:
      - mesh
      port: 80
    route:
    - destination:
        host: istio-egressgateway.istio-system.svc.cluster.local
        subset: cnn
        port:
          number: 80
      weight: 100
  - match:
    - gateways:
      - istio-egressgateway
      port: 80
    route:
    - destination:
        host: edition.cnn.com
        port:
          number: 443
      weight: 100
EOF
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: direct-cnn-to-egress-gateway
spec:
  parentRefs:
  - kind: ServiceEntry
    group: networking.istio.io
    name: cnn
  rules:
  - backendRefs:
    - name: cnn-egress-gateway-istio
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: forward-cnn-from-egress-gateway
spec:
  parentRefs:
  - name: cnn-egress-gateway
  hostnames:
  - edition.cnn.com
  rules:
  - backendRefs:
    - kind: Hostname
      group: networking.istio.io
      name: edition.cnn.com
      port: 443
EOF
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

5)  Define a `DestinationRule` to perform TLS origination for requests to `edition.cnn.com`:

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: networking.istio.io/v1
    kind: DestinationRule
    metadata:
      name: originate-tls-for-edition-cnn-com
    spec:
      host: edition.cnn.com
      trafficPolicy:
        loadBalancer:
          simple: ROUND_ROBIN
        portLevelSettings:
        - port:
            number: 443
          tls:
            mode: SIMPLE # initiates HTTPS for connections to edition.cnn.com
    EOF
    {{< /text >}}

6)  Send an HTTP request to [http://edition.cnn.com/politics](https://edition.cnn.com/politics).

    {{< text bash >}}
    $ kubectl exec "${SOURCE_POD}" -c curl -- curl -sSL -o /dev/null -D - http://edition.cnn.com/politics
    HTTP/1.1 200 OK
    ...
    {{< /text >}}

    The output should be the same as in the [TLS Origination for Egress Traffic](/docs/tasks/traffic-management/egress/egress-tls-origination/)
    example, with TLS origination: without the _301 Moved Permanently_ message.

7) Check the log of the egress gateway's proxy.

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

If Istio is deployed in the `istio-system` namespace, the command to print the log is:

{{< text bash >}}
$ kubectl logs -l istio=egressgateway -c istio-proxy -n istio-system | tail
{{< /text >}}

You should see a line similar to the following:

{{< text plain>}}
[2020-06-30T16:17:56.763Z] "GET /politics HTTP/2" 200 - "-" "-" 0 1295938 529 89 "10.244.0.171" "curl/7.64.0" "cf76518d-3209-9ab7-a1d0-e6002728ef5b" "edition.cnn.com" "151.101.129.67:443" outbound|443||edition.cnn.com 10.244.0.170:54280 10.244.0.170:8080 10.244.0.171:35628 - -
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

Access the log corresponding to the egress gateway using the Istio-generated pod label:

{{< text bash >}}
$ kubectl logs -l gateway.networking.k8s.io/gateway-name=cnn-egress-gateway -c istio-proxy | tail
{{< /text >}}

You should see a line similar to the following:

{{< text plain >}}
[2024-03-14T18:37:01.451Z] "GET /politics HTTP/1.1" 200 - via_upstream - "-" 0 2484998 59 37 "172.30.239.26" "curl/7.87.0-DEV" "b80c8732-8b10-4916-9a73-c3e1c848ed1e" "edition.cnn.com" "151.101.131.5:443" outbound|443||edition.cnn.com 172.30.239.33:51270 172.30.239.33:80 172.30.239.26:35192 edition.cnn.com default.forward-cnn-from-egress-gateway.0
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

### Cleanup the TLS origination example

Remove the Istio configuration items you created:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl delete gw istio-egressgateway
$ kubectl delete serviceentry cnn
$ kubectl delete virtualservice direct-cnn-through-egress-gateway
$ kubectl delete destinationrule originate-tls-for-edition-cnn-com
$ kubectl delete destinationrule egressgateway-for-cnn
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl delete serviceentry cnn
$ kubectl delete gtw cnn-egress-gateway
$ kubectl delete httproute direct-cnn-to-egress-gateway
$ kubectl delete httproute forward-cnn-from-egress-gateway
$ kubectl delete destinationrule egressgateway-for-cnn
$ kubectl delete destinationrule originate-tls-for-edition-cnn-com
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

## Perform mutual TLS origination with an egress gateway

Similar to the previous section, this section describes how to configure an egress gateway to perform
TLS origination for an external service, only this time using a service that requires mutual TLS.

This example is considerably more involved because you need to first:

1. generate client and server certificates
1. deploy an external service that supports the mutual TLS protocol
1. redeploy the egress gateway with the needed mutual TLS certs

Only then can you configure the external traffic to go through the egress gateway which will perform
TLS origination.

### Generate client and server certificates and keys

For this task you can use your favorite tool to generate certificates and keys. The commands below use
[openssl](https://man.openbsd.org/openssl.1)

1.  Create a root certificate and private key to sign the certificate for your services:

    {{< text bash >}}
    $ openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=example Inc./CN=example.com' -keyout example.com.key -out example.com.crt
    {{< /text >}}

1.  Create a certificate and a private key for `my-nginx.mesh-external.svc.cluster.local`:

    {{< text bash >}}
    $ openssl req -out my-nginx.mesh-external.svc.cluster.local.csr -newkey rsa:2048 -nodes -keyout my-nginx.mesh-external.svc.cluster.local.key -subj "/CN=my-nginx.mesh-external.svc.cluster.local/O=some organization"
    $ openssl x509 -req -sha256 -days 365 -CA example.com.crt -CAkey example.com.key -set_serial 0 -in my-nginx.mesh-external.svc.cluster.local.csr -out my-nginx.mesh-external.svc.cluster.local.crt
    {{< /text >}}

    Optionally, you can add `SubjectAltNames` to the certificate if you want to enable SAN validation for the destination. For example:

    {{< text syntax=bash snip_id=none >}}
    $ cat > san.conf <<EOF
    [req]
    distinguished_name = req_distinguished_name
    req_extensions = v3_req
    x509_extensions = v3_req
    prompt = no
    [req_distinguished_name]
    countryName = US
    [v3_req]
    keyUsage = critical, digitalSignature, keyEncipherment
    extendedKeyUsage = serverAuth, clientAuth
    basicConstraints = critical, CA:FALSE
    subjectAltName = critical, @alt_names
    [alt_names]
    DNS = my-nginx.mesh-external.svc.cluster.local
    EOF
    $
    $ openssl req -out my-nginx.mesh-external.svc.cluster.local.csr -newkey rsa:4096 -nodes -keyout my-nginx.mesh-external.svc.cluster.local.key -subj "/CN=my-nginx.mesh-external.svc.cluster.local/O=some organization" -config san.conf
    $ openssl x509 -req -sha256 -days 365 -CA example.com.crt -CAkey example.com.key -set_serial 0 -in my-nginx.mesh-external.svc.cluster.local.csr -out my-nginx.mesh-external.svc.cluster.local.crt -extfile san.conf -extensions v3_req
    {{< /text >}}

1.  Generate client certificate and private key:

    {{< text bash >}}
    $ openssl req -out client.example.com.csr -newkey rsa:2048 -nodes -keyout client.example.com.key -subj "/CN=client.example.com/O=client organization"
    $ openssl x509 -req -sha256 -days 365 -CA example.com.crt -CAkey example.com.key -set_serial 1 -in client.example.com.csr -out client.example.com.crt
    {{< /text >}}

### Deploy a mutual TLS server

To simulate an actual external service that supports the mutual TLS protocol,
deploy an [NGINX](https://www.nginx.com) server in your Kubernetes cluster, but running outside of
the Istio service mesh, i.e., in a namespace without Istio sidecar proxy injection enabled.

1.  Create a namespace to represent services outside the Istio mesh, namely `mesh-external`. Note that the sidecar proxy will
    not be automatically injected into the pods in this namespace since the automatic sidecar injection was not
    [enabled](/docs/setup/additional-setup/sidecar-injection/#deploying-an-app) on it.

    {{< text bash >}}
    $ kubectl create namespace mesh-external
    {{< /text >}}

1. Create Kubernetes [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) to hold the server's and CA
   certificates.

    {{< text bash >}}
    $ kubectl create -n mesh-external secret tls nginx-server-certs --key my-nginx.mesh-external.svc.cluster.local.key --cert my-nginx.mesh-external.svc.cluster.local.crt
    $ kubectl create -n mesh-external secret generic nginx-ca-certs --from-file=example.com.crt
    {{< /text >}}

1.  Create a configuration file for the NGINX server:

    {{< text bash >}}
    $ cat <<\EOF > ./nginx.conf
    events {
    }

    http {
      log_format main '$remote_addr - $remote_user [$time_local]  $status '
      '"$request" $body_bytes_sent "$http_referer" '
      '"$http_user_agent" "$http_x_forwarded_for"';
      access_log /var/log/nginx/access.log main;
      error_log  /var/log/nginx/error.log;

      server {
        listen 443 ssl;

        root /usr/share/nginx/html;
        index index.html;

        server_name my-nginx.mesh-external.svc.cluster.local;
        ssl_certificate /etc/nginx-server-certs/tls.crt;
        ssl_certificate_key /etc/nginx-server-certs/tls.key;
        ssl_client_certificate /etc/nginx-ca-certs/example.com.crt;
        ssl_verify_client on;
      }
    }
    EOF
    {{< /text >}}

1.  Create a Kubernetes [ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
to hold the configuration of the NGINX server:

    {{< text bash >}}
    $ kubectl create configmap nginx-configmap -n mesh-external --from-file=nginx.conf=./nginx.conf
    {{< /text >}}

1.  Deploy the NGINX server:

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: v1
    kind: Service
    metadata:
      name: my-nginx
      namespace: mesh-external
      labels:
        run: my-nginx
    spec:
      ports:
      - port: 443
        protocol: TCP
      selector:
        run: my-nginx
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: my-nginx
      namespace: mesh-external
    spec:
      selector:
        matchLabels:
          run: my-nginx
      replicas: 1
      template:
        metadata:
          labels:
            run: my-nginx
        spec:
          containers:
          - name: my-nginx
            image: nginx
            ports:
            - containerPort: 443
            volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx
              readOnly: true
            - name: nginx-server-certs
              mountPath: /etc/nginx-server-certs
              readOnly: true
            - name: nginx-ca-certs
              mountPath: /etc/nginx-ca-certs
              readOnly: true
          volumes:
          - name: nginx-config
            configMap:
              name: nginx-configmap
          - name: nginx-server-certs
            secret:
              secretName: nginx-server-certs
          - name: nginx-ca-certs
            secret:
              secretName: nginx-ca-certs
    EOF
    {{< /text >}}

### Configure mutual TLS origination for egress traffic

1)  Create a Kubernetes [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)
    in the **same namespace** as the egress gateway is deployed in, to hold the client's certificates:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl create secret -n istio-system generic client-credential --from-file=tls.key=client.example.com.key \
  --from-file=tls.crt=client.example.com.crt --from-file=ca.crt=example.com.crt
{{< /text >}}

To support integration with various tools, Istio supports a few different Secret formats.
In this example, a single generic Secret with keys `tls.key`, `tls.crt`, and `ca.crt` is used.

{{< tip >}}
{{< boilerplate crl-tip >}}
{{< /tip >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl create secret -n default generic client-credential --from-file=tls.key=client.example.com.key \
  --from-file=tls.crt=client.example.com.crt --from-file=ca.crt=example.com.crt
{{< /text >}}

To support integration with various tools, Istio supports a few different Secret formats.
In this example, a single generic Secret with keys `tls.key`, `tls.crt`, and `ca.crt` is used.

{{< tip >}}
{{< boilerplate crl-tip >}}
{{< /tip >}}

{{< /tab >}}

{{< /tabset >}}

2)  Create an egress `Gateway` for `my-nginx.mesh-external.svc.cluster.local`, port 443, and a destination rule for
    sidecar requests that will be directed to the egress gateway:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: istio-egressgateway
spec:
  selector:
    istio: egressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - my-nginx.mesh-external.svc.cluster.local
    tls:
      mode: ISTIO_MUTUAL
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-nginx
spec:
  host: istio-egressgateway.istio-system.svc.cluster.local
  subsets:
  - name: nginx
    trafficPolicy:
      loadBalancer:
        simple: ROUND_ROBIN
      portLevelSettings:
      - port:
          number: 443
        tls:
          mode: ISTIO_MUTUAL
          sni: my-nginx.mesh-external.svc.cluster.local
EOF
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: nginx-egressgateway
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: https
    hostname: my-nginx.mesh-external.svc.cluster.local
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      options:
        gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nginx-egressgateway-istio-sds
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - watch
  - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nginx-egressgateway-istio-sds
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: nginx-egressgateway-istio-sds
subjects:
- kind: ServiceAccount
  name: nginx-egressgateway-istio
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-nginx
spec:
  host: nginx-egressgateway-istio.default.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: ISTIO_MUTUAL
        sni: my-nginx.mesh-external.svc.cluster.local
EOF
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

3) Configure route rules to direct traffic through the egress gateway:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: direct-nginx-through-egress-gateway
spec:
  hosts:
  - my-nginx.mesh-external.svc.cluster.local
  gateways:
  - istio-egressgateway
  - mesh
  http:
  - match:
    - gateways:
      - mesh
      port: 80
    route:
    - destination:
        host: istio-egressgateway.istio-system.svc.cluster.local
        subset: nginx
        port:
          number: 443
      weight: 100
  - match:
    - gateways:
      - istio-egressgateway
      port: 443
    route:
    - destination:
        host: my-nginx.mesh-external.svc.cluster.local
        port:
          number: 443
      weight: 100
EOF
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: direct-nginx-to-egress-gateway
spec:
  hosts:
  - my-nginx.mesh-external.svc.cluster.local
  gateways:
  - mesh
  http:
  - match:
    - port: 80
    route:
    - destination:
        host: nginx-egressgateway-istio.default.svc.cluster.local
        port:
          number: 443
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: forward-nginx-from-egress-gateway
spec:
  parentRefs:
  - name: nginx-egressgateway
  hostnames:
  - my-nginx.mesh-external.svc.cluster.local
  rules:
  - backendRefs:
    - name: my-nginx
      namespace: mesh-external
      port: 443
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: my-nginx-reference-grant
  namespace: mesh-external
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: default
  to:
    - group: ""
      kind: Service
      name: my-nginx
EOF
{{< /text >}}

TODO: figure out why using an `HTTPRoute`, instead of the above `VirtualService`, doesn't work. It completely ignores the `HTTPRoute` and tries to pass through to the destination service, which times out. The only difference from the above `VirtualService` is that the generated `VirtualService` includes annotation: `internal.istio.io/route-semantics": "gateway"`.

{{< /tab >}}

{{< /tabset >}}

4)  Add a `DestinationRule` to perform mutual TLS origination:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl apply -n istio-system -f - <<EOF
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-mtls-for-nginx
spec:
  host: my-nginx.mesh-external.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: MUTUAL
        credentialName: client-credential # this must match the secret created earlier to hold client certs
        sni: my-nginx.mesh-external.svc.cluster.local
        # subjectAltNames: # can be enabled if the certificate was generated with SAN as specified in previous section
        # - my-nginx.mesh-external.svc.cluster.local
EOF
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-mtls-for-nginx
spec:
  host: my-nginx.mesh-external.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: MUTUAL
        credentialName: client-credential # this must match the secret created earlier to hold client certs
        sni: my-nginx.mesh-external.svc.cluster.local
        # subjectAltNames: # can be enabled if the certificate was generated with SAN as specified in previous section
        # - my-nginx.mesh-external.svc.cluster.local
EOF
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

{{< boilerplate auto-san-validation >}}

5)  Verify that the credential is supplied to the egress gateway and active:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ istioctl -n istio-system proxy-config secret deploy/istio-egressgateway | grep client-credential
kubernetes://client-credential            Cert Chain     ACTIVE     true           1                                          2024-06-04T12:46:28Z     2023-06-05T12:46:28Z
kubernetes://client-credential-cacert     Cert Chain     ACTIVE     true           16491643791048004260                       2024-06-04T12:46:28Z     2023-06-05T12:46:28Z
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ istioctl proxy-config secret deploy/nginx-egressgateway-istio | grep client-credential
kubernetes://client-credential            Cert Chain     ACTIVE     true           1                                          2024-06-04T12:46:28Z     2023-06-05T12:46:28Z
kubernetes://client-credential-cacert     Cert Chain     ACTIVE     true           16491643791048004260                       2024-06-04T12:46:28Z     2023-06-05T12:46:28Z
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

6)  Send an HTTP request to `http://my-nginx.mesh-external.svc.cluster.local`:

    {{< text bash >}}
    $ kubectl exec "$(kubectl get pod -l app=curl -o jsonpath={.items..metadata.name})" -c curl -- curl -sS http://my-nginx.mesh-external.svc.cluster.local
    <!DOCTYPE html>
    <html>
    <head>
    <title>Welcome to nginx!</title>
    ...
    {{< /text >}}

7) Check the log of the egress gateway's proxy:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

If Istio is deployed in the `istio-system` namespace, the command to print the log is:

{{< text bash >}}
$ kubectl logs -l istio=egressgateway -n istio-system | grep 'my-nginx.mesh-external.svc.cluster.local' | grep HTTP
{{< /text >}}

You should see a line similar to the following:

{{< text plain>}}
[2018-08-19T18:20:40.096Z] "GET / HTTP/1.1" 200 - 0 612 7 5 "172.30.146.114" "curl/7.35.0" "b942b587-fac2-9756-8ec6-303561356204" "my-nginx.mesh-external.svc.cluster.local" "172.21.72.197:443"
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

Access the log corresponding to the egress gateway using the Istio-generated pod label:

{{< text bash >}}
$ kubectl logs -l gateway.networking.k8s.io/gateway-name=nginx-egressgateway | grep 'my-nginx.mesh-external.svc.cluster.local' | grep HTTP
{{< /text >}}

You should see a line similar to the following:

{{< text plain >}}
[2024-04-08T20:08:18.451Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 615 5 5 "172.30.239.41" "curl/7.87.0-DEV" "86e54df0-6dc3-46b3-a8b8-139474c32a4d" "my-nginx.mesh-external.svc.cluster.local" "172.30.239.57:443" outbound|443||my-nginx.mesh-external.svc.cluster.local 172.30.239.53:48530 172.30.239.53:443 172.30.239.41:53694 my-nginx.mesh-external.svc.cluster.local default.forward-nginx-from-egress-gateway.0
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

### Cleanup the mutual TLS origination example

1.  Remove the NGINX mutual TLS server resources:

    {{< text bash >}}
    $ kubectl delete secret nginx-server-certs nginx-ca-certs -n mesh-external
    $ kubectl delete configmap nginx-configmap -n mesh-external
    $ kubectl delete service my-nginx -n mesh-external
    $ kubectl delete deployment my-nginx -n mesh-external
    $ kubectl delete namespace mesh-external
    {{< /text >}}

1.  Remove the gateway configuration resources:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl delete secret client-credential -n istio-system
$ kubectl delete gw istio-egressgateway
$ kubectl delete virtualservice direct-nginx-through-egress-gateway
$ kubectl delete destinationrule -n istio-system originate-mtls-for-nginx
$ kubectl delete destinationrule egressgateway-for-nginx
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl delete secret client-credential
$ kubectl delete gtw nginx-egressgateway
$ kubectl delete role nginx-egressgateway-istio-sds
$ kubectl delete rolebinding nginx-egressgateway-istio-sds
$ kubectl delete virtualservice direct-nginx-to-egress-gateway
$ kubectl delete httproute forward-nginx-from-egress-gateway
$ kubectl delete destinationrule originate-mtls-for-nginx
$ kubectl delete destinationrule egressgateway-for-nginx
$ kubectl delete referencegrant my-nginx-reference-grant -n mesh-external
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

3)  Delete the certificates and private keys:

    {{< text bash >}}
    $ rm example.com.crt example.com.key my-nginx.mesh-external.svc.cluster.local.crt my-nginx.mesh-external.svc.cluster.local.key my-nginx.mesh-external.svc.cluster.local.csr client.example.com.crt client.example.com.csr client.example.com.key
    {{< /text >}}

4)  Delete the generated configuration files used in this example:

    {{< text bash >}}
    $ rm ./nginx.conf
    {{< /text >}}

## Cleanup

Delete the `curl` service and deployment:

{{< text bash >}}
$ kubectl delete -f @samples/curl/curl.yaml@
{{< /text >}}
