# Kafka Lab — Manual Installation

> The recommended way is `./deploy.sh` which runs everything automatically.
> This file describes the individual steps for those who want to understand the process.

---

## Prerequisites

```bash
kubectl cluster-info   # Kubernetes active
helm version           # Helm 3+
vault version          # Vault CLI
docker info            # Docker active
```

---

## Step 1 — Vault

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update
kubectl create namespace vault-system

helm install vault hashicorp/vault -n vault-system \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken=root \
  --set ui.enabled=true \
  --set ui.serviceType=NodePort \
  --set ui.serviceNodePort=30372 \
  --set injector.enabled=false

kubectl -n vault-system wait --for=condition=ready pod \
  -l app.kubernetes.io/name=vault --timeout=120s
```

## Step 2 — Load Secrets into Vault

```bash
export VAULT_ADDR="http://localhost:30372"
export VAULT_TOKEN="root"
PASSWORD="your-password"  # min 12 characters

vault secrets enable -version=2 -path=secret kv 2>/dev/null || true
vault kv put secret/kafka/users/admin         password="$PASSWORD"
vault kv put secret/kafka/users/producer-user password="$PASSWORD"
vault kv put secret/kafka/users/consumer-user password="$PASSWORD"
vault kv put secret/kafka/monitoring/grafana  password="$PASSWORD"
vault kv put secret/kafka/jenkins/admin       password="$PASSWORD"
```

## Step 3 — Configure Kubernetes Auth in Vault

```bash
vault auth enable kubernetes 2>/dev/null || true

CA_CERT=$(kubectl get configmap kube-root-ca.crt -n kafka-lab \
  -o jsonpath='{.data.ca\.crt}' 2>/dev/null || \
  kubectl get configmap kube-root-ca.crt -n default \
  -o jsonpath='{.data.ca\.crt}')
echo "$CA_CERT" > /tmp/k8s-ca.crt

JWT=$(kubectl create token vault-auth -n kafka-lab --duration=8760h 2>/dev/null || \
  kubectl create token default --duration=8760h)

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/tmp/k8s-ca.crt \
  token_reviewer_jwt="$JWT"

vault policy write kafka-lab - << 'POLICY'
path "secret/data/kafka/*"     { capabilities = ["read", "list"] }
path "secret/metadata/kafka/*" { capabilities = ["list"] }
POLICY

vault write auth/kubernetes/role/kafka-lab \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=kafka-lab \
  policies=kafka-lab \
  ttl=24h
```

## Step 4 — External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io && helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system --create-namespace \
  --set installCRDs=true --wait
```

## Step 5 — Strimzi Operator

```bash
helm repo add strimzi https://strimzi.io/charts/ && helm repo update
kubectl create namespace kafka-lab
helm install strimzi-operator strimzi/strimzi-kafka-operator \
  --namespace kafka-lab --wait
```

## Step 6 — Kafka Lab

```bash
helm install kafka-lab ./helm -n kafka-lab --timeout 15m
```

## Step 7 — Verify

```bash
kubectl get externalsecret -n kafka-lab   # all SecretSynced: True
kubectl get pods -n kafka-lab              # all Running
open http://localhost:30080                # Kafka UI
```

---

## After a Docker Desktop Restart

Vault runs in dev mode — data is stored in RAM and lost on every restart. Run:

```bash
./scripts/vault/vault-reinit.sh
```

---

## Troubleshooting

**ESO in SecretSyncedError:**
```bash
kubectl describe externalsecret admin-password -n kafka-lab | tail -10
# If "permission denied" -> run vault-reinit.sh
# If "no such path"      -> reload secrets (Step 2)
```

**Kafka UI cannot connect (SaslAuthenticationException):**
```bash
# Secrets are not synced or password is wrong
./scripts/vault/vault-reinit.sh
```

**Namespace stuck in Terminating:**
```bash
for r in kafka kafkanodepool kafkatopic kafkauser kafkaconnect kafkaconnector; do
  kubectl get $r -n kafka-lab -o name 2>/dev/null | xargs -I{} \
    kubectl patch {} -n kafka-lab \
    -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
done
```
