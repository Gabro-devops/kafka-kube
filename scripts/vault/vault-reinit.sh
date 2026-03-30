#!/bin/bash
# ============================================================================
# VAULT RE-INIT - Ripristina Vault dopo restart del pod
# ============================================================================
# Vault gira in dev mode (storage in memoria) - i dati si perdono ad ogni
# restart del pod. Questo script ripristina tutto in 30 secondi.
#
# Quando usarlo:
# - Dopo un Docker Desktop restart
# - Dopo un Mac sleep/wake
# - Quando ESO mostra SecretSyncedError
# - Quando Kafka UI non riesce ad autenticarsi
#
# Uso: ./scripts/vault/vault-reinit.sh <PASSWORD>
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VAULT_NODEPORT=30372
KAFKA_NAMESPACE="kafka-lab"
VAULT_NAMESPACE="vault-system"

echo -e "${BLUE}${NC}"
echo -e "${BLUE} VAULT RE-INIT - Ripristino Dati ${NC}"
echo -e "${BLUE}${NC}"
echo

# Recupera password
if [ -n "$1" ]; then
 APP_PASSWORD="$1"
else
 # Prova a leggerla dall'ultimo file passwords
 LATEST_PWD=$(ls -t scripts/vault/vault-passwords-*.txt 2>/dev/null | head -1)
 if [ -n "$LATEST_PWD" ]; then
 APP_PASSWORD=$(grep "Password:" "$LATEST_PWD" | awk '{print $2}' | head -1)
 echo -e "${YELLOW} Password recuperata da: $LATEST_PWD${NC}"
 fi
fi

if [ -z "$APP_PASSWORD" ]; then
 read -rsp " Inserisci la password dei servizi: " APP_PASSWORD
 echo
fi

export VAULT_ADDR="http://localhost:${VAULT_NODEPORT}"
export VAULT_TOKEN="root"

# Verifica Vault raggiungibile
echo -n " Verifico Vault... "
if ! vault status &>/dev/null; then
 echo -e "${RED} Vault non raggiungibile su localhost:${VAULT_NODEPORT}${NC}"
 echo -e "${YELLOW} Verifica che il cluster Kubernetes sia attivo${NC}"
 exit 1
fi
echo -e "${GREEN}${NC}"

# Step 1: Riabilita KV engine
echo -n " Abilito KV engine... "
vault secrets enable -version=2 -path=secret kv 2>/dev/null || true
echo -e "${GREEN}${NC}"

# Step 2: Carica secret
echo -n " Carico secret Kafka... "
vault kv put secret/kafka/users/admin password="${APP_PASSWORD}" > /dev/null
vault kv put secret/kafka/users/producer-user password="${APP_PASSWORD}" > /dev/null
vault kv put secret/kafka/users/consumer-user password="${APP_PASSWORD}" > /dev/null
vault kv put secret/kafka/monitoring/grafana password="${APP_PASSWORD}" > /dev/null
vault kv put secret/kafka/jenkins/admin password="${APP_PASSWORD}" > /dev/null
echo -e "${GREEN}${NC}"

# Step 3: Riconfigura Kubernetes auth usando il CA cert corretto
echo -n " Configuro Kubernetes auth... "
vault auth enable kubernetes 2>/dev/null || true

# Prendi CA cert dal configmap (metodo affidabile su Docker Desktop)
CA_CERT=$(kubectl get configmap kube-root-ca.crt -n ${KAFKA_NAMESPACE} \
 -o jsonpath='{.data.ca\.crt}' 2>/dev/null)

if [ -z "$CA_CERT" ]; then
 # Fallback: usa il CA dal pod Vault stesso
 kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- sh -c "
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
vault auth enable kubernetes 2>/dev/null || true
vault write auth/kubernetes/config \
 kubernetes_host='https://kubernetes.default.svc:443' \
 kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
 token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
" > /dev/null
else
 # Metodo diretto con CA cert dal configmap (più affidabile)
 echo "${CA_CERT}" > /tmp/k8s-ca.crt
 JWT=$(kubectl create token vault-auth -n ${KAFKA_NAMESPACE} --duration=8760h 2>/dev/null || \
 kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)

 vault write auth/kubernetes/config \
 kubernetes_host="https://kubernetes.default.svc:443" \
 kubernetes_ca_cert=@/tmp/k8s-ca.crt \
 token_reviewer_jwt="${JWT}" > /dev/null
 rm -f /tmp/k8s-ca.crt
fi
echo -e "${GREEN}${NC}"

# Step 4: Crea policy e role
echo -n " Creo policy e role... "
vault policy write kafka-lab - > /dev/null << EOF
path "secret/data/kafka/*" {
 capabilities = ["read", "list"]
}
path "secret/metadata/kafka/*" {
 capabilities = ["list"]
}
EOF

vault write auth/kubernetes/role/kafka-lab \
 bound_service_account_names=vault-auth \
 bound_service_account_namespaces=${KAFKA_NAMESPACE} \
 policies=kafka-lab \
 ttl=24h > /dev/null
echo -e "${GREEN}${NC}"

# Step 5: Forza risync ESO
echo -n " Forzo sync External Secrets... "
sleep 3
kubectl annotate externalsecret -n ${KAFKA_NAMESPACE} --all \
 force-sync=$(date +%s) --overwrite > /dev/null
echo -e "${GREEN}${NC}"

# Step 6: Attendi sync
echo -n " Attendo SecretSynced... "
for attempt in {1..20}; do
 READY=$(kubectl -n ${KAFKA_NAMESPACE} get externalsecrets \
 -o jsonpath='{.items[*].status.conditions[0].status}' 2>/dev/null | \
 tr ' ' '\n' | grep -c "True" || true)
 TOTAL=$(kubectl -n ${KAFKA_NAMESPACE} get externalsecrets \
 --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo 0)
 if [ "$READY" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
 echo -e "${GREEN} ($TOTAL/$TOTAL)${NC}"
 break
 fi
 sleep 3
 if [ $attempt -eq 20 ]; then
 echo -e "${YELLOW} Timeout - verifica manualmente${NC}"
 fi
done

# Step 7: Riavvia Kafka UI per ricaricare credenziali
echo -n " Riavvio pod che dipendono dai secret... "
kubectl rollout restart deployment/kafka-ui -n ${KAFKA_NAMESPACE} > /dev/null || true
kubectl rollout restart deployment/grafana -n ${KAFKA_NAMESPACE} > /dev/null || true
kubectl rollout restart deployment/jenkins -n ${KAFKA_NAMESPACE} > /dev/null || true
kubectl rollout restart deployment/kafka-exporter -n ${KAFKA_NAMESPACE} > /dev/null || true
echo -e "${GREEN}OK${NC}"

echo
echo -e "${GREEN} Vault ripristinato! Tutti i secret sincronizzati.${NC}"
echo
echo -e "${YELLOW} Verifica ESO: kubectl get externalsecret -n kafka-lab${NC}"
echo -e "${YELLOW} Verifica secret: vault kv get secret/kafka/users/admin${NC}"
