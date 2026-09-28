ubectl -n argocd patch configmap argocd-cmd-params-cm \
  --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd patch configmap argocd-cm \
  --type merge -p '{"data":{"url":"https://argocd.<your-tailnet>.ts.net"}}'
kubectl -n argocd rollout restart deployment argocd-server