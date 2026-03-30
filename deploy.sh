#!/bin/bash
# ============================================================================
# KAFKA LAB - DEPLOY AUTOMATICO COMPLETO
# ============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

VAULT_NODEPORT=30372
KAFKA_NAMESPACE="kafka-lab"
VAULT_NAMESPACE="vault-system"
ESO_NAMESPACE="external-secrets-system"

echo -e "${BLUE}${NC}"
echo -e "${BLUE} KAFKA LAB - AUTO DEPLOY ${NC}"
echo -e "${BLUE}${NC}"
echo

# ============================================================================
# CHIEDI PASSWORD UNA VOLTA SOLA
# ============================================================================
echo -e "${CYAN}${NC}"
echo -e "${YELLOW} Inserisci la password che verrà usata per TUTTI i servizi:${NC}"
echo -e "${YELLOW} (Grafana, Jenkins, Kafka Admin, Producer, Consumer, AWX)${NC}"
echo -e "${CYAN}${NC}"
echo

while true; do
 read -rsp " Password (min 12 caratteri): " APP_PASSWORD
 echo
 if [ ${#APP_PASSWORD} -lt 12 ]; then
 echo -e "${RED} Password troppo corta! Minimo 12 caratteri.${NC}"
 else
 read -rsp " Conferma password: " APP_PASSWORD2
 echo
 if [ "$APP_PASSWORD" == "$APP_PASSWORD2" ]; then
 echo -e "${GREEN} Password accettata${NC}"
 break
 else
 echo -e "${RED} Le password non corrispondono!${NC}"
 fi
 fi
done

echo

# ============================================================================
# STEP 1: PREREQUISITI
# ============================================================================
echo -e "${BLUE}[1/7] Verifica prerequisiti...${NC}"

for cmd in kubectl helm docker; do
 if ! command -v $cmd &> /dev/null; then
 echo -e "${RED} $cmd non trovato${NC}"
 exit 1
 fi
done

if ! command -v vault &> /dev/null; then
 echo -e "${YELLOW} vault CLI non trovato, installo...${NC}"
 brew install vault
fi

echo -e "${GREEN} Prerequisiti OK${NC}"
echo

# ============================================================================
# BUILD IMMAGINI DOCKER (se non esistono su Docker Hub)
# ============================================================================
echo -e "${BLUE}[1b/7] Verifica immagini Docker...${NC}"

DOCKER_USER="gabrodevops"
JENKINS_IMAGE="${DOCKER_USER}/jenkins-kafka:1.0.0"
AWX_EE_IMAGE="${DOCKER_USER}/kafka-ee:1.0.0"

build_and_push_image() {
 local IMAGE=$1
 local CONTEXT=$2
 local NAME=$3

 echo -n " Verifico ${NAME} (${IMAGE})... "

 # Controlla se esiste già su Docker Hub
 if docker manifest inspect "${IMAGE}" &>/dev/null; then
 echo -e "${GREEN} Già presente su Docker Hub${NC}"
 return 0
 fi

 # Non esiste - controlla se esiste localmente
 if docker image inspect "${IMAGE}" &>/dev/null; then
 echo -e "${YELLOW}Presente solo in locale, push in corso...${NC}"
 docker push "${IMAGE}" > /dev/null
 echo -e "${GREEN} Push completato${NC}"
 return 0
 fi

 # Non esiste da nessuna parte - build + push
 echo -e "${YELLOW} Non trovata, build in corso...${NC}"
 echo -e " ${CYAN}(Prima esecuzione: può richiedere 5-10 minuti)${NC}"

 if docker build -t "${IMAGE}" "${CONTEXT}" ; then
 echo -n " Push su Docker Hub... "
 docker push "${IMAGE}" > /dev/null
 echo -e "${GREEN} Build e push completati${NC}"
 else
 echo -e "${RED} Build fallita per ${NAME}${NC}"
 exit 1
 fi
}

# Verifica login Docker Hub
echo -n " Verifico login Docker Hub... "
if ! docker info 2>/dev/null | grep -q "Username"; then
 echo -e "${YELLOW} Non loggato, eseguo login...${NC}"
 docker login
fi
echo -e "${GREEN}${NC}"

# Build Jenkins con plugin
build_and_push_image "${JENKINS_IMAGE}" "./jenkins" "Jenkins+plugin"

# Build AWX Execution Environment
build_and_push_image "${AWX_EE_IMAGE}" "./awx-ee" "AWX Execution Environment"

echo -e "${GREEN} Immagini Docker pronte${NC}"
echo

# ============================================================================
# STEP 2: INSTALLA VAULT
# ============================================================================
echo -e "${BLUE}[2/7] Installazione HashiCorp Vault (NodePort: ${VAULT_NODEPORT})...${NC}"

helm repo add hashicorp https://helm.releases.hashicorp.com &> /dev/null || true
helm repo update &> /dev/null

kubectl create namespace $VAULT_NAMESPACE 2>/dev/null || true

helm upgrade --install vault hashicorp/vault -n $VAULT_NAMESPACE \
    --set server.dev.enabled=true \
    --set server.dev.devRootToken=root \
    --set ui.enabled=true \
    --set ui.serviceType=NodePort \
    --set ui.serviceNodePort=${VAULT_NODEPORT} \
    --set injector.enabled=false \
    --wait --timeout 5m

echo -n " Attendo Vault ready... "
kubectl -n $VAULT_NAMESPACE wait --for=condition=ready pod -l app.kubernetes.io/name=vault --timeout=120s > /dev/null
echo -e "${GREEN}${NC}"

export VAULT_ADDR="http://localhost:${VAULT_NODEPORT}"
export VAULT_TOKEN="root"

echo -e "${GREEN} Vault installato -> http://localhost:${VAULT_NODEPORT} (token: root)${NC}"
echo

# ============================================================================
# STEP 3: INIZIALIZZA SECRET IN VAULT
# ============================================================================
echo -e "${BLUE}[3/7] Inizializzazione secret in Vault...${NC}"

# Abilita KV engine
vault secrets enable -version=2 -path=secret kv 2>/dev/null || true

# Carica tutti i secret con la password inserita
echo -n " Carico secrets in Vault... "
vault kv put secret/kafka/users/admin password="${APP_PASSWORD}" > /dev/null
vault kv put secret/kafka/users/producer-user password="${APP_PASSWORD}" > /dev/null
vault kv put secret/kafka/users/consumer-user password="${APP_PASSWORD}" > /dev/null
vault kv put secret/kafka/monitoring/grafana password="${APP_PASSWORD}" > /dev/null
vault kv put secret/kafka/jenkins/admin password="${APP_PASSWORD}" > /dev/null
echo -e "${GREEN}${NC}"

# Salva le password in file
PWD_FILE="scripts/vault/vault-passwords-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p scripts/vault
cat > "$PWD_FILE" << EOF
# ============================================
# KAFKA LAB - CREDENZIALI
# Generato: $(date)
# ============================================

# ATTENZIONE: Non committare questo file su Git!

Kafka Admin: admin / ${APP_PASSWORD}
Kafka Producer: producer-user / ${APP_PASSWORD}
Kafka Consumer: consumer-user / ${APP_PASSWORD}
Grafana: admin / ${APP_PASSWORD}
Jenkins: admin / ${APP_PASSWORD}
Vault: http://localhost:${VAULT_NODEPORT} (token: root)
EOF

echo -e "${GREEN} Secret inizializzati${NC}"
echo -e " Credenziali salvate in: ${CYAN}${PWD_FILE}${NC}"
echo

# ============================================================================
# STEP 4: CONFIGURA KUBERNETES AUTH IN VAULT
# ============================================================================
echo -e "${BLUE}[4/7] Configurazione Kubernetes Auth in Vault...${NC}"

kubectl create namespace $KAFKA_NAMESPACE 2>/dev/null || true

# Configura Vault K8s auth direttamente nel pod
echo -n " Configuro Kubernetes auth... "
kubectl -n $VAULT_NAMESPACE exec vault-0 -- sh -c "
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Abilita Kubernetes auth
vault auth enable kubernetes 2>/dev/null || true

# Configura con credenziali del pod
vault write auth/kubernetes/config \
 kubernetes_host='https://kubernetes.default.svc:443' \
 kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
 token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

# Crea policy
vault policy write kafka-lab - <<POLICY
path \"secret/data/kafka/*\" {
 capabilities = [\"read\", \"list\"]
}
path \"secret/metadata/kafka/*\" {
 capabilities = [\"list\"]
}
POLICY

# Crea role
vault write auth/kubernetes/role/kafka-lab \
 bound_service_account_names=vault-auth \
 bound_service_account_namespaces=${KAFKA_NAMESPACE} \
 policies=kafka-lab \
 ttl=24h
" > /dev/null

echo -e "${GREEN}${NC}"

# Crea token secret per ServiceAccount (dopo che Helm crea il SA)
# Lo creiamo subito con apply così Helm lo adotterà
echo -e "${GREEN} Kubernetes Auth configurato${NC}"
echo

# ============================================================================
# STEP 5: INSTALLA EXTERNAL SECRETS OPERATOR
# ============================================================================
echo -e "${BLUE}[5/7] Installazione External Secrets Operator...${NC}"

helm repo add external-secrets https://charts.external-secrets.io &> /dev/null || true
helm repo update &> /dev/null

helm upgrade --install external-secrets external-secrets/external-secrets \
    -n $ESO_NAMESPACE --create-namespace \
    --set installCRDs=true \
    --wait --timeout 5m

echo -n " Attendo ESO ready... "
kubectl -n $ESO_NAMESPACE wait --for=condition=ready pod \
 -l app.kubernetes.io/name=external-secrets --timeout=120s > /dev/null
echo -e "${GREEN}${NC}"

echo -e "${GREEN} External Secrets Operator installato${NC}"
echo

# ============================================================================
# STEP 6: INSTALLA STRIMZI OPERATOR
# ============================================================================
echo -e "${BLUE}[6/7] Installazione Strimzi Kafka Operator...${NC}"

helm repo add strimzi https://strimzi.io/charts/ &> /dev/null || true
helm repo update &> /dev/null

helm upgrade --install strimzi-operator strimzi/strimzi-kafka-operator \
    --namespace $KAFKA_NAMESPACE \
    --wait --timeout 5m

echo -n " Attendo Strimzi ready... "
kubectl -n $KAFKA_NAMESPACE wait --for=condition=ready pod \
 -l name=strimzi-cluster-operator --timeout=120s > /dev/null
echo -e "${GREEN}${NC}"

echo -e "${GREEN} Strimzi Operator installato${NC}"
echo

# ============================================================================
# STEP 7: INSTALLA KAFKA LAB
# ============================================================================
echo -e "${BLUE}[7/7] Installazione Kafka Lab (può richiedere 10-15 minuti)...${NC}"

helm upgrade --install kafka-lab ./helm -n $KAFKA_NAMESPACE --timeout 15m --disable-openapi-validation

echo -e "${GREEN} Helm chart applicato${NC}"
echo

# ============================================================================
# ATTENDI AWX PRONTO (inizia subito dopo helm install, richiede 8-10 minuti)
# ============================================================================
echo -e "${BLUE}Attendo AWX (può richiedere 8-10 minuti)...${NC}"
echo -n " Attendo AWX web... "
AWX_OK=0
for i in $(seq 1 120); do
    AWX_READY=$(kubectl -n $KAFKA_NAMESPACE get pod -l app.kubernetes.io/component=awx-web \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "$AWX_READY" = "True" ]; then
        echo -e "${GREEN}OK${NC}"
        AWX_OK=1
        break
    fi
    sleep 5
done
if [ $AWX_OK -eq 0 ]; then
    echo -e "${YELLOW}Timeout - continuo comunque${NC}"
fi
echo

# ATTENDI CHE EXTERNAL SECRETS SINCRONIZZI
# ============================================================================
echo -e "${BLUE}Attendo sincronizzazione External Secrets...${NC}"
echo -e "${YELLOW}(Questo può richiedere 2-5 minuti)${NC}"
echo

# Aspetta che vault-auth ServiceAccount sia creato da Helm
echo -n " Attendo ServiceAccount vault-auth... "
for i in {1..60}; do
    if kubectl -n $KAFKA_NAMESPACE get sa vault-auth &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        break
    fi
    sleep 2
    if [ $i -eq 60 ]; then
        echo -e "${RED}Timeout${NC}"
    fi
done

# Crea token secret per vault-auth
echo -n " Creo token per vault-auth... "
kubectl -n $KAFKA_NAMESPACE delete secret vault-auth-token --ignore-not-found &>/dev/null
cat <<TOKEOF | kubectl -n $KAFKA_NAMESPACE apply -f - > /dev/null
apiVersion: v1
kind: Secret
metadata:
  name: vault-auth-token
  namespace: ${KAFKA_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: vault-auth
type: kubernetes.io/service-account-token
TOKEOF
# Aspetta che il token venga popolato
sleep 5
echo -e "${GREEN}OK${NC}"

# Recupera il token generato e aggiorna Vault
echo -n " Aggiorno Vault con token ServiceAccount... "
SA_TOKEN=$(kubectl -n $KAFKA_NAMESPACE get secret vault-auth-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
CA_CERT=$(kubectl -n $KAFKA_NAMESPACE get secret vault-auth-token -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d)

if [ -n "$SA_TOKEN" ] && [ -n "$CA_CERT" ]; then
    # Scrivi CA cert in file temporaneo
    echo "$CA_CERT" > /tmp/vault-ca.crt
    
    export VAULT_ADDR="http://localhost:${VAULT_NODEPORT}"
    export VAULT_TOKEN="root"
    
    vault auth enable kubernetes 2>/dev/null || true
    vault write auth/kubernetes/config \
        kubernetes_host="https://kubernetes.default.svc:443" \
        kubernetes_ca_cert=@/tmp/vault-ca.crt \
        token_reviewer_jwt="$SA_TOKEN" > /dev/null 2>&1
    
    rm -f /tmp/vault-ca.crt
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}Token non ancora pronto, uso metodo alternativo...${NC}"
    kubectl -n $VAULT_NAMESPACE exec vault-0 -- sh -c "
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
vault auth enable kubernetes 2>/dev/null || true
vault write auth/kubernetes/config \
    kubernetes_host='https://kubernetes.default.svc:443' \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
" > /dev/null 2>&1
    echo -e "${GREEN}OK${NC}"
fi

# Forza sync degli ExternalSecrets
echo -n " Forzo sync External Secrets... "
sleep 5
for es in admin-password producer-user-password consumer-user-password grafana-admin-secret jenkins-admin-secret; do
    kubectl -n $KAFKA_NAMESPACE annotate externalsecret $es         force-sync=$(date +%s) --overwrite &>/dev/null || true
done
echo -e "${GREEN}OK${NC}"

# Aspetta che tutti gli ExternalSecrets siano sincronizzati
echo -n " Attendo SecretSynced... "
SYNCED=0
for attempt in {1..30}; do
    READY=$(kubectl -n $KAFKA_NAMESPACE get externalsecrets -o jsonpath='{.items[*].status.conditions[0].status}' 2>/dev/null | tr ' ' '\n' | grep -c "True" || true)
    TOTAL=$(kubectl -n $KAFKA_NAMESPACE get externalsecrets --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    if [ "$READY" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
        SYNCED=1
        echo -e "${GREEN}($TOTAL/$TOTAL sincronizzati)${NC}"
        break
    fi
    sleep 5
done

if [ $SYNCED -eq 0 ]; then
    echo -e "${YELLOW}Non tutti i secret sono sincronizzati, continuo comunque...${NC}"
fi

# ============================================================================
# RIAVVIA POD CHE DIPENDONO DAI SECRET
# ============================================================================
echo
echo -e "${BLUE}Riavvio pod che dipendono dai secret...${NC}"
sleep 5
kubectl -n $KAFKA_NAMESPACE rollout restart deployment/grafana 2>/dev/null || true
kubectl -n $KAFKA_NAMESPACE rollout restart deployment/jenkins 2>/dev/null || true
kubectl -n $KAFKA_NAMESPACE rollout restart deployment/kafka-ui 2>/dev/null || true
kubectl -n $KAFKA_NAMESPACE rollout restart deployment/kafka-exporter 2>/dev/null || true
echo -e "${GREEN}OK${NC}"
echo

# ============================================================================
# ATTENDI POD RUNNING
# ============================================================================
echo
echo -e "${BLUE}Attendo che tutti i pod siano Running...${NC}"
echo -e "${YELLOW}(Kafka e AWX richiedono qualche minuto)${NC}"

echo -n " Attendo Grafana... "
kubectl -n $KAFKA_NAMESPACE wait --for=condition=ready pod \
 -l app=grafana --timeout=300s > /dev/null 2>&1 && echo -e "${GREEN}${NC}" || echo -e "${YELLOW} Ancora in avvio${NC}"

# Riavvia Grafana dopo provisioning per caricare correttamente la home dashboard
sleep 15
kubectl -n $KAFKA_NAMESPACE rollout restart deployment/grafana > /dev/null 2>&1 || true
kubectl -n $KAFKA_NAMESPACE wait --for=condition=ready pod \
 -l app=grafana --timeout=120s > /dev/null 2>&1 || true

echo -n " Attendo Jenkins... "
kubectl -n $KAFKA_NAMESPACE wait --for=condition=ready pod \
 -l app=jenkins --timeout=300s > /dev/null 2>&1 && echo -e "${GREEN}${NC}" || echo -e "${YELLOW} Ancora in avvio${NC}"

echo -n " Attendo Kafka brokers... "
kubectl -n $KAFKA_NAMESPACE wait --for=condition=ready pod \
 -l strimzi.io/kind=Kafka --timeout=300s > /dev/null 2>&1 && echo -e "${GREEN}${NC}" || echo -e "${YELLOW} Ancora in avvio${NC}"

# ============================================================================
# CONFIGURAZIONE AUTOMATICA AWX
# ============================================================================
echo
echo -e "${BLUE}Configurazione AWX...${NC}"
echo

AWX_PASS=$(kubectl get secret awx-admin-password -n ${KAFKA_NAMESPACE} -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
AWX_URL="http://localhost:30043"

if [ -n "$AWX_PASS" ]; then
 echo -n " Configuro Execution Environment... "
 # Crea Execution Environment
 curl -s -X POST "${AWX_URL}/api/v2/execution_environments/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d "{
 \"name\": \"Kafka EE\",
 \"image\": \"${AWX_EE_IMAGE}\",
 \"pull\": \"missing\",
 \"description\": \"Kafka Execution Environment con kubernetes.core\"
 }" > /dev/null 2>&1 && echo -e "${GREEN}${NC}" || echo -e "${YELLOW} Riprova manualmente${NC}"

 echo -n " Configuro Organization... "
 ORG_ID=$(curl -s "${AWX_URL}/api/v2/organizations/" \
 -u "admin:${AWX_PASS}" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')

 echo -n " Configuro Project (repo GitHub)... "
 curl -s -X POST "${AWX_URL}/api/v2/projects/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d "{
 \"name\": \"kafka-kube\",
 \"description\": \"Kafka Lab Ansible Playbooks\",
 \"scm_type\": \"git\",
 \"scm_url\": \"https://github.com/Gabro-devops/kafka-kube.git\",
 \"scm_branch\": \"main\",
 \"scm_update_on_launch\": true,
 \"organization\": ${ORG_ID:-1}
 }" > /dev/null 2>&1 && echo -e "${GREEN}${NC}" || echo -e "${YELLOW} Riprova manualmente${NC}"

 echo -n " Configuro Inventory... "
 INV_ID=$(curl -s -X POST "${AWX_URL}/api/v2/inventories/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d "{
 \"name\": \"Kafka Inventory\",
 \"description\": \"Kafka cluster inventory\",
 \"organization\": ${ORG_ID:-1}
 }" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
 echo -e "${GREEN}${NC}"

 # Attendi sync del project con loop robusto
 echo -n " Attendo sync Project da GitHub... "
 PROJ_ID=""
 for i in {1..24}; do
 PROJ_ID=$(curl -s "${AWX_URL}/api/v2/projects/?name=kafka-kube" \
 -u "admin:${AWX_PASS}" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
 if [ -n "$PROJ_ID" ]; then
 PROJ_STATUS=$(curl -s "${AWX_URL}/api/v2/projects/${PROJ_ID}/" \
 -u "admin:${AWX_PASS}" 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status"://;s/"//g')
 if [ "$PROJ_STATUS" = "successful" ]; then
 echo -e "${GREEN}${NC}"
 break
 fi
 fi
 sleep 5
 if [ $i -eq 24 ]; then
 echo -e "${YELLOW} Timeout sync - vai in AWX -> Projects -> kafka-kube -> premi Sync${NC}"
 fi
 done
 EE_ID=$(curl -s "${AWX_URL}/api/v2/execution_environments/?name=Kafka+EE" \
 -u "admin:${AWX_PASS}" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')

 # Crea Job Templates
 # Crea Custom Credential Type per Kafka
 echo -n " Creo Credential Type Kafka... "
 CRED_TYPE_ID=$(curl -s -X POST "${AWX_URL}/api/v2/credential_types/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d '{
 "name": "Kafka Custom Credential",
 "description": "Credenziali per Kafka SCRAM-SHA-512",
 "kind": "cloud",
 "inputs": {
 "fields": [
 {
 "id": "kafka_admin_password",
 "type": "string",
 "label": "Kafka Admin Password",
 "secret": true
 },
 {
 "id": "kafka_admin_user",
 "type": "string",
 "label": "Kafka Admin User"
 }
 ],
 "required": ["kafka_admin_password", "kafka_admin_user"]
 },
 "injectors": {
 "extra_vars": {
 "kafka_admin_password": "{% raw %}{{ kafka_admin_password }}{% endraw %}",
 "kafka_admin_user": "{% raw %}{{ kafka_admin_user }}{% endraw %}"
 }
 }
 }' 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
 echo -e "${GREEN}${NC}"

 # Crea Credential con la password inserita dall utente
 echo -n " Creo Credential Kafka Admin... "
 CRED_ID=$(curl -s -X POST "${AWX_URL}/api/v2/credentials/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d "{
 \"name\": \"Kafka Admin Credential\",
 \"description\": \"Credenziali admin Kafka\",
 \"credential_type\": ${CRED_TYPE_ID:-1},
 \"organization\": ${ORG_ID:-1},
 \"inputs\": {
 \"kafka_admin_user\": \"admin\",
 \"kafka_admin_password\": \"${APP_PASSWORD}\"
 }
 }" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
 echo -e "${GREEN}${NC}"

 # Crea Credential Kubernetes per AWX
 echo -n " Creo Credential Kubernetes... "
 # Recupera il token del ServiceAccount jenkins-admin
 K8S_TOKEN=$(kubectl create token jenkins-admin -n ${KAFKA_NAMESPACE} --duration=8760h 2>/dev/null || \
 kubectl -n ${KAFKA_NAMESPACE} get secret \
 $(kubectl -n ${KAFKA_NAMESPACE} get sa jenkins-admin -o jsonpath="{.secrets[0].name}" 2>/dev/null) \
 -o jsonpath="{.data.token}" 2>/dev/null | base64 -d)

 # Recupera ID del credential type Kubernetes/OpenShift
 K8S_CRED_TYPE_ID=$(curl -s "${AWX_URL}/api/v2/credential_types/?name=OpenShift+or+Kubernetes+API+Bearer+Token" \
 -u "admin:${AWX_PASS}" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
 # Fallback: cerca per namespace
 if [ -z "$K8S_CRED_TYPE_ID" ]; then
 K8S_CRED_TYPE_ID=$(curl -s "${AWX_URL}/api/v2/credential_types/?kind=kubernetes" \
 -u "admin:${AWX_PASS}" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
 fi
 K8S_CRED_ID=$(curl -s -X POST "${AWX_URL}/api/v2/credentials/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d "{
 \"name\": \"Kubernetes Local\",
 \"description\": \"Accesso al cluster Kubernetes locale\",
 \"credential_type\": ${K8S_CRED_TYPE_ID:-15},
 \"organization\": ${ORG_ID:-1},
 \"inputs\": {
 \"host\": \"https://kubernetes.default.svc\",
 \"bearer_token\": \"${K8S_TOKEN}\",
 \"verify_ssl\": false
 }
 }" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
 echo -e "${GREEN}${NC}"

 echo -n " Creo Job Templates... "

 create_job_template() {
 local NAME=$1
 local PLAYBOOK=$2
 local EXTRA_VARS=$3
 local JT_ID=$(curl -s -X POST "${AWX_URL}/api/v2/job_templates/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d "{
 \"name\": \"${NAME}\",
 \"job_type\": \"run\",
 \"inventory\": ${INV_ID:-1},
 \"project\": ${PROJ_ID:-1},
 \"playbook\": \"${PLAYBOOK}\",
 \"execution_environment\": ${EE_ID:-1},
 \"ask_variables_on_launch\": true,
 \"extra_vars\": \"${EXTRA_VARS}\",
 \"verbosity\": 1
 }" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
 # Associa credential Kafka al job template
 if [ -n "$JT_ID" ] && [ -n "$CRED_ID" ]; then
 curl -s -X POST "${AWX_URL}/api/v2/job_templates/${JT_ID}/credentials/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d "{\"id\": ${CRED_ID}}" > /dev/null 2>&1
 fi
 # Associa credential Kubernetes al job template
 if [ -n "$JT_ID" ] && [ -n "$K8S_CRED_ID" ]; then
 curl -s -X POST "${AWX_URL}/api/v2/job_templates/${JT_ID}/credentials/" \
 -u "admin:${AWX_PASS}" \
 -H "Content-Type: application/json" \
 -d "{\"id\": ${K8S_CRED_ID}}" > /dev/null 2>&1
 fi
 }

 create_job_template \
 "Kafka - Health Check" \
 "ansible/playbooks/kafka_health.yml" \
 "---"

 create_job_template \
 "Kafka - Create Topic" \
 "ansible/playbooks/kafka_create_topic.yml" \
 "---\nkafka_topic_name: my-topic\nkafka_topic_partitions: 3\nkafka_topic_replicas: 3"

 create_job_template \
 "Kafka - Manage Users" \
 "ansible/playbooks/kafka_manage_users.yml" \
 "---\nkafka_user_action: list\nkafka_username: \"\"\nkafka_password: \"\""

 create_job_template \
 "Kafka - Manage ACL" \
 "ansible/playbooks/kafka_manage_acl.yml" \
 "---\nkafka_username: admin"

 create_job_template \
 "Kafka - Full Test Suite" \
 "ansible/playbooks/kafka_full_test.yml" \
 "---\ncleanup: false"

 echo -e "${GREEN}${NC}"
 echo -e "${GREEN} AWX configurato${NC}"
else
 echo -e "${YELLOW} AWX non ancora pronto - configura manualmente seguendo docs/AWX_SETUP.md${NC}"
fi

# ============================================================================
# RIEPILOGO FINALE
# ============================================================================
echo
echo -e "${BLUE}${NC}"
echo -e "${BLUE} DEPLOYMENT STATUS ${NC}"
echo -e "${BLUE}${NC}"
echo
kubectl -n $KAFKA_NAMESPACE get pods --no-headers | awk '{
 if ($3 == "Running" || $3 == "Completed")
 printf "\033[0;32m\033[0m %-45s %s\n", $1, $3
 else
 printf "\033[0;31m\033[0m %-45s %s\n", $1, $3
}'

echo
echo -e "${BLUE}${NC}"
echo -e "${BLUE} ACCESSO AI SERVIZI ${NC}"
echo -e "${BLUE}${NC}"
echo
echo -e "${GREEN} Vault:${NC} http://localhost:${VAULT_NODEPORT} (token: root)"
echo -e "${GREEN} Kafka UI:${NC} http://localhost:30080"
echo -e "${GREEN} Grafana:${NC} http://localhost:30030 (admin / ${APP_PASSWORD})"
echo -e "${GREEN} Jenkins:${NC} http://localhost:32000 (admin / ${APP_PASSWORD})"
echo -e "${GREEN} Prometheus:${NC} http://localhost:30090"
echo -e "${GREEN} AWX:${NC} http://localhost:30043"
echo
AWX_PASS=$(kubectl get secret awx-admin-password -n ${KAFKA_NAMESPACE} -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "recupera con: kubectl get secret awx-admin-password -n kafka-lab -o jsonpath='{.data.password}' | base64 -d")
echo -e "${YELLOW} AWX Password:${NC} ${AWX_PASS}"
echo
echo -e "${YELLOW} Credenziali salvate in: ${CYAN}${PWD_FILE}${NC}"
echo
echo -e "${CYAN} [INFO] AWX configurato automaticamente con:${NC}"
echo -e "${CYAN} - Execution Environment: ${AWX_EE_IMAGE}${NC}"
echo -e "${CYAN} - Project: https://github.com/Gabro-devops/kafka-kube.git${NC}"
echo -e "${CYAN} - Inventory: Kafka Inventory${NC}"
echo
echo -e "${YELLOW} Credenziali salvate in: ${CYAN}${PWD_FILE}${NC}"
echo
echo -e "${GREEN} Deploy completato!${NC}"
