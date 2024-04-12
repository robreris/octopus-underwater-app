filename="octopus-underwater-app-deployment.yml" 
ecr_repository="<insert ecr repo here>"

cat << EOF > $filename
apiVersion: apps/v1
kind: Deployment
metadata:
  name: octopus-underwater-app
  labels:
    app: octopus-underwater-app
spec:
  selector:
    matchLabels:
        app: octopus-underwater-app
  replicas: 3
  strategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: octopus-underwater-app
    spec:
      containers:
        - name: octopus-underwater-app
          image: $ecr_repository
          ports:
            - containerPort: 80
              protocol: TCP
          imagePullPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  name: octopus-underwater-app-service
spec:
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  type: NodePort
  selector:
    app: octopus-underwater-app
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: octopus-underwater-app-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: octopus-underwater-app-service
              port:
                number: 80
EOF

kubectl apply -f $filename
apppodname=$(kubectl get pod -l app=octopus-underwater-app -o jsonpath='{.items[0].metadata.name}')

ingressdns=""
while [ "$ingressdns" == "" ]; do
  echo "Waiting for ingress resource creation..."
  ingressdns=$(kubectl get ingress octopus-underwater-app-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  sleep 1
done

echo "Ingress DNS: $ingressdns"
status=""
echo -n "Checking app status. Still deploying..."
while [ ! "$status" == "200" ]; do
  status=$(curl -o /dev/null -s -w "%{http_code}\n" http://$ingressdns)
  sleep 1
  echo -n "."
done
echo "Deployment complete."
echo "App will be availabel momentarily at: http://$ingressdns"
echo "To delete deployment, service, and ingress:"
echo "> kubectl delete -f octopus-underwater-app-deployment.yml"
