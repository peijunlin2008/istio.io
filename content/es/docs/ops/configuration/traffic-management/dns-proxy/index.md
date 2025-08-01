---
title: DNS Proxying
description: How to configure DNS proxying.
weight: 60
keywords: [traffic-management,dns,virtual-machine]
owner: istio/wg-networking-maintainers
test: yes
---

In addition to capturing application traffic, Istio can also capture DNS requests to improve the performance and usability of your mesh.
When proxying DNS, all DNS requests from an application will be redirected to the sidecar or ztunnel proxy, which stores a local mapping of domain names to IP addresses. If the request can be handled by the proxy, it will directly return a response to the application, avoiding a roundtrip to the upstream DNS server. Otherwise, the request is forwarded upstream following the standard `/etc/resolv.conf` DNS configuration.

While Kubernetes provides DNS resolution for Kubernetes `Service`s out of the box, any custom `ServiceEntry`s will not be recognized. With this feature, `ServiceEntry` addresses can be resolved without requiring custom configuration of a DNS server. For Kubernetes `Service`s, the DNS response will be the same, but with reduced load on `kube-dns` and increased performance.

This functionality is also available for services running outside of Kubernetes. This means that all internal services can be resolved without clunky workarounds to expose Kubernetes DNS entries outside of the cluster.

## Getting started

Istio will generally route traffic based on HTTP headers. If routing based on a HTTP header is not possible - in ambient mode, or with TCP traffic in sidecar mode - DNS proxy can be enabled.

In ambient mode, the ztunnel only sees traffic at capa 4, and does not have access to HTTP headers. Therefore, DNS proxying is required to enable resolution of `ServiceEntry` addresses, especially in the case of [sending egress traffic to waypoints](https://github.com/istio/istio/wiki/Troubleshooting-Istio-Ambient#scenario-ztunnel-is-not-sending-egress-traffic-to-waypoints).

### Ambient mode

DNS proxying is enabled by default in ambient mode from Istio 1.25 onwards.

For versions prior to 1.25, you can enable DNS capture by setting `values.cni.ambient.dnsCapture=true` and `values.pilot.env.PILOT_ENABLE_IP_AUTOALLOCATE=true` during installation.

### Sidecar mode

This feature is not currently enabled by default. To enable it, install Istio with the following settings:

{{< text bash >}}
$ cat <<EOF | istioctl install -y -f -
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    defaultConfig:
      proxyMetadata:
        # Enable basic DNS proxying
        ISTIO_META_DNS_CAPTURE: "true"
EOF
{{< /text >}}

This can also be enabled on a per-pod basis with the [`proxy.istio.io/config` annotation](/es/docs/reference/config/annotations/):

{{< text syntax=yaml snip_id=none >}}
kind: Deployment
metadata:
  name: curl
spec:
...
  template:
    metadata:
      annotations:
        proxy.istio.io/config: |
          proxyMetadata:
            ISTIO_META_DNS_CAPTURE: "true"
...
{{< /text >}}

{{< tip >}}
When deploying to a VM using [`istioctl workload entry configure`](/es/docs/setup/install/virtual-machine/), basic DNS proxying will be enabled by default.
{{< /tip >}}

## DNS capture in action

To try out the DNS capture, first set up a `ServiceEntry` for some external service:

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: external-address
spec:
  addresses:
  - 198.51.100.1
  hosts:
  - address.internal
  ports:
  - name: http
    number: 80
    protocol: HTTP
EOF
{{< /text >}}

Bring up a client application to initiate the DNS request:

{{< text bash >}}
$ kubectl label namespace default istio-injection=enabled --overwrite
$ kubectl apply -f @samples/curl/curl.yaml@
{{< /text >}}

Without the DNS capture, a request to `address.internal` would likely fail to resolve. Once this is enabled, you should instead get a response back based on the configured `address`:

{{< text bash >}}
$ kubectl exec deploy/curl -- curl -sS -v address.internal
*   Trying 198.51.100.1:80...
{{< /text >}}

## Address auto-allocation

In the above example, you had a predefined IP address for the service to which you sent the request. However, it's common to access external services that do not have stable addresses, and instead rely on DNS. In this case, the DNS proxy will not have enough information to return a response, and will need to forward DNS requests upstream.

This is especially problematic with TCP traffic. Unlike HTTP requests, which are routed based on `Host` headers, TCP carries much less information; you can only route on the destination IP and port number. Because you don't have a stable IP for the backend, you cannot route based on that either, leaving only port number, which leads to conflicts when multiple `ServiceEntry`s for TCP services share the same port. Refer
to [the following section](#external-tcp-services-without-vips) for more details.

To work around these issues, the DNS proxy additionally supports automatically allocating addresses for `ServiceEntry`s that do not explicitly define one. The DNS response will include a distinct and automatically assigned address for each `ServiceEntry`. The proxy is then configured to match requests to this IP address, and forward the request to the corresponding `ServiceEntry`. Istio will automatically allocate non-routable VIPs (from the Class E subnet) to such services as long as they do not use a wildcard host. The Istio agent on the sidecar will use the VIPs as responses to the DNS lookup queries from the application. Envoy can now clearly distinguish traffic bound for each external TCP service and forward it to the right target.

{{< warning >}}
Because this feature modifies DNS responses, it may not be compatible with all applications.
{{< /warning >}}

To try this out, configure another `ServiceEntry`:

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: external-auto
spec:
  hosts:
  - auto.internal
  ports:
  - name: http
    number: 80
    protocol: HTTP
  resolution: DNS
EOF
{{< /text >}}

Now, send a request:

{{< text bash >}}
$ kubectl exec deploy/curl -- curl -sS -v auto.internal
*   Trying 240.240.0.1:80...
{{< /text >}}

As you can see, the request is sent to an automatically allocated address, `240.240.0.1`. These addresses will be picked from the `240.240.0.0/16` reserved IP address range to avoid conflicting with real services.

Users also have the flexibility for more granular configuration by adding the label `networking.istio.io/enable-autoallocate-ip="true/false"` to their `ServiceEntry`. This label configures whether a `ServiceEntry` without any `spec.addresses` set should get an IP address automatically allocated for it.

To try this out, update the existing `ServiceEntry` with the opt-out label:

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: external-auto
  labels:
    networking.istio.io/enable-autoallocate-ip: "false"
spec:
  hosts:
  - auto.internal
  ports:
  - name: http
    number: 80
    protocol: HTTP
  resolution: DNS
EOF
{{< /text >}}

Now, send a request and verify that the auto allocation is no longer happening:

{{< text bash >}}
$ kubectl exec deploy/curl -- curl -sS -v auto.internal
* Could not resolve host: auto.internal
* shutting down connection #0
{{< /text >}}

## External TCP services without VIPs

By default, Istio has a limitation when routing external TCP traffic because it is unable to distinguish between multiple TCP services on the same port. This limitation is particularly apparent when using third party databases such as AWS Relational Database Service or any database setup with geographical redundancy. Similar, but different external TCP services, cannot be handled separately by default. For the sidecar to distinguish traffic between two different TCP services that are outside of the mesh, the services must be on different ports or they need to have globally unique VIPs.

For example, if you have two external database services, `mysql-instance1` and `mysql-instance2`, and you create service entries for both, client sidecars will still have a single listener on `0.0.0.0:{port}` that looks up the IP address of only `mysql-instance1`, from public DNS servers, and forwards traffic to it. It cannot route traffic to `mysql-instance2` because it has no way of distinguishing whether traffic arriving at `0.0.0.0:{port}` is bound for `mysql-instance1` or `mysql-instance2`.

The following example shows how DNS proxying can be used to solve this problem.
A virtual IP address will be assigned to every service entry so that client sidecars can clearly distinguish traffic bound for each external TCP service.

1.  Update the Istio configuration specified in the [Getting Started](#getting-started) section to also configure `discoverySelectors` that restrict the mesh to namespaces with `istio-injection` enabled. This will let us use any other namespaces in the cluster to run TCP services outside of the mesh.

    {{< text bash >}}
    $ cat <<EOF | istioctl install -y -f -
    apiVersion: install.istio.io/v1alpha1
    kind: IstioOperator
    spec:
      meshConfig:
        defaultConfig:
          proxyMetadata:
            # Enable basic DNS proxying
            ISTIO_META_DNS_CAPTURE: "true"
        # discoverySelectors configuration below is just used for simulating the external service TCP scenario,
        # so that we do not have to use an external site for testing.
        discoverySelectors:
        - matchLabels:
            istio-injection: enabled
    EOF
    {{< /text >}}

1.  Deploy the first external sample TCP application:

    {{< text bash >}}
    $ kubectl create ns external-1
    $ kubectl -n external-1 apply -f samples/tcp-echo/tcp-echo.yaml
    {{< /text >}}

1.  Deploy the second external sample TCP application:

    {{< text bash >}}
    $ kubectl create ns external-2
    $ kubectl -n external-2 apply -f samples/tcp-echo/tcp-echo.yaml
    {{< /text >}}

1.  Configure `ServiceEntry` to reach external services:

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: external-svc-1
    spec:
      hosts:
      - tcp-echo.external-1.svc.cluster.local
      ports:
      - name: external-svc-1
        number: 9000
        protocol: TCP
      resolution: DNS
    ---
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: external-svc-2
    spec:
      hosts:
      - tcp-echo.external-2.svc.cluster.local
      ports:
      - name: external-svc-2
        number: 9000
        protocol: TCP
      resolution: DNS
    EOF
    {{< /text >}}

1.  Verify listeners are configured separately for each service at the client side:

    {{< text bash >}}
    $ istioctl pc listener deploy/curl | grep tcp-echo | awk '{printf "ADDRESS=%s, DESTINATION=%s %s\n", $1, $4, $5}'
    ADDRESS=240.240.105.94, DESTINATION=Cluster: outbound|9000||tcp-echo.external-2.svc.cluster.local
    ADDRESS=240.240.69.138, DESTINATION=Cluster: outbound|9000||tcp-echo.external-1.svc.cluster.local
    {{< /text >}}

## Cleanup

{{< text bash >}}
$ kubectl -n external-1 delete -f @samples/tcp-echo/tcp-echo.yaml@
$ kubectl -n external-2 delete -f @samples/tcp-echo/tcp-echo.yaml@
$ kubectl delete -f @samples/curl/curl.yaml@
$ istioctl uninstall --purge -y
$ kubectl delete ns istio-system external-1 external-2
$ kubectl label namespace default istio-injection-
{{< /text >}}
