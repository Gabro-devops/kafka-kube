# GUIDA VAULT SECRET MANAGEMENT

## Panoramica

Questo progetto utilizza **HashiCorp Vault** per la gestione centralizzata e sicura dei secret, integrato con Kubernetes tramite **External Secrets Operator (ESO)**.

### Vantaggi rispetto a secret hardcoded

1. **Sicurezza**: Nessuna password in Git o values.yaml
2. **Centralizzazione**: Un unico punto di gestione per tutti i secret
3. **Audit Trail**: Vault traccia tutti gli accessi ai secret
4. **Rotation**: Possibilità di ruotare i secret senza riavviare i pod
5. **Encryption at Rest**: Secret crittografati in Vault
6. **Access Control**: Politiche granulari per l'accesso

---

## Architettura

```

 Kubernetes Cluster 


 External Secrets 
 Operator 


 Crea Secret K8s 


 Kubernetes 
 Secret 


 Monta Secret 
 Legge Secret 

 Kafka / Jenkins 
 / Grafana 




 TLS


 HashiCorp Vault 
 (External) 

```

---

## PARTE 1: Setup Vault Server

### Opzione A: Vault in Kubernetes (Consigliato per LAB)

```bash
# 1. Aggiungi Helm repo HashiCorp
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# 2. Crea namespace per Vault
kubectl create namespace vault-system

# 3. Deploy Vault in dev mode (SOLO PER LAB!)
cat <<EOF > vault-values.yaml
server:
 dev:
 enabled: true
 devRootToken: "root"

 # Per PRODUZIONE, usa questo invece:
 # ha:
 # enabled: true
 # replicas: 3
 # dataStorage:
 # enabled: true
 # size: 10Gi
 # auditStorage:
 # enabled: true
 # size: 10Gi

 service:
 type: ClusterIP

ui:
 enabled: true
 serviceType: NodePort
 serviceNodePort: 30082

injector:
 enabled: false
EOF

helm install vault hashicorp/vault \
 --namespace vault-system \
 --values vault-values.yaml

# 4. Verifica deployment
kubectl -n vault-system get pods
kubectl -n vault-system get svc
```

### Opzione B: Vault Esterno (Consigliato per PRODUZIONE)

Se hai già un Vault esistente, usa il suo indirizzo in `values.yaml`:

```yaml
vault:
 address: "https://vault.example.com:8200"
```

---

## PARTE 2: Configurazione Vault

### 1. Accedi a Vault

```bash
# Se Vault è in K8s
kubectl -n vault-system exec -it vault-0 -- /bin/sh

# Imposta variabili ambiente
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root' # In produzione usa token appropriato

# Login
vault login $VAULT_TOKEN
```

### 2. Abilita KV Secrets Engine v2

```bash
# Verifica se già abilitato
vault secrets list

# Abilita KV v2 (se non presente)
vault secrets enable -version=2 -path=secret kv

# Verifica
vault secrets list -detailed
```

### 3. Crea i Secret in Vault

```bash
# Secret per Kafka Users
vault kv put secret/kafka/users/admin password="SuperSecureAdminPass123!"
vault kv put secret/kafka/users/producer-user password="ProducerSecurePass456!"
vault kv put secret/kafka/users/consumer-user password="ConsumerSecurePass789!"

# Secret per Monitoring
vault kv put secret/kafka/monitoring/grafana password="GrafanaAdminPass999!"

# Secret per Jenkins
vault kv put secret/kafka/jenkins/admin password="JenkinsAdminPass777!"

# Verifica creazione
vault kv list secret/kafka/users
vault kv get secret/kafka/users/admin
```

### 4. Configura Kubernetes Auth Method

```bash
# Esci dal pod Vault (se ci sei dentro)
exit

# Ottieni Service Account Token Reviewer
SA_JWT_TOKEN=$(kubectl -n kafka-lab get secret \
 $(kubectl -n kafka-lab get sa vault-auth -o jsonpath='{.secrets[0].name}') \
 -o jsonpath='{.data.token}' | base64 --decode)

SA_CA_CRT=$(kubectl -n kafka-lab get secret \
 $(kubectl -n kafka-lab get sa vault-auth -o jsonpath='{.secrets[0].name}') \
 -o jsonpath='{.data.ca\.crt}' | base64 --decode)

K8S_HOST=$(kubectl config view --minify --flatten \
 -o jsonpath='{.clusters[0].cluster.server}')

# Torna in Vault
kubectl -n vault-system exec -it vault-0 -- /bin/sh

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Abilita Kubernetes auth
vault auth enable kubernetes

# Configura Kubernetes auth
vault write auth/kubernetes/config \
 token_reviewer_jwt="$SA_JWT_TOKEN" \
 kubernetes_host="$K8S_HOST" \
 kubernetes_ca_cert="$SA_CA_CRT" \
 issuer="https://kubernetes.default.svc.cluster.local"
```

### 5. Crea Policy per i Secret

```bash
# Policy per kafka-lab namespace
cat <<EOF > /tmp/kafka-lab-policy.hcl
# Lettura secret Kafka users
path "secret/data/kafka/users/*" {
 capabilities = ["read", "list"]
}

# Lettura secret monitoring
path "secret/data/kafka/monitoring/*" {
 capabilities = ["read", "list"]
}

# Lettura secret Jenkins
path "secret/data/kafka/jenkins/*" {
 capabilities = ["read", "list"]
}

# Metadati
path "secret/metadata/kafka/*" {
 capabilities = ["list"]
}
EOF

# Carica policy
vault policy write kafka-lab /tmp/kafka-lab-policy.hcl

# Verifica policy
vault policy read kafka-lab
```

### 6. Crea Role per Kubernetes Auth

```bash
# Role per il namespace kafka-lab
vault write auth/kubernetes/role/kafka-lab \
 bound_service_account_names=vault-auth \
 bound_service_account_namespaces=kafka-lab \
 policies=kafka-lab \
 ttl=24h

# Verifica role
vault read auth/kubernetes/role/kafka-lab
```

---

## PARTE 3: Setup External Secrets Operator

### 1. Installa External Secrets Operator

```bash
# Aggiungi Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Installa ESO
helm install external-secrets \
 external-secrets/external-secrets \
 --namespace external-secrets-system \
 --create-namespace \
 --set installCRDs=true

# Verifica installazione
kubectl -n external-secrets-system get pods
kubectl get crd | grep external-secrets
```

### 2. Verifica CRD installate

```bash
kubectl get crd | grep external-secrets

# Dovresti vedere:
# externalsecrets.external-secrets.io
# secretstores.external-secrets.io
# clustersecretstores.external-secrets.io
```

---

## PARTE 4: Deploy Kafka Lab con Vault

### 1. Verifica Configurazione values.yaml

```yaml
vault:
 enabled: true
 address: "http://vault.vault-system.svc.cluster.local:8200"
 kvPath: "secret/data/kafka"
 auth:
 method: kubernetes
 serviceAccount: vault-auth
 role: kafka-lab
 refreshInterval: 1h
```

### 2. Deploy del Chart

```bash
# Crea namespace
kubectl create namespace kafka-lab

# Deploy con Helm
helm install kafka-lab ./helm \
 --namespace kafka-lab \
 --values helm/values.yaml

# Monitora creazione risorse
watch kubectl -n kafka-lab get externalsecrets,secretstores,secrets
```

### 3. Verifica Secret Creation

```bash
# Verifica SecretStore
kubectl -n kafka-lab get secretstore vault-backend -o yaml

# Verifica External Secrets
kubectl -n kafka-lab get externalsecrets

# Output atteso:
# NAME STORE REFRESH INTERVAL STATUS
# admin-password vault-backend 1h SecretSynced
# producer-user-password vault-backend 1h SecretSynced
# consumer-user-password vault-backend 1h SecretSynced
# grafana-admin-secret vault-backend 1h SecretSynced
# jenkins-admin-secret vault-backend 1h SecretSynced

# Verifica Secret creati
kubectl -n kafka-lab get secrets | grep -E "admin|producer|consumer|grafana|jenkins"

# Controlla contenuto di un secret (decodificato)
kubectl -n kafka-lab get secret admin-password -o jsonpath='{.data.password}' | base64 -d
```

### 4. Verifica Kafka Users

```bash
# Attendi che Strimzi crei gli utenti
kubectl -n kafka-lab get kafkauser

# Output atteso:
# NAME CLUSTER AUTHENTICATION AUTHORIZATION READY
# admin kafka-cluster scram-sha-512 simple True
# producer-user kafka-cluster scram-sha-512 simple True
# consumer-user kafka-cluster scram-sha-512 simple True

# Verifica dettagli utente
kubectl -n kafka-lab get kafkauser admin -o yaml
```

---

## PARTE 5: Testing e Verifica

### Test 1: Verifica Autenticazione Kafka

```bash
# Ottieni bootstrap server
BOOTSTRAP=$(kubectl -n kafka-lab get kafka kafka-cluster -o jsonpath='{.status.listeners[?(@.name=="tls")].bootstrapServers}')

# Ottieni password admin da secret
ADMIN_PASS=$(kubectl -n kafka-lab get secret admin-password -o jsonpath='{.data.password}' | base64 -d)

# Crea JAAS config
cat <<EOF > /tmp/jaas.conf
KafkaClient {
 org.apache.kafka.common.security.scram.ScramLoginModule required
 username="admin"
 password="$ADMIN_PASS";
};
EOF

# Test connessione (da un pod con kafka tools)
kubectl -n kafka-lab run kafka-test-pod --rm -it \
 --image=quay.io/strimzi/kafka:latest-kafka-3.7.0 \
 --restart=Never \
 -- bin/kafka-topics.sh \
 --bootstrap-server $BOOTSTRAP \
 --command-config /tmp/jaas.conf \
 --list
```

### Test 2: Verifica Grafana Login

```bash
# Port-forward Grafana
kubectl -n kafka-lab port-forward svc/grafana 3000:3000 &

# Ottieni password
GRAFANA_PASS=$(kubectl -n kafka-lab get secret grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d)

echo "Grafana URL: http://localhost:3000"
echo "Username: admin"
echo "Password: $GRAFANA_PASS"

# Apri browser e testa login
```

### Test 3: Verifica Jenkins Login

```bash
# Ottieni NodePort
JENKINS_PORT=$(kubectl -n kafka-lab get svc jenkins -o jsonpath='{.spec.ports[0].nodePort}')

# Ottieni password
JENKINS_PASS=$(kubectl -n kafka-lab get secret jenkins-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d)

echo "Jenkins URL: http://<NODE_IP>:$JENKINS_PORT"
echo "Username: admin"
echo "Password: $JENKINS_PASS"
```

### Test 4: Verifica Secret Refresh

```bash
# Cambia password in Vault
kubectl -n vault-system exec -it vault-0 -- vault kv put secret/kafka/users/admin password="NewPassword123!"

# Attendi refresh (default 1h, o forza riconciliazione)
kubectl -n kafka-lab annotate externalsecret admin-password \
 force-sync=$(date +%s) --overwrite

# Verifica nuovo secret
sleep 5
kubectl -n kafka-lab get secret admin-password -o jsonpath='{.data.password}' | base64 -d
# Output: NewPassword123!
```

---

## PARTE 6: Troubleshooting

### External Secrets non si sincronizzano

```bash
# Controlla status External Secret
kubectl -n kafka-lab describe externalsecret admin-password

# Controlla logs ESO
kubectl -n external-secrets-system logs -l app.kubernetes.io/name=external-secrets

# Verifica connectivity a Vault
kubectl -n kafka-lab run vault-test --rm -it \
 --image=curlimages/curl:latest \
 --restart=Never \
 -- curl -k http://vault.vault-system.svc.cluster.local:8200/v1/sys/health
```

### Vault Auth fallisce

```bash
# Verifica ServiceAccount
kubectl -n kafka-lab get sa vault-auth

# Verifica SecretStore
kubectl -n kafka-lab get secretstore vault-backend -o yaml

# Test manuale auth
kubectl -n vault-system exec -it vault-0 -- vault read auth/kubernetes/role/kafka-lab
```

### Secret non vengono caricati nei pod

```bash
# Verifica che il secret esista
kubectl -n kafka-lab get secret admin-password

# Verifica mount del secret nel pod
kubectl -n kafka-lab describe pod <pod-name>

# Controlla env variables
kubectl -n kafka-lab exec <pod-name> -- env | grep PASSWORD
```

---

## PARTE 7: Best Practices Produzione

### 1. High Availability Vault

```yaml
# helm/vault-prod-values.yaml
server:
 ha:
 enabled: true
 replicas: 3
 raft:
 enabled: true
 setNodeId: true
 config: |
 ui = true
 listener "tcp" {
 tls_disable = 0
 address = "[::]:8200"
 cluster_address = "[::]:8201"
 tls_cert_file = "/vault/tls/tls.crt"
 tls_key_file = "/vault/tls/tls.key"
 }

 storage "raft" {
 path = "/vault/data"
 }

 service_registration "kubernetes" {}
```

### 2. TLS per Vault

```bash
# Genera certificati (o usa cert-manager)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
 -keyout vault.key \
 -out vault.crt \
 -subj "/CN=vault.vault-system.svc"

# Crea secret
kubectl -n vault-system create secret tls vault-tls \
 --cert=vault.crt \
 --key=vault.key

# Aggiorna values.yaml
vault:
 address: "https://vault.vault-system.svc.cluster.local:8200"
```

### 3. Policy Granulari

```hcl
# Policy separata per ogni componente
path "secret/data/kafka/users/admin" {
 capabilities = ["read"]
}

path "secret/data/kafka/monitoring/grafana" {
 capabilities = ["read"]
}

# Deny esplicito per altri path
path "secret/*" {
 capabilities = ["deny"]
}
```

### 4. Audit Logging

```bash
# Abilita audit in Vault
vault audit enable file file_path=/vault/audit/audit.log

# Verifica log
kubectl -n vault-system exec -it vault-0 -- tail -f /vault/audit/audit.log
```

### 5. Secret Rotation

```bash
# Script automatico per rotation
#!/bin/bash
# rotate-kafka-passwords.sh

USERS=("admin" "producer-user" "consumer-user")

for user in "${USERS[@]}"; do
 NEW_PASS=$(openssl rand -base64 32)
 vault kv put "secret/kafka/users/$user" password="$NEW_PASS"
 echo "Rotated password for $user"
done

# Forza sync External Secrets
for user in "${USERS[@]}"; do
 kubectl -n kafka-lab annotate externalsecret "${user}-password" \
 force-sync=$(date +%s) --overwrite
done
```

---

## PARTE 8: Migrazione da Hardcoded a Vault

Se hai già un deployment con password hardcoded:

### Step 1: Prepara Vault

```bash
# Estrai password esistenti da values.yaml
ADMIN_PASS=$(grep "password: admin-secret" values.yaml | awk '{print $2}')

# Carica in Vault
vault kv put secret/kafka/users/admin password="$ADMIN_PASS"
```

### Step 2: Deploy con Dual Mode

```yaml
# Temporaneamente supporta entrambi i metodi
vault:
 enabled: true # Abilita Vault

# Mantieni anche le password vecchie come fallback
kafkaUsers:
 - name: admin
 password: admin-secret # Fallback se Vault non disponibile
 vaultSecretPath: users/admin
```

### Step 3: Verifica e Cutover

```bash
# Verifica che ESO funzioni
kubectl -n kafka-lab get externalsecrets

# Se OK, rimuovi password hardcoded da values.yaml
# Ripeti deploy
```

---

## Riepilogo Comandi Rapidi

```bash
# Setup completo (eseguire in ordine)

# 1. Deploy Vault
helm install vault hashicorp/vault -n vault-system --create-namespace

# 2. Configura Vault
kubectl -n vault-system exec -it vault-0 -- /bin/sh
vault operator init # Solo prima volta
vault operator unseal # Ripeti 3 volte con chiavi diverse
vault login

# 3. Carica secret
vault kv put secret/kafka/users/admin password="YourSecurePass123!"

# 4. Configura K8s auth
vault auth enable kubernetes
vault write auth/kubernetes/role/kafka-lab ...

# 5. Deploy ESO
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace

# 6. Deploy Kafka Lab
helm install kafka-lab ./helm -n kafka-lab

# 7. Verifica
kubectl -n kafka-lab get externalsecrets
kubectl -n kafka-lab get secrets
```

---

## Conclusione

Con questa configurazione hai:

 **Zero secret hardcoded** in Git o configurazioni 
 **Centralizzazione** di tutti i secret in Vault 
 **Automatic secret refresh** senza restart pod 
 **Audit trail completo** di tutti gli accessi 
 **Production-ready** architecture 
 **Rotation facile** dei secret 

Per domande o problemi, controlla sempre:
1. Logs External Secrets Operator
2. Status External Secrets (`kubectl describe externalsecret`)
3. Vault audit logs
4. Connectivity tra namespace
