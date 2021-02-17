# Kong Labs - Kubernetes - Notes
Some notes for my experience with the amazing classes with [Kong Labs - Kubernetes](https://www.konglabs.io/kubernetes/)

## Install kong for K8S (dbless)
```
kubectl apply -f https://bit.ly/kong-ingress-dbless
kubectl wait --for=condition=available --timeout=120s --namespace=kong deployment/ingress-kong
export PROXY_IP=$(kubectl get -o jsonpath="{.spec.clusterIP}" service -n kong kong-proxy)
```

## Sample apps (K8S applies)
The echo server:
```
kubectl apply -f https://bit.ly/sample-echo-service
```
The httpbin server:
```
kubectl apply -f https://bit.ly/sample-httpbin-service
```

## Useful curl commands:
-i: for showing the reponse headers [method:GET]
```
curl -i $PROXY_IP/foo
```

-H: to set a specific hostname [method:GET]
```
curl -i -H "Host: example.com" $PROXY_IP/bar/sample
```

-X: to set verb [method:POST]
```
curl -s  $PROXY_IP/foo -X POST
```

-k: to skip certificate validation
```
curl -k Location URL
```

## Useful kubectl commands
Updating a service including a plugin:
```
kubectl patch svc echo -p '{"metadata":{"annotations":{"konghq.com/plugins": "rl-by-ip\n"}}}'
```

Creating secret for kong-consumer:
```
kubectl create secret generic harry-apikey  \
  --from-literal=kongCredType=key-auth  \
  --from-literal=key=my-sooper-secret-key
```

Scale the deployment:
```
kubectl scale --replicas 3 -n kong deployment ingress-kong
```

## Install Redis in K8S
```
kubectl apply -n kong -f https://bit.ly/k8s-redis
```

## Script - Kong - Labs
The file `script-kong-labs.sh` has all the commands that I did in the course and could be used to continue from some previous step.