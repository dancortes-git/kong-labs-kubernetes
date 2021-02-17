#!/bin/bash

# Set up Kubernetes Cluster
## Create a Kubernetes cluster
./launch-k3s.sh

## Verify
# kubectl get nodes

# Deploy Kong for Kubernetes
## Deploy Kong for Kubernetes
kubectl apply -f https://bit.ly/kong-ingress-dbless

## Verify install
kubectl wait --for=condition=available --timeout=120s --namespace=kong deployment/ingress-kong

## Set up environment variables
export PROXY_IP=$(kubectl get -o jsonpath="{.spec.clusterIP}" service -n kong kong-proxy)

## Verify setup
#curl -i http://$PROXY_IP/

# Deploy Sample Services
## Deploy the echo service
kubectl apply -f https://bit.ly/sample-echo-service

## Deploy the httpbin service
kubectl apply -f https://bit.ly/sample-httpbin-service

## Verify
#kubectl get deployment --namespace=default

# Get Started with Kong for Kubernetes
## Configure basic proxy
echo "
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo
  annotations:
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
      - path: /foo
        backend:
          serviceName: echo
          servicePort: 80
" | kubectl apply -f -

## Verify
#curl -i $PROXY_IP/foo

## Set up a Kong Plugin resource
echo "
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: request-id
config:
  header_name: my-request-id
plugin: correlation-id
" | kubectl apply -f -

## Create a new Ingress resource which uses this plugin
echo "
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo-example-com
  annotations:
    konghq.com/plugins: request-id
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - host: example.com
    http:
      paths:
      - path: /bar
        backend:
          serviceName: echo
          servicePort: 80
" | kubectl apply -f -

## Verify
#curl -i -H "Host: example.com" $PROXY_IP/bar/sample

## Configure Kong plugin for a service
## Create a Kong Plugin resource
echo "
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rl-by-ip
config:
  minute: 5
  limit_by: ip
  policy: local
plugin: rate-limiting
" | kubectl apply -f -

## Apply plugin to the services that requires rate-limiting
kubectl patch svc echo -p '{"metadata":{"annotations":{"konghq.com/plugins": "rl-by-ip\n"}}}'

## Verify service is rate-limited
#curl -I  $PROXY_IP/foo
#curl -I -H "Host: example.com"  $PROXY_IP/bar/sample

# Using Kong Plugin resource
## Set up Ingress rule for Kong plugin
## Add ingress resource for echo service
echo '
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
      - path: /foo
        backend:
          serviceName: httpbin
          servicePort: 80
      - path: /bar
        backend:
          serviceName: echo
          servicePort: 80
' | kubectl apply -f -

## Verify endpoints
#curl -i $PROXY_IP/foo/status/200
#curl -i $PROXY_IP/bar

## Add ingress resource for httpbin service
echo '
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo-2
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
      - path: /baz
        backend:
          serviceName: httpbin
          servicePort: 80
' | kubectl apply -f -

## Configure Response-Transformer plugin on Ingress resource
## Create KongPlugin resource
echo '
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: add-response-header
config:
  add:
    headers:
    - "demo: injected-by-kong"
plugin: response-transformer
' | kubectl apply -f -

## Associate plugin with the ingress rule
kubectl patch ingress demo -p '{"metadata":{"annotations":{"konghq.com/plugins":"add-response-header"}}}'

## Verify
#curl -I $PROXY_IP/bar
#curl -i $PROXY_IP/foo/status/200

## What happens if you send request to /baz?
#curl -I $PROXY_IP/baz

## Configure Key-Auth plugin on Service Resource
## Add Kong Key Authentication plugin
echo "
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: httpbin-auth
plugin: key-auth
" | kubectl apply -f -

## Associate plugin to service
kubectl patch service httpbin -p '{"metadata":{"annotations":{"konghq.com/plugins":"httpbin-auth"}}}'

## Verify authentication is required
#curl -I $PROXY_IP/baz
#curl -I $PROXY_IP/foo

## Provision consumers and credentials
echo "
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: harry
  annotations:
    kubernetes.io/ingress.class: kong
username: harry
" | kubectl apply -f -

## Create a Secret resource with an API-key inside it
kubectl create secret generic harry-apikey --from-literal=kongCredType=key-auth --from-literal=key=my-sooper-secret-key

## Associate API-key with the Consumer
echo "
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: harry
  annotations:
    kubernetes.io/ingress.class: kong
username: harry
credentials:
- harry-apikey
" | kubectl apply -f -

## Verify API key
#curl -I $PROXY_IP/foo -H 'apikey: my-sooper-secret-key'
#curl -I $PROXY_IP/baz -H 'apikey: my-sooper-secret-key'

## Configure Rate-Limiting plugin on a global level
## Create a KongPlugin resource
echo "
apiVersion: configuration.konghq.com/v1
kind: KongClusterPlugin
metadata:
  name: global-rate-limit
  annotations:
    kubernetes.io/ingress.class: kong
  labels:
    global: \"true\"
config:
  minute: 5
  limit_by: consumer
  policy: local
plugin: rate-limiting
" | kubectl apply -f -

## Verify rate-limiting on httpbin server
#curl -I $PROXY_IP/foo -H 'apikey: my-sooper-secret-key'

## Verify rate-limiting on echo server
#curl -I $PROXY_IP/bar

## Configure Rate-Limiting plugin for a specific cosumer
## Create a KongPlugin resource
echo "
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: harry-rate-limit
config:
  minute: 10
  limit_by: consumer
  policy: local
plugin: rate-limiting
" | kubectl apply -f -

## Associate resource to the Consumer
echo "
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: harry
  annotations:
    kubernetes.io/ingress.class: kong
    konghq.com/plugins: harry-rate-limit
username: harry
credentials:
- harry-apikey
" | kubectl apply -f -

# Using Kong Ingress resource
## Introduction - Kong Ingress resource
## Set up Ingress rule for Kong Ingress
echo "
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo
  annotations:
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
      - path: /foo
        backend:
          serviceName: echo
          servicePort: 80
" | kubectl apply -f -

## Verify the ingress rule
#curl -i  $PROXY_IP/foo

## Use Kong Ingress with Ingress resource
## Set up a KongIngress resource
echo "
apiVersion: configuration.konghq.com/v1
kind: KongIngress
metadata:
  name: sample-customization
route:
  methods:
  - GET
  strip_path: true
" | kubectl apply -f -

## Associate ingress resource
kubectl patch ingress demo -p '{"metadata":{"annotations":{"konghq.com/override":"sample-customization"}}}'

## Verify
#curl -s  $PROXY_IP/foo -X POST
#curl -s $PROXY_IP/foo/baz

## Use Kong Ingress with Service resource
## Create a Kong Ingress resource
echo "
apiVersion: configuration.konghq.com/v1
kind: KongIngress
metadata:
  name: demo-customization
upstream:
  hash_on: ip
proxy:
  path: /bar/
" | kubectl apply -f -

## Apply plugin to the service
kubectl patch service echo -p '{"metadata":{"annotations":{"configuration.konghq.com":"demo-customization"}}}'

## Verify
#curl $PROXY_IP/foo/baz

## Further Tests
#curl -s  $PROXY_IP/foo | grep "pod IP"

# Configuring a fallback service
## Set up Ingress rule for fallback service
echo '
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
      - path: /cafe
        backend:
          serviceName: echo
          servicePort: 80
' | kubectl apply -f -

## Verify
#curl -i $PROXY_IP/cafe/status/200

## Set up a fallback service
## Create KongPlugin resource
kubectl apply -f fallback-svc.yml

## Create ingress rule
echo "
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: fallback
  annotations:
    kubernetes.io/ingress.class: kong
spec:
  backend:
    serviceName: fallback-svc
    servicePort: 80
" | kubectl apply -f -

## Verify fallback service
## Test it
#curl $PROXY_IP/random-path

# Introduction - HTTPs Redirects
## Set up Ingress rule for HTTPs redirects
echo '
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo-redirect
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
      - path: /foo-redirect
        backend:
          serviceName: httpbin
          servicePort: 80
' | kubectl apply -f -

## Verify
#curl -i  $PROXY_IP/foo-redirect/status/200

## Set up HTTPs redirect
echo "
apiVersion: configuration.konghq.com/v1
kind: KongIngress
metadata:
    name: demo-redirect
route:
  protocols:
  - https
  https_redirect_status_code: 302
" | kubectl apply -f -

## Associate the KongIngress resource
kubectl patch ingress demo-redirect -p '{"metadata":{"annotations":{"konghq.com/override":"https-only"}}}'

## Verify HTTPs redirect
## Test it
#curl $PROXY_IP/foo-redirect/headers -I

## Verify HTTPs access
#curl -k Location URL

# Introduction - Redis for rate-limiting
## Set up ingress rule for Redis
echo '
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo-redis
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
      - path: /foo-redis
        backend:
          serviceName: httpbin-2
          servicePort: 80
' | kubectl apply -f -

## Verify ingress rule
#curl -i $PROXY_IP/foo-redis/status/200

## Set up rate-limiting plugin
## Add rate-limiting plugin
echo "
apiVersion: configuration.konghq.com/v1
kind: KongClusterPlugin
metadata:
  name: global-rate-limit
  annotations:
    kubernetes.io/ingress.class: kong
  labels:
    global: \"true\"
config:
  minute: 5
  policy: local
plugin: rate-limiting
" | kubectl apply -f -

## Verify traffic control
#curl -I $PROXY_IP/foo-redis/headers

## Scale Kong for Kubernetes to multiple pods
kubectl scale --replicas 3 -n kong deployment ingress-kong

## Wait for replicas to deploy
kubectl get pods -n kong

## Verify traffic control
#curl -I $PROXY_IP/foo-redis/headers

## Deploy Redis to your Kubernetes cluster
kubectl apply -n kong -f https://bit.ly/k8s-redis

## Update KongPlugin resource
echo "
apiVersion: configuration.konghq.com/v1
kind: KongClusterPlugin
metadata:
  name: global-rate-limit
  annotations:
    kubernetes.io/ingress.class: kong
  labels:
    global: \"true\"
config:
  minute: 5
  policy: redis
  redis_host: redis
plugin: rate-limiting
" | kubectl apply -f -

## Verify rate-limiting across cluster
## Test it
#curl -I $PROXY_IP/foo-redis/headers

