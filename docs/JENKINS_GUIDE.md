# JENKINS CI/CD PER KAFKA - GUIDA COMPLETA

## Indice

1. [Cos'è e Perché Serve](#1-cosè-e-perché-serve)
2. [Architettura](#2-architettura)
3. [Installazione](#3-installazione)
4. [Jobs Pre-configurati](#4-jobs-pre-configurati)
5. [Esercizi Pratici](#5-esercizi-pratici)
6. [Creare Nuove Pipeline](#6-creare-nuove-pipeline)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Cos'è e Perché Serve

### Il Problema SENZA Jenkins

```
SCENARIO TIPICO (MANUALE):

1. Developer: "Ho bisogno del topic order-events"
2. Tu apri Slack, leggi il messaggio
3. Tu ti colleghi al cluster: kubectl exec -it kafka-cluster-kafka-0 ...
4. Tu crei il file YAML a mano
5. Tu esegui: kubectl apply -f topic.yaml
6. Tu verifichi che funzioni
7. Tu rispondi su Slack: "Fatto"

PROBLEMI:
 Tempo perso (30 min per un topic)
 Errori di battitura possibili
 Nessun audit (chi ha creato cosa?)
 Non riproducibile
 Se sei in ferie, nessuno può farlo
```

### La Soluzione CON Jenkins

```
SCENARIO CON JENKINS:

1. Developer: Apre Jenkins -> "Deploy Kafka Topic"
2. Compila il form: nome=order-events, partitions=6, replicas=3
3. Click "Build"
4. Jenkins: Valida -> Genera YAML -> Applica -> Verifica -> Notifica

VANTAGGI:
 2 minuti invece di 30
 Zero errori (tutto automatico)
 Audit completo (log di ogni build)
 Self-service per developer
 Funziona anche quando sei in ferie
```

### Cosa Fa Jenkins nel Tuo Lab

```

 JENKINS NEL TUO LAB 



 JENKINS KAFKA-LAB 
 (namespace: (namespace: 
 jenkins) kafka-lab) 

 kubectl 
 Deploy KafkaTopic 
 Topic 


 kubectl KafkaUser 
 Deploy 
 User 

 Kafka 
 kubectl Broker 
 Health 
 Check exec 

 Connect 
 kubectl 
 Consumer 
 Lag 



 :32000 (NodePort) 

 TU (Browser) 


```

---

## 2. Architettura

### Componenti Jenkins nel Cluster

| Componente | Descrizione | Namespace |
|------------|-------------|-----------|
| **Jenkins Controller** | Server principale, UI, gestisce i job | `jenkins` |
| **Jenkins Agent** | Esegue i job (pod dinamici K8s) | `jenkins` |
| **ServiceAccount** | Permette a Jenkins di usare kubectl | `jenkins` |
| **ClusterRoleBinding** | Dà permessi su namespace `kafka-lab` | cluster-wide |
| **PVC** | Storage per config e job history | `jenkins` |

### Flusso di un Job

```

 FLUSSO JOB JENKINS 


 1. TRIGGER 

 Manuale (click "Build") 
 Schedulato (cron) 
 Webhook (git push) 

 2. JENKINS CONTROLLER 

 Crea Pod Agent (kafka-agent) 

 Contiene: kubectl, jnlp 

 3. ESECUZIONE (nel Pod Agent) 

 Stage: Validate 
 Stage: Generate YAML 
 Stage: Deploy (kubectl apply) 
 Stage: Verify 

 4. CLEANUP 

 Pod Agent eliminato automaticamente 

 5. NOTIFICA 

 Log, Slack (se configurato), Email 


```

---

## 3. Installazione

### 3.1 Prerequisiti

- Cluster Kubernetes funzionante (Minikube, Docker Desktop, etc.)
- Helm installato
- Il chart kafka-lab già deployato

### 3.2 Deploy con Helm

```bash
# Se Jenkins è già abilitato in values.yaml (enabled: true)
cd kafka-fix/helm
helm upgrade --install kafka-lab . -n kafka-lab --create-namespace

# Verifica che Jenkins sia stato creato
kubectl get pods -n jenkins
kubectl get svc -n jenkins
```

### 3.3 Primo Accesso

```bash
# 1. Ottieni l'URL
# Se usi Minikube:
minikube service jenkins -n jenkins --url

# Se usi Docker Desktop/altro:
# http://localhost:32000

# 2. Credenziali di default
# Username: admin
# Password: admin123 (o quello che hai messo in values.yaml)
```

### 3.4 Verifica Installazione

```bash
# Pod Jenkins running
kubectl get pods -n jenkins
# NAME READY STATUS RESTARTS AGE
# jenkins-xxxx-yyyy 1/1 Running 0 5m

# Service esposto
kubectl get svc -n jenkins
# NAME TYPE CLUSTER-IP PORT(S) 
# jenkins NodePort 10.96.xxx.xxx 8080:32000/TCP

# ServiceAccount con permessi
kubectl get clusterrolebinding jenkins-kafka-admin-binding
# NAME ROLE 
# jenkins-kafka-admin-binding ClusterRole/jenkins-kafka-admin
```

---

## 4. Jobs Pre-configurati

Il chart installa automaticamente 4 job pronti all'uso:

### 4.1 Deploy Kafka Topic

**Percorso:** `kafka-operations/deploy-topic`

**Cosa fa:**
1. Valida i parametri inseriti
2. Genera il YAML del KafkaTopic
3. Applica con `kubectl apply`
4. Verifica che il topic sia pronto

**Parametri:**

| Parametro | Descrizione | Default |
|-----------|-------------|---------|
| `TOPIC_NAME` | Nome del topic | (obbligatorio) |
| `PARTITIONS` | Numero partizioni | 6 |
| `REPLICAS` | Fattore di replica | 3 |
| `RETENTION_MS` | Retention in millisecondi | 604800000 (7 giorni) |
| `ENVIRONMENT` | Ambiente (dev/prod) | dev |

**Esempio Output:**
```
[Pipeline] stage (Validate)
 Validazione OK: order-events

[Pipeline] stage (Generate YAML)
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
 name: order-events
 namespace: kafka-lab
...

[Pipeline] stage (Deploy)
kafkatopic.kafka.strimzi.io/order-events created

[Pipeline] stage (Verify)
NAME CLUSTER PARTITIONS REPLICATION FACTOR READY
order-events kafka-cluster 6 3 True

 Topic order-events deployato con successo!
```

---

### 4.2 Deploy Kafka User

**Percorso:** `kafka-operations/deploy-user`

**Cosa fa:**
1. Genera KafkaUser con ACL appropriate
2. Applica con `kubectl apply`
3. Mostra la password generata (dal Secret)

**Parametri:**

| Parametro | Descrizione | Opzioni |
|-----------|-------------|---------|
| `USER_NAME` | Nome utente | (obbligatorio) |
| `USER_TYPE` | Tipo utente | producer, consumer, admin |
| `TOPIC_PATTERN` | Pattern topic | `*` o prefix (es: `order-`) |

**ACL generate per tipo:**

| Tipo | ACL |
|------|-----|
| **producer** | Write, Describe, Create su topic |
| **consumer** | Read, Describe su topic + Read su group |
| **admin** | All su topic, group, cluster |

---

### 4.3 Kafka Health Check

**Percorso:** `kafka-operations/health-check`

**Cosa fa:**
1. Verifica stato pod Kafka
2. Lista tutti i topic
3. Verifica Kafka Connect
4. Lista utenti
5. Test connettività broker

**Schedulazione:** Ogni 30 minuti (automatico)

**Output esempio:**
```
=== STATO POD KAFKA ===
NAME READY STATUS RESTARTS
kafka-cluster-kafka-0 1/1 Running 0
kafka-cluster-kafka-1 1/1 Running 0
kafka-cluster-kafka-2 1/1 Running 0

=== KAFKA TOPICS ===
NAME PARTITIONS REPLICAS READY
order-events 6 3 True
test-topic 3 3 True

=== KAFKA CONNECT ===
NAME DESIRED READY
kafka-connect 1 1

=== KAFKA USERS ===
NAME AUTHENTICATION AUTHORIZATION
admin scram-sha-512 simple
producer-user scram-sha-512 simple
```

---

### 4.4 Consumer Lag Monitor

**Percorso:** `kafka-operations/list-consumer-lag`

**Cosa fa:**
1. Lista tutti i consumer group
2. Per ogni gruppo, mostra offset e LAG

**Output esempio:**
```
=== CONSUMER GROUPS ===
console-consumer-12345
order-processor-group

=== CONSUMER LAG ===
--- Group: order-processor-group ---
GROUP TOPIC PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG
order-processor-group order-events 0 150 150 0
order-processor-group order-events 1 148 150 2
order-processor-group order-events 2 152 152 0
```

---

## 5. Esercizi Pratici

### Esercizio 1: Crea il Tuo Primo Topic via Jenkins

**Obiettivo:** Familiarizzare con l'interfaccia Jenkins

**Passi:**

1. Apri Jenkins: `http://localhost:32000`
2. Login: admin / admin123
3. Vai su: `kafka-operations` -> `deploy-topic`
4. Click: "Build with Parameters"
5. Compila:
 ```
 TOPIC_NAME: mio-primo-topic
 PARTITIONS: 3
 REPLICAS: 3
 RETENTION_MS: 86400000 (1 giorno)
 ENVIRONMENT: dev
 ```
6. Click "Build"
7. Guarda i log (click sul numero del build -> Console Output)

**Verifica:**
```bash
kubectl get kafkatopic mio-primo-topic -n kafka-lab
```

---

### Esercizio 2: Crea un Utente Producer

**Obiettivo:** Creare un utente che può scrivere solo su topic order-*

**Passi:**

1. Vai su: `kafka-operations` -> `deploy-user`
2. Compila:
 ```
 USER_NAME: order-writer
 USER_TYPE: producer
 TOPIC_PATTERN: order-
 ```
3. Build

**Verifica:**
```bash
# Vedi l'utente
kubectl get kafkauser order-writer -n kafka-lab

# Vedi la password
kubectl get secret order-writer -n kafka-lab -o jsonpath='{.data.password}' | base64 -d
```

---

### Esercizio 3: Monitora il Cluster

**Obiettivo:** Usare il health check per diagnostica

**Passi:**

1. Vai su: `kafka-operations` -> `health-check`
2. Click "Build Now"
3. Analizza l'output:
 - Tutti i pod sono Running?
 - I topic sono Ready?
 - Connect è attivo?

---

### Esercizio 4: Simula un Problema e Diagnosticalo

**Obiettivo:** Usare Jenkins per troubleshooting

**Setup (simula problema):**
```bash
# Crea un consumer group con lag
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Produci messaggi
cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

for i in {1..100}; do
 echo "message-$i" | /opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic mio-primo-topic \
 --producer.config /tmp/admin.properties
done

exit
```

**Diagnosi con Jenkins:**
1. Vai su: `kafka-operations` -> `list-consumer-lag`
2. Build
3. Vedi che `mio-primo-topic` ha messaggi non consumati

---

### Esercizio 5: Crea un Job Personalizzato

**Obiettivo:** Imparare a creare nuove pipeline

1. Jenkins -> New Item
2. Nome: `delete-topic`
3. Tipo: Pipeline
4. Script:

```groovy
pipeline {
 agent { label 'kafka-agent' }

 parameters {
 string(name: 'TOPIC_NAME', description: 'Topic da eliminare')
 booleanParam(name: 'CONFIRM', defaultValue: false, description: 'Conferma eliminazione')
 }

 stages {
 stage('Confirm') {
 steps {
 script {
 if (!params.CONFIRM) {
 error "Devi confermare l'eliminazione!"
 }
 }
 }
 }

 stage('Delete') {
 steps {
 container('kubectl') {
 sh "kubectl delete kafkatopic ${params.TOPIC_NAME} -n kafka-lab"
 }
 }
 }
 }
}
```

5. Salva e testa

---

## 6. Creare Nuove Pipeline

### Template Base

```groovy
pipeline {
 // Usa l'agent con kubectl
 agent { label 'kafka-agent' }

 // Variabili globali
 environment {
 KAFKA_NAMESPACE = 'kafka-lab'
 KAFKA_CLUSTER = 'kafka-cluster'
 }

 // Parametri (form di input)
 parameters {
 string(name: 'MY_PARAM', defaultValue: '', description: 'Descrizione')
 choice(name: 'MY_CHOICE', choices: ['opt1', 'opt2'], description: 'Scegli')
 booleanParam(name: 'MY_BOOL', defaultValue: false, description: 'Flag')
 }

 stages {
 stage('Nome Stage') {
 steps {
 container('kubectl') {
 sh '''
 # Comandi bash
 kubectl get pods -n $KAFKA_NAMESPACE
 '''
 }
 }
 }
 }

 post {
 success {
 echo " Completato!"
 }
 failure {
 echo " Fallito!"
 }
 }
}
```

### Esempi Utili

**Pipeline: Scala Partizioni Topic**
```groovy
stage('Scale Partitions') {
 steps {
 container('kubectl') {
 sh """
 kubectl patch kafkatopic ${params.TOPIC_NAME} -n kafka-lab \
 --type merge -p '{"spec":{"partitions": ${params.NEW_PARTITIONS}}}'
 """
 }
 }
}
```

**Pipeline: Backup Topic Config**
```groovy
stage('Backup') {
 steps {
 container('kubectl') {
 sh '''
 kubectl get kafkatopic -n kafka-lab -o yaml > topics-backup.yaml
 kubectl get kafkauser -n kafka-lab -o yaml > users-backup.yaml
 '''
 archiveArtifacts artifacts: '*-backup.yaml'
 }
 }
}
```

**Pipeline: Test Produce/Consume**
```groovy
stage('E2E Test') {
 steps {
 container('kubectl') {
 sh '''
 # Produce
 kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- \
 bash -c "echo 'test-$(date +%s)' | /opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --producer.config /tmp/admin.properties"

 # Consume
 RESULT=$(kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --from-beginning \
 --max-messages 1 \
 --timeout-ms 10000 \
 --consumer.config /tmp/admin.properties)

 echo "Received: $RESULT"
 '''
 }
 }
}
```

---

## 7. Troubleshooting

### Problema: Jenkins non parte

```bash
# Check pod
kubectl describe pod -n jenkins -l app=jenkins

# Check logs
kubectl logs -n jenkins -l app=jenkins

# Cause comuni:
# - PVC non creato (storage class mancante)
# - Risorse insufficienti
# - Init container fallito (rete per download plugin)
```

### Problema: Job fallisce con "permission denied"

```bash
# Verifica ServiceAccount
kubectl get sa jenkins -n jenkins

# Verifica ClusterRoleBinding
kubectl describe clusterrolebinding jenkins-kafka-admin-binding

# Fix: ricrea il binding
kubectl delete clusterrolebinding jenkins-kafka-admin-binding
helm upgrade kafka-lab . -n kafka-lab
```

### Problema: Agent pod non parte

```bash
# Check pod agent
kubectl get pods -n jenkins -l jenkins=agent

# Verifica che il controller Jenkins sia raggiungibile
kubectl exec -it <jenkins-pod> -n jenkins -- curl http://jenkins:8080
```

### Problema: kubectl non funziona nel job

```bash
# Verifica che il container kubectl sia nel template
# Il job deve usare: container('kubectl') { ... }

# Verifica manualmente
kubectl run test-kubectl --image=bitnami/kubectl -it --rm -- kubectl get pods -n kafka-lab
```

---

## Riepilogo Comandi Utili

```bash
# === JENKINS ===
# Accesso UI
http://localhost:32000 # admin / admin123

# Restart Jenkins
kubectl rollout restart deployment jenkins -n jenkins

# Vedi log
kubectl logs -f -n jenkins -l app=jenkins

# === VERIFICA RISORSE CREATE ===
# Topic creati da Jenkins
kubectl get kafkatopic -n kafka-lab -l managed-by=jenkins

# User creati da Jenkins
kubectl get kafkauser -n kafka-lab -l managed-by=jenkins

# === DEBUG ===
# Entra nel pod Jenkins
kubectl exec -it -n jenkins $(kubectl get pod -n jenkins -l app=jenkins -o name) -- bash

# Vedi config JCasC
kubectl get configmap jenkins-casc-config -n jenkins -o yaml
```

---

## Prossimi Passi

1. **Integra con Git**: Crea un repo con i YAML e trigga Jenkins su push
2. **Aggiungi Slack**: Notifiche su canale Slack per ogni deploy
3. **Multi-environment**: Usa i parametri per DEV/STAGING/PROD
4. **Approval Gate**: Aggiungi `input` per approvazione manuale su PROD

---

**Fine Guida Jenkins**

Versione: 1.0 
Integrato con: kafka-lab-kraft-fixed 
Namespace Jenkins: jenkins 
Namespace Kafka: kafka-lab
