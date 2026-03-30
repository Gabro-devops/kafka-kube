# Vault Secret Management Guide

## Overview

This project uses **HashiCorp Vault** for centralized and secure secret management, integrated with Kubernetes via the **External Secrets Operator (ESO)**.

### Advantages over hardcoded secrets

1. **Security**: No passwords in Git or values.yaml
2. **Centralization**: A single management point for all secrets
3. **Audit Trail**: Vault tracks all secret access
4. **Rotation**: Secrets can be rotated without restarting pods
5. **Encryption at Rest**: Secrets encrypted in Vault
6. **Access Control**: Granular policies for access

---

## Architecture

```
Kubernetes Cluster
  |
  +-- External Secrets Operator
       |
       +-- reads from Vault
       |
       +-- creates Kubernetes Secrets
            |
            +-- mounted by pods (Kafka, Jenkins, Grafana, Kafka UI)
```

---

## Part 1: Vault Server Setup

### Option A: Vault in Kubernetes (Recommended for LAB)

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
kubectl create namespace vault-system

helm upgrade --install vault hashicorp/vault -n vault-system \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken=root \
  --set ui.enabled=true \
  --set ui.serviceType=NodePort \
  --set ui.serviceNodePort=30372 \
  --set injector.enabled=false

kubectl -n vault-system wait --for=condition=ready pod \
  -l app.kubernetes.io/name=vault --timeout=120s
```

> **WARNING**: Dev mode stores data in RAM. Data is lost on every pod restart.
> Use `./scripts/vault/vault-reinit.sh` to restore after a restart.

### Option B: External Vault (Recommended for Production)

If you already have an existing Vault, update the address in `values.yaml`:

```yaml
vault:
  address: "https://vault.example.com:8200"
```

---

## Part 2: Vault Configuration

### 1. Enable KV Secrets Engine

```bash
export VAULT_ADDR="http://localhost:30372"
export VAULT_TOKEN="root"

vault secrets enable -version=2 -path=secret kv
```

### 2. Load Secrets

```bash
vault kv put secret/kafka/users/admin         password="YourPassword123!"
vault kv put secret/kafka/users/producer-user password="YourPassword123!"
vault kv put secret/kafka/users/consumer-user password="YourPassword123!"
vault kv put secret/kafka/monitoring/grafana  password="YourPassword123!"
vault kv put secret/kafka/jenkins/admin       password="YourPassword123!"

# Verify
vault kv list secret/kafka/users
vault kv get secret/kafka/users/admin
```

### 3. Configure Kubernetes Auth

```bash
vault auth enable kubernetes 2>/dev/null || true

CA_CERT=$(kubectl get configmap kube-root-ca.crt -n kafka-lab \
  -o jsonpath='{.data.ca\.crt}')
echo "$CA_CERT" > /tmp/k8s-ca.crt

JWT=$(kubectl create token vault-auth -n kafka-lab --duration=8760h)

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/tmp/k8s-ca.crt \
  token_reviewer_jwt="$JWT"
```

### 4. Create Policy

```bash
vault policy write kafka-lab - << 'POLICY'
path "secret/data/kafka/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/kafka/*" {
  capabilities = ["list"]
}
POLICY
```

### 5. Create Role

```bash
vault write auth/kubernetes/role/kafka-lab \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=kafka-lab \
  policies=kafka-lab \
  ttl=24h
```

---

## Part 3: External Secrets Operator (ESO)

ESO reads secrets from Vault and creates Kubernetes Secrets automatically.

### SecretStore

The `SecretStore` resource defines how to connect to Vault:

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: kafka-lab
spec:
  provider:
    vault:
      server: "http://vault.vault-system.svc.cluster.local:8200"
      path: "secret"
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: kafka-lab
          serviceAccountRef:
            name: vault-auth
```

### ExternalSecret

Each ExternalSecret defines which secret to sync:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: admin-password
  namespace: kafka-lab
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: admin-password
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        password: "{{ .password }}"
  data:
    - secretKey: password
      remoteRef:
        key: kafka/users/admin
        property: password
```

---

## Troubleshooting

### SecretSyncedError

```bash
# Check ExternalSecret status
kubectl describe externalsecret admin-password -n kafka-lab

# Check ESO logs
kubectl -n external-secrets-system logs -l app.kubernetes.io/name=external-secrets

# Quick fix: restore Vault
./scripts/vault/vault-reinit.sh
```

### Permission denied

```bash
# Test Vault token capabilities
vault token capabilities secret/data/kafka/users/admin

# Verify policy
vault policy read kafka-lab
```

### Vault unreachable

```bash
# Test connectivity from inside the cluster
kubectl run test --rm -it --image=curlimages/curl \
  -- curl http://vault.vault-system.svc:8200/v1/sys/health
```

---

## After a Docker Desktop Restart

Vault dev mode loses all data on restart. Run:

```bash
./scripts/vault/vault-reinit.sh
```

The script restores everything in ~30 seconds.
