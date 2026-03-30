# GUIDA DEPLOYMENT KAFKA-FIX
## Setup Completo con Jenkins + AWX su Mac M4

---

## INDICE

1. [Prerequisiti](#1-prerequisiti)
2. [Setup Kubernetes Locale](#2-setup-kubernetes-locale)
3. [Deploy Strimzi Operator](#3-deploy-strimzi-operator)
4. [Deploy Kafka-Fix (Jenkins + AWX + Kafka)](#4-deploy-kafka-fix)
5. [Verifica Deployment](#5-verifica-deployment)
6. [Primo Utilizzo Jenkins](#6-primo-utilizzo-jenkins)
7. [Primo Utilizzo AWX](#7-primo-utilizzo-awx)
8. [Quando Usare Jenkins vs AWX](#8-quando-usare-jenkins-vs-awx)
9. [Esempi Pratici](#9-esempi-pratici)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. PREREQUISITI

### Software Necessario

```bash
# 1. Docker Desktop per Mac (Apple Silicon)
# Download: https://www.docker.com/products/docker-desktop/
# Installa e avvia Docker Desktop

# 2. Verifica Docker running
docker info
# Se vedi statistiche -> OK 

# 3. Abilita Kubernetes in Docker Desktop
# Docker Desktop -> Settings -> Kubernetes -> Enable Kubernetes
# Aspetta ~3-5 minuti per il primo setup

# 4. Verifica Kubernetes
kubectl version --client
kubectl get nodes
# Output atteso:
# NAME STATUS ROLES AGE VERSION
# docker-desktop Ready control-plane 1d v1.29.x

# 5. Installa Helm
brew install helm
helm version
# Output atteso: version.BuildInfo{Version:"v3.x.x"...}
```

### Risorse Docker Desktop

```bash
# Docker Desktop -> Settings -> Resources

MINIMO (funziona ma lento):
 CPU: 4 cores
 Memory: 6 GB
 Swap: 1 GB
 Disk: 40 GB

RACCOMANDATO (per tuo Mac M4 16GB):
 CPU: 6 cores
 Memory: 8 GB
 Swap: 2 GB
 Disk: 60 GB

OTTIMALE:
 CPU: 8 cores
 Memory: 10 GB
 Swap: 2 GB
 Disk: 80 GB
```

---

## 2. SETUP KUBERNETES LOCALE

### Verifica Cluster

```bash
# 1. Verifica nodi
kubectl get nodes
# Dovresti vedere: docker-desktop Ready

# 2. Verifica namespace
kubectl get namespaces
# Dovresti vedere: default, kube-system, kube-public, kube-node-lease

# 3. Test deployment base
kubectl run test --image=nginx --rm -it --restart=Never -- echo "K8s OK"
# Output atteso: K8s OK
# Pod test deleted (automatico)

# Se tutto funziona -> procedi!
```

---

## 3. DEPLOY STRIMZI OPERATOR

Strimzi è l'Operator che gestisce Kafka su Kubernetes.

```bash
# 1. Crea namespace
kubectl create namespace kafka-lab

# 2. Aggiungi Helm repo Strimzi
helm repo add strimzi https://strimzi.io/charts/
helm repo update

# 3. Installa Strimzi Operator 0.50.0
helm upgrade --install strimzi-operator strimzi/strimzi-kafka-operator \
 -n kafka-lab \
 --version 0.50.0 \
 --set watchNamespaces="{kafka-lab}"

# Output atteso:
# Release "strimzi-operator" does not exist. Installing it now.
# NAME: strimzi-operator
# NAMESPACE: kafka-lab
# STATUS: deployed

# 4. Verifica pod Strimzi
kubectl get pods -n kafka-lab

# Output atteso (dopo 30-60 secondi):
# NAME READY STATUS AGE
# strimzi-cluster-operator-xxxxxxxxxx-xxxxx 1/1 Running 1m

# 5. Aspetta che sia Ready (importante!)
kubectl wait --for=condition=Ready pod \
 -l name=strimzi-cluster-operator \
 -n kafka-lab \
 --timeout=120s

# Se vedi "pod/strimzi-cluster-operator-xxx condition met" -> OK!
```

---

## 4. DEPLOY KAFKA-FIX

### Opzione A: Deploy Completo (Jenkins + AWX + Kafka + Monitoring)

```bash
# 1. Vai nella directory del progetto
cd /path/to/kafka-fix\ 3/helm

# 2. IMPORTANTE: Verifica values.yaml
cat values.yaml | grep "enabled: true"
# Dovresti vedere:
# kafka.enabled: true
# jenkins.enabled: true
# awx.enabled: true
# kafkaUi.enabled: true
# monitoring.enabled: true

# 3. Aggiungi repo AWX (necessario per dependency)
helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm/
helm repo update

# 4. Update dependencies
helm dependency update

# 5. Dry-run (verifica YAML senza applicare)
helm install kafka-lab . -n kafka-lab --dry-run --debug | head -100
# Controlla che non ci siano errori

# 6. DEPLOY REALE
helm install kafka-lab . -n kafka-lab

# Output atteso:
# NAME: kafka-lab
# NAMESPACE: kafka-lab
# STATUS: deployed
# REVISION: 1

# 7. Monitora deployment (lascia questo comando running)
watch -n 2 'kubectl get pods -n kafka-lab'

# Aspetta che tutti i pod siano Running:
# 
# Pod che vedrai (in ordine di creazione): 
# 
# 1. strimzi-cluster-operator (già running) 
# 2. kafka-cluster-kafka-0 (2-3 min) <- Kafka broker 1 
# 3. kafka-cluster-kafka-1 (2-3 min) <- Kafka broker 2 
# 4. kafka-cluster-kafka-2 (2-3 min) <- Kafka broker 3 
# 5. kafka-connect-xxx (dopo Kafka ready) 
# 6. kafka-ui-xxx 
# 7. jenkins-xxx 
# 8. awx-operator-xxx 
# 9. awx-postgres-xxx (DB per AWX) 
# 10. awx-xxx (AWX main pod) 
# 11. prometheus-xxx 
# 12. grafana-xxx 
# 

# TEMPO TOTALE: 8-12 minuti per tutto Ready
```

### Opzione B: Deploy Minimale (Solo Jenkins + Kafka, no AWX)

Se vuoi deployare più velocemente senza AWX:

```bash
cd /path/to/kafka-fix\ 3/helm

# Modifica values.yaml
# Cambia: awx.enabled: false

# Deploy
helm install kafka-lab . -n kafka-lab

# Tempo: 5-7 minuti
```

### Opzione C: Deploy Solo AWX + Kafka (no Jenkins)

```bash
# Modifica values.yaml
# Cambia: jenkins.enabled: false

# Deploy
helm install kafka-lab . -n kafka-lab
```

---

## 5. VERIFICA DEPLOYMENT

### Check 1: Tutti i Pod Running

```bash
# Aspetta che TUTTI siano 1/1 Running
kubectl get pods -n kafka-lab

# Output atteso (deployment completo):
NAME READY STATUS AGE
strimzi-cluster-operator-xxx 1/1 Running 10m
kafka-cluster-kafka-0 1/1 Running 8m
kafka-cluster-kafka-1 1/1 Running 8m
kafka-cluster-kafka-2 1/1 Running 8m
kafka-cluster-entity-operator-xxx 2/2 Running 7m
kafka-connect-xxx 1/1 Running 6m
kafka-ui-xxx 1/1 Running 5m
jenkins-xxx 1/1 Running 5m
awx-operator-controller-manager-xxx 2/2 Running 5m
awx-postgres-xxx 1/1 Running 4m
awx-xxx 4/4 Running 3m
prometheus-xxx 1/1 Running 5m
grafana-xxx 1/1 Running 5m

# Se tutti Running -> OK!
```

### Check 2: Kafka Cluster Ready

```bash
# Verifica Kafka custom resource
kubectl get kafka -n kafka-lab

# Output atteso:
NAME DESIRED KAFKA REPLICAS READY
kafka-cluster 3 True

# Se READY = True -> Kafka cluster funzionante! 
```

### Check 3: Services Exposed

```bash
# Verifica NodePort services
kubectl get svc -n kafka-lab | grep NodePort

# Output atteso:
kafka-ui NodePort 10.x.x.x <none> 8080:30080/TCP 5m
jenkins NodePort 10.x.x.x <none> 8080:32000/TCP 5m
awx-service NodePort 10.x.x.x <none> 80:30043/TCP 3m
grafana NodePort 10.x.x.x <none> 3000:30030/TCP 5m
prometheus NodePort 10.x.x.x <none> 9090:30090/TCP 5m
```

### Check 4: URLs Accessibili

```bash
# Testa tutte le interfacce web
echo "Testing UIs..."

# Kafka UI
curl -s http://localhost:30080 > /dev/null && echo " Kafka UI: OK" || echo " Kafka UI: FAIL"

# Jenkins
curl -s http://localhost:32000 > /dev/null && echo " Jenkins: OK" || echo " Jenkins: FAIL"

# AWX
curl -s http://localhost:30043 > /dev/null && echo " AWX: OK" || echo " AWX: FAIL"

# Grafana
curl -s http://localhost:30030 > /dev/null && echo " Grafana: OK" || echo " Grafana: FAIL"

# Prometheus
curl -s http://localhost:30090 > /dev/null && echo " Prometheus: OK" || echo " Prometheus: FAIL"
```

### Check 5: Kafka Funzionante (Test End-to-End)

```bash
# Entra nel pod Kafka
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Dentro il pod:

# 1. Crea file properties per autenticazione
cat > /tmp/admin.properties << 'EOF'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# 2. Lista broker (dovrebbe mostrare 0, 1, 2)
/opt/kafka/bin/kafka-broker-api-versions.sh \
 --bootstrap-server localhost:9092 \
 --command-config /tmp/admin.properties \
 | grep "id:"

# Output atteso:
# kafka-cluster-kafka-0.kafka-cluster-kafka-brokers.kafka-lab.svc:9092 (id: 0 rack: null)
# kafka-cluster-kafka-1.kafka-cluster-kafka-brokers.kafka-lab.svc:9092 (id: 1 rack: null)
# kafka-cluster-kafka-2.kafka-cluster-kafka-brokers.kafka-lab.svc:9092 (id: 2 rack: null)

# 3. Lista topic (dovrebbe almeno mostrare __consumer_offsets)
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --list \
 --command-config /tmp/admin.properties

# 4. Crea topic di test
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic test-deployment \
 --partitions 3 \
 --replication-factor 3 \
 --command-config /tmp/admin.properties

# Output atteso: Created topic test-deployment.

# 5. Produce messaggio
echo "Hello Kafka!" | /opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-deployment \
 --producer.config /tmp/admin.properties

# 6. Consuma messaggio
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-deployment \
 --from-beginning \
 --max-messages 1 \
 --consumer.config /tmp/admin.properties

# Output atteso: Hello Kafka!

# 7. Esci dal pod
exit

# Se tutto funziona -> Kafka cluster OK!
```

---

## 6. PRIMO UTILIZZO JENKINS

### Accesso Iniziale

```bash
# 1. Apri browser
open http://localhost:32000

# 2. Login
Username: admin
Password: admin123

# 3. Se chiede "Unlock Jenkins":
# Recupera password iniziale:
kubectl exec -it $(kubectl get pods -n kafka-lab -l app=jenkins -o name) -n kafka-lab -- \
 cat /var/jenkins_home/secrets/initialAdminPassword

# 4. Prima volta: "Install suggested plugins"
# Aspetta ~2-3 minuti

# 5. Crea admin user (o skip and continue as admin)
```

### Verifica Jobs Pre-configurati

```bash
# Dalla Home Jenkins dovresti vedere folder:
 kafka-operations/
 deploy-topic
 deploy-user
 health-check
 consumer-lag
```

### Primo Job: Health Check

```bash
# 1. Click su "kafka-operations" -> "health-check"
# 2. Click "Build Now"
# 3. Aspetta ~30 secondi
# 4. Click su "#1" (numero build)
# 5. Click "Console Output"

# Output atteso:
# Started by user admin
# Running on kubernetes agent
# 
# [health-check] Checking Kafka brokers...
# kafka-cluster-kafka-0: Running
# kafka-cluster-kafka-1: Running 
# kafka-cluster-kafka-2: Running
# 
# [health-check] Broker count: 3/3
# All brokers online
# 
# Finished: SUCCESS
```

### Primo Job Interattivo: Deploy Topic

```bash
# 1. Click "kafka-operations" -> "deploy-topic"
# 2. Click "Build with Parameters"
# 3. Compila:
# TOPIC_NAME: my-first-topic
# PARTITIONS: 6
# REPLICAS: 3
# RETENTION_MS: 604800000
# 4. Click "Build"
# 5. Aspetta ~1-2 minuti
# 6. Verifica in Kafka UI: http://localhost:30080
```

---

## 7. PRIMO UTILIZZO AWX

### Accesso Iniziale

```bash
# 1. Recupera password AWX
kubectl get secret awx-admin-password -n kafka-lab \
 -o jsonpath="{.data.password}" | base64 -d
echo

# Copia la password che vedi

# 2. Apri browser
open http://localhost:30043

# 3. Login
Username: admin
Password: [quella copiata sopra]
```

### Setup Iniziale AWX

```bash
# Prima volta in AWX, devi configurare:

# 1. CREDENTIALS
# Dashboard -> Credentials -> Add
# Name: Kubernetes ServiceAccount
# Type: Kubernetes
# -> Lascia vuoto (userà ServiceAccount del pod)

# 2. INVENTORY
# Inventories -> Add
# Name: Kafka Lab
# Type: Inventory
# 
# -> Sources -> Add
# Name: Kubernetes Pods
# Source: Custom Script
# Script:
```

```python
#!/usr/bin/env python3
import json

# Inventario statico per Kafka Lab
inventory = {
 "kafka_brokers": {
 "hosts": [
 "kafka-cluster-kafka-0",
 "kafka-cluster-kafka-1",
 "kafka-cluster-kafka-2"
 ],
 "vars": {
 "ansible_connection": "kubectl",
 "ansible_kubectl_namespace": "kafka-lab"
 }
 },
 "_meta": {
 "hostvars": {}
 }
}

print(json.dumps(inventory, indent=2))
```

```bash
# 3. PROJECT
# Projects -> Add
# Name: Kafka Playbooks
# SCM Type: Manual
# Playbook Directory: /runner/project
# 
# -> Carica playbooks dal progetto kafka-fix

# 4. JOB TEMPLATE
# Templates -> Add Job Template
# Name: Kafka Health Check
# Job Type: Run
# Inventory: Kafka Lab
# Project: Kafka Playbooks
# Playbook: kafka_health.yml
# Credentials: Kubernetes ServiceAccount
```

### Primo Job AWX: Health Check

```bash
# 1. Templates -> "Kafka Health Check"
# 2. Click rocket icon (Launch)
# 3. Aspetta esecuzione

# Vedrai output Ansible in tempo reale:
# PLAY [Kafka Health Check] ******
# 
# TASK [Banner] *******************
# ok: [localhost] => {
# "msg": [
# "==================",
# "KAFKA HEALTH CHECK",
# "==================",
# "Cluster: kafka-cluster",
# "Namespace: kafka-lab"
# ]
# }
# 
# PLAY RECAP **********************
# localhost: ok=5 changed=0
```

---

## 8. QUANDO USARE JENKINS VS AWX

### USA JENKINS PER:

```
 Create Kafka Topic
 Frequenza: Quotidiana
 User: Developers
 Tempo: 2 minuti
 -> Jenkins job "deploy-topic"

 Create Kafka User + ACL
 Frequenza: Quotidiana
 User: Security Team / Developers
 Tempo: 2 minuti
 -> Jenkins job "deploy-user"

 Deploy Kafka Connector
 Frequenza: Settimanale
 User: Data Engineers
 Tempo: 3 minuti
 -> Jenkins job "deploy-connector"

 Health Check (automated)
 Frequenza: Ogni 30 minuti (automatico)
 User: Sistema
 Tempo: 30 secondi
 -> Jenkins scheduled job

 Consumer Lag Monitoring
 Frequenza: Ogni 5 minuti (automatico)
 User: Sistema
 Tempo: 20 secondi
 -> Jenkins scheduled job
```

###  USA AWX PER:

```
 Full Cluster Test
 Frequenza: Settimanale
 User: SRE
 Tempo: 5-10 minuti
 -> AWX Template "Full Kafka Test"
 Include: health, topic test, producer/consumer test, ACL test

 Security Audit
 Frequenza: Settimanale
 User: Security Team
 Tempo: 3-5 minuti
 -> AWX Template "Security Audit"
 Include: list all users, list all ACLs, verify compliance

 Backup Configuration
 Frequenza: Giornaliera (scheduled nightly)
 User: Sistema
 Tempo: 10 minuti
 -> AWX Template "Backup Kafka Config"
 Include: export topic configs, export user/ACLs, upload to S3

 Scale Kafka Cluster
 Frequenza: Mensile
 User: Platform Team (con approval)
 Tempo: 30-60 minuti
 -> AWX Workflow "Scale Cluster"
 Include: add brokers, rebalance partitions, verify

 Disaster Recovery
 Frequenza: Solo emergenze
 User: SRE on-call (con approval senior)
 Tempo: 1-3 ore
 -> AWX Workflow "Disaster Recovery"
 Include: restore from backup, verify data integrity
```

### Decision Tree

```
Ho bisogno di...

 Creare/modificare risorse Kafka? (topic, user, connector)
 Frequenza > 1 volta/settimana?
 YES -> JENKINS 
 NO -> AWX (con approval)

 Monitoring/Health check?
 Automatico e frequente?
 YES -> JENKINS (scheduled) 
 NO -> AWX (report completo)

 Operazione complessa multi-step?
 Richiede > 10 task Ansible?
 YES -> AWX 
 NO -> Jenkins

 Serve approval/change management?
 YES -> AWX 
 NO -> Jenkins

 Operazione critica su production?
 YES -> AWX (RBAC + audit) 
 NO -> Jenkins
```

---

## 9. ESEMPI PRATICI

### Esempio 1: Developer Crea Topic per Nuovo Microservizio

```
SCENARIO:
Developer sta sviluppando "notification-service"
Serve topic "notification-events"

TOOL: JENKINS 

STEPS:
1. Developer apre Jenkins: http://localhost:32000
2. kafka-operations -> deploy-topic -> Build with Parameters
3. Compila:
 - TOPIC_NAME: notification-events
 - PARTITIONS: 6
 - REPLICAS: 3
 - RETENTION_MS: 604800000 (7 giorni)
4. Build
5. [2 minuti dopo] Topic pronto! 

Notifica Slack (opzionale):
" New topic created: notification-events by dev@company.com"

PERCHÉ JENKINS:
- Operazione semplice (1 risorsa)
- Frequente (developers fanno questo quotidianamente)
- Self-service (no approval needed)
- Veloce (< 3 minuti)
```

### Esempio 2: SRE Fa Full Test Cluster Settimanale

```
SCENARIO:
Ogni Monday mattina, SRE verifica salute completa cluster

TOOL: AWX 

STEPS:
1. SRE apre AWX: http://localhost:30043
2. Templates -> "Full Kafka Test"
3. Launch
4. [5-10 minuti] AWX esegue:
 Health check (3 broker online?)
 Create test topic
 Produce 1000 messages
 Consume 1000 messages
 Verify no data loss
 Check ACLs compliance
 Check disk usage
 Generate PDF report
 Email report to SRE team

PERCHÉ AWX:
- Operazione complessa (20+ task)
- Scheduling (ogni Monday 8 AM)
- Report dettagliato necessario
- Audit trail importante
```

### Esempio 3: Data Engineer Deploy CDC Connector

```
SCENARIO:
Data Engineer vuole stream "orders" table da PostgreSQL -> Kafka

TOOL: JENKINS 

STEPS:
1. Data Engineer apre Jenkins
2. kafka-operations -> deploy-connector -> Build with Parameters
3. Compila:
 - CONNECTOR_TYPE: PostgreSQL CDC
 - DATABASE_HOST: postgres-db.production
 - DATABASE_NAME: ecommerce
 - TABLES: orders
 - CONNECTOR_NAME: orders-cdc
4. Build
5. [3 minuti] Connector deployed e streaming! 

PERCHÉ JENKINS:
- Operazione frequente (data engineers fanno spesso)
- Template pre-configurato (facile)
- Risultato immediato
```

### Esempio 4: Platform Team Scala Cluster da 3 a 5 Nodi

```
SCENARIO:
Cluster sotto carico, serve scalare

TOOL: AWX 

STEPS:
1. Platform Lead apre AWX
2. Templates -> "Scale Kafka Cluster"
3. Survey:
 - Current replicas: 3
 - Target replicas: 5
 - Rebalance partitions: Yes
 - Approval required: Yes
4. Submit
5. [APPROVAL STEP]
 Senior SRE riceve notifica
 Review plan
 Approve
6. [60 minuti] AWX esegue:
 Backup current config
 Update KafkaNodePool replicas: 5
 Wait for new brokers ready
 Generate partition reassignment plan
 Execute reassignment
 Monitor progress
 Verify rebalance complete
 Update monitoring dashboards

PERCHÉ AWX:
- Operazione critica (production impact)
- Approval necessario
- Multi-step complesso (30+ task)
- Audit trail essenziale
- Rollback plan incluso
```

---

## 10. TROUBLESHOOTING

### Problema: Pod non diventa Ready

```bash
# 1. Identifica quale pod
kubectl get pods -n kafka-lab | grep -v Running

# 2. Vedi dettagli
kubectl describe pod <pod-name> -n kafka-lab

# 3. Vedi log
kubectl logs <pod-name> -n kafka-lab

# Soluzioni comuni:

# Pod Pending (manca risorse):
# -> Aumenta RAM Docker Desktop

# Pod CrashLoopBackOff:
# -> Vedi logs per errore specifico

# Pod ImagePullBackOff:
# -> Check connessione internet
```

### Problema: Kafka Pod non parte

```bash
# Kafka richiede PersistentVolume
kubectl get pvc -n kafka-lab

# Se PVC Pending:
kubectl describe pvc data-kafka-cluster-kafka-0 -n kafka-lab

# Soluzione:
# Docker Desktop ha StorageClass default
# Se manca, crea PV manualmente
```

### Problema: Jenkins non accessibile

```bash
# 1. Verifica Service
kubectl get svc jenkins -n kafka-lab

# 2. Verifica NodePort
kubectl get svc jenkins -n kafka-lab -o yaml | grep nodePort

# 3. Test local port
nc -zv localhost 32000

# Se fallisce:
# -> Controlla firewall Mac
# -> Prova port-forward:
kubectl port-forward -n kafka-lab svc/jenkins 8080:8080
# Poi accedi: http://localhost:8080
```

### Problema: AWX password non funziona

```bash
# 1. Recupera di nuovo
kubectl get secret awx-admin-password -n kafka-lab \
 -o jsonpath="{.data.password}" | base64 -d && echo

# 2. Se ancora non funziona, reset:
kubectl delete secret awx-admin-password -n kafka-lab
kubectl delete pod -l app.kubernetes.io/name=awx -n kafka-lab

# AWX rigenererà password
# Aspetta pod restart (~3 min)
# Riprova
```

### Problema: Strimzi non crea Kafka

```bash
# 1. Verifica Strimzi Operator log
kubectl logs -n kafka-lab deployment/strimzi-cluster-operator

# 2. Verifica Kafka CRD
kubectl get kafka kafka-cluster -n kafka-lab -o yaml

# Cerca nella sezione status per errori

# 3. Se Kafka non si crea:
# Verifica risorse sufficienti:
kubectl top nodes

# Se nodo saturo:
# -> Aumenta RAM/CPU Docker Desktop
```

### Reset Completo

```bash
# Se qualcosa va storto e vuoi ricominciare:

# 1. Rimuovi tutto
helm uninstall kafka-lab -n kafka-lab
helm uninstall strimzi-operator -n kafka-lab

# 2. Pulisci PVC (ATTENZIONE: cancella dati!)
kubectl delete pvc --all -n kafka-lab

# 3. Rimuovi namespace
kubectl delete namespace kafka-lab

# 4. Aspetta cleanup completo
kubectl get namespaces | grep kafka-lab
# Non dovrebbe mostrare nulla

# 5. Ricomincia da Step 3 (Deploy Strimzi)
```

---

## CHECKLIST FINALE

```
Prima di considerare il setup completo, verifica:

KUBERNETES:
 kubectl get nodes -> docker-desktop Ready
 Docker Desktop ha 8GB+ RAM allocati

STRIMZI:
 kubectl get pods -n kafka-lab | grep strimzi -> Running
 kubectl get kafka -n kafka-lab -> READY=True

KAFKA:
 kubectl get pods -n kafka-lab | grep kafka-cluster-kafka -> 3x Running
 kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- kafka-broker-api-versions.sh -> 3 broker

JENKINS:
 http://localhost:32000 -> Login page
 Jobs visibili in kafka-operations/
 Health-check job eseguito con successo

AWX:
 http://localhost:30043 -> Login page
 Inventory configurato
 Job Template health-check eseguito

MONITORING:
 http://localhost:30080 -> Kafka UI mostra cluster
 http://localhost:30030 -> Grafana accessibile
 http://localhost:30090 -> Prometheus accessibile

TEST END-TO-END:
 Topic creato via Jenkins
 Messaggio prodotto e consumato
 Health check AWX completato
```

---

## PROSSIMI PASSI

Ora che hai tutto funzionante:

1. **Esplora esercizi** in `esercizi/CORSO_COMPLETO_KAFKA_SYSADMIN_60_ESERCIZI.md`
2. **Crea pipeline Jenkins custom** per tuoi use case
3. **Configura AWX workflows** per operazioni complesse
4. **Integra Kafka Connect** per CDC da PostgreSQL
5. **Setup alert** Prometheus -> Slack
6. **Pratica disaster recovery** con AWX

Buon lavoro! 
