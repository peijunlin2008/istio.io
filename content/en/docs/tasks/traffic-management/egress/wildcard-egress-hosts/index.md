---
title: Egress using Wildcard Hosts
description: Describes how to enable egress traffic for a set of hosts in a common domain, instead of configuring each and every host separately.
keywords: [traffic-management,egress]
weight: 50
aliases:
  - /docs/examples/advanced-gateways/wildcard-egress-hosts/
owner: istio/wg-networking-maintainers
test: yes
---

The [Accessing External Services](/docs/tasks/traffic-management/egress/egress-control) task and
the [Configure an Egress Gateway](/docs/tasks/traffic-management/egress/egress-gateway/) example
describe how to configure egress traffic for specific hostnames, like `edition.cnn.com`.
This example shows how to enable egress traffic for a set of hosts in a common domain, for
example `*.wikipedia.org`, instead of configuring each and every host separately.

## Background

Suppose you want to enable egress traffic in Istio for the `wikipedia.org` sites in all languages.
Each version of `wikipedia.org` in a particular language has its own hostname, e.g., `en.wikipedia.org` and
`de.wikipedia.org` in the English and the German languages, respectively.
You want to enable egress traffic by common configuration items for all the Wikipedia sites,
without the need to specify every language's site separately.

{{< boilerplate gateway-api-support >}}

## Before you begin

*   Install Istio with access logging enabled and with the blocking-by-default outbound traffic policy:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ istioctl install --set profile=demo --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY
{{< /text >}}

{{< tip >}}
You can run this task on an Istio configuration other than the `demo` profile as long as you make sure to
[deploy the Istio egress gateway](/docs/tasks/traffic-management/egress/egress-gateway/#deploy-istio-egress-gateway),
[enable Envoy’s access logging](/docs/tasks/observability/logs/access-log/#enable-envoy-s-access-logging), and
[apply the blocking-by-default outbound traffic policy](/docs/tasks/traffic-management/egress/egress-control/#change-to-the-blocking-by-default-policy)
in your installation.
{{< /tip >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ istioctl install --set profile=minimal -y \
    --set values.pilot.env.PILOT_ENABLE_ALPHA_GATEWAY_API=true \
    --set meshConfig.accessLogFile=/dev/stdout \
    --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

*   Deploy the [curl]({{< github_tree >}}/samples/curl) sample app to use as a test source for sending requests.
    If you have
    [automatic sidecar injection](/docs/setup/additional-setup/sidecar-injection/#automatic-sidecar-injection)
    enabled, run the following command to deploy the sample app:

    {{< text bash >}}
    $ kubectl apply -f @samples/curl/curl.yaml@
    {{< /text >}}

    Otherwise, manually inject the sidecar before deploying the `curl` application with the following command:

    {{< text bash >}}
    $ kubectl apply -f <(istioctl kube-inject -f @samples/curl/curl.yaml@)
    {{< /text >}}

    {{< tip >}}
    You can use any pod with `curl` installed as a test source.
    {{< /tip >}}

*   Set the `SOURCE_POD` environment variable to the name of your source pod:

    {{< text bash >}}
    $ export SOURCE_POD=$(kubectl get pod -l app=curl -o jsonpath={.items..metadata.name})
    {{< /text >}}

## Configure direct traffic to a wildcard host

The first, and simplest, way to access a set of hosts within a common domain is by configuring
a simple `ServiceEntry` with a wildcard host and calling the services directly from the sidecar.
When calling services directly (i.e., not via an egress gateway), the configuration for
a wildcard host is no different than that of any other (e.g., fully qualified) host,
only much more convenient when there are many hosts within the common domain.

{{< warning >}}
Note that the configuration below can be easily bypassed by a malicious application. For a secure egress traffic control,
direct the traffic through an egress gateway.
{{< /warning >}}

{{< warning >}}
Note that the `DNS` resolution cannot be used for wildcard hosts. This is why the `NONE` resolution (omitted since it is
the default) is used in the service entry below.
{{< /warning >}}

1.  Define a `ServiceEntry` for `*.wikipedia.org`:

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: wikipedia
    spec:
      hosts:
      - "*.wikipedia.org"
      ports:
      - number: 443
        name: https
        protocol: HTTPS
    EOF
    {{< /text >}}

1.  Send HTTPS requests to
    [https://en.wikipedia.org](https://en.wikipedia.org) and [https://de.wikipedia.org](https://de.wikipedia.org):

    {{< text bash >}}
    $ kubectl exec "$SOURCE_POD" -c curl -- sh -c 'curl -s https://en.wikipedia.org/wiki/Main_Page | grep -o "<title>.*</title>"; curl -s https://de.wikipedia.org/wiki/Wikipedia:Hauptseite | grep -o "<title>.*</title>"'
    <title>Wikipedia, the free encyclopedia</title>
    <title>Wikipedia – Die freie Enzyklopädie</title>
    {{< /text >}}

### Cleanup direct traffic to a wildcard host

{{< text bash >}}
$ kubectl delete serviceentry wikipedia
{{< /text >}}

## Configure egress gateway traffic to a wildcard host

When all wildcard hosts are served by a single server, the configuration for
egress gateway-based access to a wildcard host is very similar to that of any host, with one exception:
the configured route destination will not be the same as the configured host,
i.e., the wildcard. It will instead be configured with the host of the single server for
the set of domains.

1.  Create an egress `Gateway` for _*.wikipedia.org_ and route rules
    to direct the traffic through the egress gateway and from the egress gateway to the external service:

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
    - "*.wikipedia.org"
    tls:
      mode: PASSTHROUGH
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-wikipedia
spec:
  host: istio-egressgateway.istio-system.svc.cluster.local
  subsets:
    - name: wikipedia
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: direct-wikipedia-through-egress-gateway
spec:
  hosts:
  - "*.wikipedia.org"
  gateways:
  - mesh
  - istio-egressgateway
  tls:
  - match:
    - gateways:
      - mesh
      port: 443
      sniHosts:
      - "*.wikipedia.org"
    route:
    - destination:
        host: istio-egressgateway.istio-system.svc.cluster.local
        subset: wikipedia
        port:
          number: 443
      weight: 100
  - match:
    - gateways:
      - istio-egressgateway
      port: 443
      sniHosts:
      - "*.wikipedia.org"
    route:
    - destination:
        host: www.wikipedia.org
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
kind: Gateway
metadata:
  name: wikipedia-egress-gateway
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: tls
    hostname: "*.wikipedia.org"
    port: 443
    protocol: TLS
    tls:
      mode: Passthrough
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: direct-wikipedia-to-egress-gateway
spec:
  parentRefs:
  - kind: ServiceEntry
    group: networking.istio.io
    name: wikipedia
  rules:
  - backendRefs:
    - name: wikipedia-egress-gateway-istio
      port: 443
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: forward-wikipedia-from-egress-gateway
spec:
  parentRefs:
  - name: wikipedia-egress-gateway
  hostnames:
  - "*.wikipedia.org"
  rules:
  - backendRefs:
    - kind: Hostname
      group: networking.istio.io
      name: www.wikipedia.org
      port: 443
---
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: wikipedia
spec:
  hosts:
  - "*.wikipedia.org"
  ports:
  - number: 443
    name: https
    protocol: HTTPS
EOF
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

2)  Create a `ServiceEntry` for the destination server, _www.wikipedia.org_:

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: www-wikipedia
    spec:
      hosts:
      - www.wikipedia.org
      ports:
      - number: 443
        name: https
        protocol: HTTPS
      resolution: DNS
    EOF
    {{< /text >}}

3)  Send HTTPS requests to
    [https://en.wikipedia.org](https://en.wikipedia.org) and [https://de.wikipedia.org](https://de.wikipedia.org):

    {{< text bash >}}
    $ kubectl exec "$SOURCE_POD" -c curl -- sh -c 'curl -s https://en.wikipedia.org/wiki/Main_Page | grep -o "<title>.*</title>"; curl -s https://de.wikipedia.org/wiki/Wikipedia:Hauptseite | grep -o "<title>.*</title>"'
    <title>Wikipedia, the free encyclopedia</title>
    <title>Wikipedia – Die freie Enzyklopädie</title>
    {{< /text >}}

4)  Check the statistics of the egress gateway's proxy for the counter that corresponds to your
    requests to _*.wikipedia.org_:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl exec "$(kubectl get pod -l istio=egressgateway -n istio-system -o jsonpath='{.items[0].metadata.name}')" -c istio-proxy -n istio-system -- pilot-agent request GET clusters | grep '^outbound|443||www.wikipedia.org.*cx_total:'
outbound|443||www.wikipedia.org::208.80.154.224:443::cx_total::2
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl exec "$(kubectl get pod -l gateway.networking.k8s.io/gateway-name=wikipedia-egress-gateway -o jsonpath='{.items[0].metadata.name}')" -c istio-proxy -- pilot-agent request GET clusters | grep '^outbound|443||www.wikipedia.org.*cx_total:'
outbound|443||www.wikipedia.org::208.80.154.224:443::cx_total::2
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

### Cleanup egress gateway traffic to a wildcard host

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl delete serviceentry www-wikipedia
$ kubectl delete gateway istio-egressgateway
$ kubectl delete virtualservice direct-wikipedia-through-egress-gateway
$ kubectl delete destinationrule egressgateway-for-wikipedia
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl delete se wikipedia
$ kubectl delete se www-wikipedia
$ kubectl delete gtw wikipedia-egress-gateway
$ kubectl delete tlsroute direct-wikipedia-to-egress-gateway
$ kubectl delete tlsroute forward-wikipedia-from-egress-gateway
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

## Wildcard configuration for arbitrary domains

The configuration in the previous section worked because all the `*.wikipedia.org` sites can be served by any one
of the `wikipedia.org` servers. However, this is not always the case. For example, you may want to configure egress
control for access to more general wildcard domains like `*.com` or `*.org`. Configuring traffic to arbitrary
wildcard domains introduces a challenge for Istio gateways; an Istio gateway can only be configured to route traffic
to predefined hosts, predefined IP addresses, or to the original destination IP address of the request.

In the previous section you configured the virtual service to direct traffic to the predefined host `www.wikipedia.org`.
In the general case, however, you don't know the host or IP address that can serve an arbitrary host received in a
request, which leaves the original destination address of the request as the only value with which to route the request.
Unfortunately, when using an egress gateway, the original destination address of the request is lost since the original
request is redirected to the gateway, causing the destination IP address to become the IP address of the gateway.

Although not as easy and somewhat fragile as it relies on Istio implementation details, you can use
[Envoy filters](/docs/reference/config/networking/envoy-filter/) to configure a gateway to support arbitrary domains
by using the [SNI](https://en.wikipedia.org/wiki/Server_Name_Indication) value in an HTTPS, or any TLS, request to
identify the original destination to which to route the request. One example of this configuration approach can be
found in [routing egress traffic to wildcard destinations](/blog/2023/egress-sni/).

## Cleanup

* Shutdown the [curl]({{< github_tree >}}/samples/curl) service:

    {{< text bash >}}
    $ kubectl delete -f @samples/curl/curl.yaml@
    {{< /text >}}

* Uninstall Istio from your cluster:

    {{< text bash >}}
    $ istioctl uninstall --purge -y
    {{< /text >}}
