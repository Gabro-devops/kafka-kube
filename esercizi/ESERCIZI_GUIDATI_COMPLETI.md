# KAFKA LAB - ESERCIZI GUIDATI PASSO-PASSO

## COME FUNZIONA IN PRODUZIONE (GitOps)

```
IN PRODUZIONE NON SI FA MAI kubectl apply A MANO!


 Developer Git Repo ArgoCD/ Kubernetes 
 crea PR (GitHub) Flux Cluster 


FLUSSO REALE:
1. Developer apre Pull Request con file YAML
2. Tech Lead fa review e approva
3. PR viene merged nel branch main
4. ArgoCD/Flux rileva il cambiamento e applica automaticamente
5. Tutto è tracciato, versionato, reversibile

NOI OGGI: Facciamo a mano per imparare, ma il concetto è identico.
```

---

# ESERCIZIO 1: HEALTH CHECK 
**Tempo: 5 minuti**

## Scenario
È lunedì mattina, inizi il turno. Prima cosa: verificare che tutto funzioni.

## Step 1.1: Verifica cluster Kafka
```bash
kubectl get kafka -n kafka-lab
```
**Output atteso:**
```
NAME READY WARNINGS KAFKA VERSION METADATA VERSION
kafka-cluster True 4.0.0 4.0-IV3
```
 Se vedi `READY: True` → cluster OK

## Step 1.2: Verifica pods
```bash
kubectl get pods -n kafka-lab
```
**Output atteso:** Tutti i pod devono essere `Running` e `READY` completo (es. 1/1, 2/2)

## Step 1.3: Verifica utenti esistenti
```bash
kubectl get kafkauser -n kafka-lab
```
**Output atteso:** Lista degli utenti Kafka (admin, producer-user, consumer-user)

## Step 1.4: Verifica topics esistenti
```bash
kubectl get kafkatopic -n kafka-lab
```
**Output atteso:** Lista dei topic (potrebbe essere vuota inizialmente)

## Step 1.5: Verifica visivamente in Kafka UI
1. Apri browser: http://localhost:30080
2. Clicca su "Brokers" → Devi vedere 3 broker
3. Clicca su "Topics" → Lista dei topic

## Checklist Esercizio 1
- [ ] Kafka cluster READY: True
- [ ] Tutti i pod Running
- [ ] Kafka UI accessibile e mostra i broker

---

# ESERCIZIO 2: CREA TOPIC 
**Tempo: 10 minuti**

## Scenario
Il team "Orders" ha bisogno di un topic per gli eventi ordine.

## Requisiti
- Nome: `order-events`
- Partizioni: 6 (per parallelismo)
- Repliche: 3 (alta disponibilità)
- Retention: 7 giorni

## Step 2.1: Crea il file YAML
```bash
cat << 'EOF' > ./esercizi/order-events-topic.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
 name: order-events
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 partitions: 6
 replicas: 3
 config:
 retention.ms: "604800000"
 cleanup.policy: "delete"
EOF
```

## Step 2.2: Applica il file
```bash
kubectl apply -f ./esercizi/order-events-topic.yaml
```
**Output atteso:**
```
kafkatopic.kafka.strimzi.io/order-events created
```

## Step 2.3: Verifica creazione
```bash
kubectl get kafkatopic order-events -n kafka-lab
```
**Output atteso:**
```
NAME CLUSTER PARTITIONS REPLICATION FACTOR READY
order-events kafka-cluster 6 3 True
```

## Step 2.4: Verifica in Kafka UI
1. Vai su http://localhost:30080
2. Clicca su "Topics"
3. Trova "order-events"
4. Verifica: 6 partizioni, replication factor 3

## Checklist Esercizio 2
- [ ] File YAML creato
- [ ] Topic applicato senza errori
- [ ] Topic visibile con kubectl
- [ ] Topic visibile in Kafka UI

---

# ESERCIZIO 3: CREA UTENTE PRODUCER 
**Tempo: 15 minuti**

## Scenario
Il microservizio `order-service` deve poter SCRIVERE su `order-events`.

## Principio: Least Privilege
L'utente avrà SOLO permesso di Write sul topic specifico, nient'altro.

## Step 3.1: Crea il Secret con la password
```bash
cat << 'EOF' > ./esercizi/order-service-secret.yaml
apiVersion: v1
kind: Secret
metadata:
 name: order-service-password
 namespace: kafka-lab
type: Opaque
stringData:
 password: "OrderService2026!"
EOF

kubectl apply -f ./esercizi/order-service-secret.yaml
```
**Output atteso:**
```
secret/order-service-password created
```

## Step 3.2: Crea l'utente con ACL
```bash
cat << 'EOF' > ./esercizi/order-service-user.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
 name: order-service
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 authentication:
 type: scram-sha-512
 password:
 valueFrom:
 secretKeyRef:
 name: order-service-password
 key: password
 authorization:
 type: simple
 acls:
 - resource:
 type: topic
 name: order-events
 patternType: literal
 operations:
 - Write
 - Describe
 host: "*"
EOF

kubectl apply -f ./esercizi/order-service-user.yaml
```
**Output atteso:**
```
kafkauser.kafka.strimzi.io/order-service created
```

## Step 3.3: Verifica utente creato
```bash
kubectl get kafkauser order-service -n kafka-lab
```
**Output atteso:**
```
NAME CLUSTER AUTHENTICATION AUTHORIZATION READY
order-service kafka-cluster scram-sha-512 simple True
```

## Step 3.4: Verifica Secret creato da Strimzi
```bash
kubectl get secret -n kafka-lab | grep order-service
```
**Output atteso:** Vedrai 2 secret:
- `order-service-password` (quello che hai creato)
- `order-service` (creato automaticamente da Strimzi con le credenziali)

## Checklist Esercizio 3
- [ ] Secret password creato
- [ ] KafkaUser creato con READY: True
- [ ] ACL configurata per Write su order-events

---

# ESERCIZIO 4: CREA UTENTE CONSUMER 
**Tempo: 10 minuti**

## Scenario
Il `payment-service` deve LEGGERE da `order-events` per processare i pagamenti.

## Step 4.1: Crea Secret e User in un unico file
```bash
cat << 'EOF' > ./esercizi/payment-service.yaml
apiVersion: v1
kind: Secret
metadata:
 name: payment-service-password
 namespace: kafka-lab
type: Opaque
stringData:
 password: "PaymentService2026!"
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
 name: payment-service
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 authentication:
 type: scram-sha-512
 password:
 valueFrom:
 secretKeyRef:
 name: payment-service-password
 key: password
 authorization:
 type: simple
 acls:
 - resource:
 type: topic
 name: order-events
 patternType: literal
 operations:
 - Read
 - Describe
 host: "*"
 - resource:
 type: group
 name: payment-service-group
 patternType: literal
 operations:
 - Read
 host: "*"
EOF

kubectl apply -f ./esercizi/payment-service.yaml
```
**Output atteso:**
```
secret/payment-service-password created
kafkauser.kafka.strimzi.io/payment-service created
```

## Step 4.2: Verifica
```bash
kubectl get kafkauser -n kafka-lab
```
**Output atteso:** Vedi tutti gli utenti incluso `payment-service`

## Checklist Esercizio 4
- [ ] payment-service creato
- [ ] ACL per Read su order-events
- [ ] ACL per consumer group

---

# ESERCIZIO 5: TEST PRODUCER/CONSUMER 
**Tempo: 20 minuti**

## Scenario
Verifica che il flusso funzioni: order-service scrive, payment-service legge.

## Step 5.1: Produci un messaggio come order-service

**Apri TERMINALE 1:**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash
```

**Dentro il pod, esegui:**
```bash
# Crea file di configurazione producer
cat << 'EOF' > ./esercizi/producer.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="order-service" password="OrderService2026!";
EOF

# Produci un messaggio
echo '{"orderId":"ORD-001","customerId":"CUST-123","amount":99.99,"status":"CREATED"}' | \
/opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic order-events \
 --producer.config ./esercizi/producer.properties

# Esci dal pod
exit
```

## Step 5.2: Consuma il messaggio come payment-service

**Apri TERMINALE 2:**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash
```

**Dentro il pod, esegui:**
```bash
# Crea file di configurazione consumer
cat << 'EOF' > ./esercizi/consumer.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="payment-service" password="PaymentService2026!";
EOF

# Consuma messaggi
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic order-events \
 --group payment-service-group \
 --consumer.config ./esercizi/consumer.properties \
 --from-beginning
```

**Output atteso:**
```
{"orderId":"ORD-001","customerId":"CUST-123","amount":99.99,"status":"CREATED"}
```

Premi `Ctrl+C` per uscire, poi `exit` per uscire dal pod.

## Step 5.3: Verifica in Kafka UI
1. Vai su http://localhost:30080
2. Topics → order-events → Messages
3. Dovresti vedere il messaggio JSON

## Checklist Esercizio 5
- [ ] Messaggio prodotto senza errori
- [ ] Messaggio consumato correttamente
- [ ] Messaggio visibile in Kafka UI

---

# ESERCIZIO 6: SIMULA POD FAILURE 
**Tempo: 15 minuti**

## Scenario
Un nodo Kafka muore. Verifica che il cluster si auto-ripari.

## Step 6.1: Verifica stato iniziale
```bash
kubectl get pods -n kafka-lab -l strimzi.io/cluster=kafka-cluster
```
**Output atteso:** 3 pod kafka Running

## Step 6.2: "Uccidi" un broker
```bash
kubectl delete pod kafka-cluster-kafka-1 -n kafka-lab
```

## Step 6.3: Osserva la riparazione automatica
```bash
kubectl get pods -n kafka-lab -l strimzi.io/cluster=kafka-cluster -w
```
**Cosa succede:**
1. kafka-cluster-kafka-1 va in Terminating
2. Strimzi crea un nuovo pod
3. Il nuovo pod passa a Running
4. Cluster torna healthy

Premi `Ctrl+C` quando il pod è tornato Running.

## Step 6.4: Verifica che i messaggi siano ancora lì
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic order-events
```
**Verifica:** Il topic ha ancora 3 repliche, nessun dato perso.

## Checklist Esercizio 6
- [ ] Pod eliminato
- [ ] Pod ricreato automaticamente
- [ ] Cluster tornato healthy
- [ ] Nessun messaggio perso (grazie a replication factor 3)

---

# ESERCIZIO 7: CONFIGURA AWX 
**Tempo: 30 minuti**

## Scenario
Configura AWX per permettere automazione enterprise.

## Step 7.1: Ottieni password AWX
```bash
kubectl get secret awx-admin-password -n kafka-lab -o jsonpath="{.data.password}" | base64 -d; echo
```
**Copia la password!**

## Step 7.2: Accedi ad AWX
1. Apri browser: http://localhost:30043
2. Username: `admin`
3. Password: (quella copiata sopra)

## Step 7.3: Crea ServiceAccount per AWX
```bash
# Crea ServiceAccount
kubectl create serviceaccount awx-automation -n kafka-lab

# Dai permessi cluster-admin
kubectl create clusterrolebinding awx-automation-admin \
 --clusterrole=cluster-admin \
 --serviceaccount=kafka-lab:awx-automation

# Genera token (COPIALO!)
kubectl create token awx-automation -n kafka-lab --duration=8760h
```
**IMPORTANTE:** Copia il token che viene stampato!

## Step 7.4: Crea Credential in AWX
1. In AWX, vai su: **Resources → Credentials → Add**
2. Compila:
 - Name: `Kubernetes`
 - Credential Type: `OpenShift or Kubernetes API Bearer Token`
 - Kubernetes API Endpoint: `https://kubernetes.default.svc`
 - API Authentication Bearer Token: (incolla il token)
 - Verify SSL: OFF (per lab)
3. Clicca **Save**

## Step 7.5: Crea Inventory
1. **Resources → Inventories → Add → Add inventory**
2. Name: `Kafka Cluster`
3. **Save**
4. Vai su **Hosts → Add**
5. Name: `localhost`
6. Variables:
```yaml
ansible_connection: local
ansible_python_interpreter: /usr/bin/python3
```
7. **Save**

## Step 7.6: Crea Project (opzionale - se hai repo Git)
1. **Resources → Projects → Add**
2. Name: `Kafka Lab`
3. Source Control Type: `Git`
4. Source Control URL: `https://github.com/TUO-USER/kafka-lab.git`
5. **Save**

## Checklist Esercizio 7
- [ ] Accesso ad AWX funzionante
- [ ] Credential Kubernetes creata
- [ ] Inventory creato
- [ ] (Opzionale) Project Git configurato

---

# ESERCIZIO 8: MONITORING E ALERTING 
**Tempo: 20 minuti**

## Scenario
Configura monitoring per vedere le metriche Kafka.

## Step 8.1: Accedi a Grafana
1. Apri browser: http://localhost:30030
2. Username: `admin`
3. Password: `admin`
4. (Ti chiede di cambiare password, puoi skippare)

## Step 8.2: Verifica Datasource Prometheus
1. Vai su: **Configuration (ingranaggio) → Data sources**
2. Dovresti vedere "Prometheus" già configurato
3. Clicca su **Test** per verificare connessione

## Step 8.3: Importa Dashboard Kafka
1. **+ (più) → Import**
2. Inserisci ID: `7589` (Strimzi Kafka Dashboard)
3. Clicca **Load**
4. Seleziona Datasource: `Prometheus`
5. **Import**

## Step 8.4: Esplora le metriche
1. Vai sulla dashboard importata
2. Dovresti vedere:
 - Brokers online
 - Messages per second
 - Bytes in/out
 - Consumer lag

## Step 8.5: Query dirette in Prometheus
1. Apri: http://localhost:30090
2. Prova queste query:
```promql
# Messaggi in ingresso per topic
kafka_server_brokertopicmetrics_messagesin_total

# Bytes in ingresso
kafka_server_brokertopicmetrics_bytesin_total

# Partizioni under-replicated (deve essere 0!)
kafka_server_replicamanager_underreplicatedpartitions
```

## Checklist Esercizio 8
- [ ] Grafana accessibile
- [ ] Datasource Prometheus funzionante
- [ ] Dashboard Kafka importata
- [ ] Metriche visibili

---

# ESERCIZIO 9: BACKUP CONFIGURAZIONE 
**Tempo: 15 minuti**

## Scenario
Esporta la configurazione per backup/disaster recovery.

## Step 9.1: Esporta tutti i KafkaTopic
```bash
kubectl get kafkatopic -n kafka-lab -o yaml > kafka-topics-backup.yaml
```

## Step 9.2: Esporta tutti i KafkaUser
```bash
kubectl get kafkauser -n kafka-lab -o yaml > kafka-users-backup.yaml
```

## Step 9.3: Esporta il cluster Kafka
```bash
kubectl get kafka -n kafka-lab -o yaml > kafka-cluster-backup.yaml
```

## Step 9.4: Verifica i file
```bash
ls -la *.yaml
cat kafka-topics-backup.yaml
```

## Step 9.5: Come fare restore (in caso di disaster)
```bash
# Su un nuovo cluster:
kubectl apply -f kafka-cluster-backup.yaml
kubectl apply -f kafka-topics-backup.yaml
kubectl apply -f kafka-users-backup.yaml
```

## Checklist Esercizio 9
- [ ] Topic esportati
- [ ] User esportati
- [ ] Cluster config esportato
- [ ] File verificati

---

# ESERCIZIO 10: SCENARIO COMPLETO 
**Tempo: 45 minuti**

## Scenario
Arriva un ticket JIRA completo per un nuovo servizio.

## Il Ticket
```
KAFKA-1234: Setup Notification Service

Il team Notifications ha bisogno di:
1. Topic "user-notifications" (partizioni: 3, retention: 3 giorni)
2. Topic "email-events" (partizioni: 6, retention: 30 giorni)
3. Utente "notification-service" che può:
 - LEGGERE da "order-events"
 - SCRIVERE su "user-notifications"
 - SCRIVERE su "email-events"
4. Utente "email-sender" che può:
 - LEGGERE da "email-events"

Deadline: Fine giornata
```

## Step 10.1: Crea i Topic
```bash
cat << 'EOF' > ./esercizi/notification-topics.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
 name: user-notifications
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
 team: notifications
spec:
 partitions: 3
 replicas: 3
 config:
 retention.ms: "259200000"
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
 name: email-events
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
 team: notifications
spec:
 partitions: 6
 replicas: 3
 config:
 retention.ms: "2592000000"
EOF

kubectl apply -f ./esercizi/notification-topics.yaml
```

## Step 10.2: Crea utente notification-service
```bash
cat << 'EOF' > ./esercizi/notification-service.yaml
apiVersion: v1
kind: Secret
metadata:
 name: notification-service-password
 namespace: kafka-lab
type: Opaque
stringData:
 password: "NotificationService2026!"
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
 name: notification-service
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 authentication:
 type: scram-sha-512
 password:
 valueFrom:
 secretKeyRef:
 name: notification-service-password
 key: password
 authorization:
 type: simple
 acls:
 # Legge da order-events
 - resource:
 type: topic
 name: order-events
 patternType: literal
 operations:
 - Read
 - Describe
 host: "*"
 # Scrive su user-notifications
 - resource:
 type: topic
 name: user-notifications
 patternType: literal
 operations:
 - Write
 - Describe
 host: "*"
 # Scrive su email-events
 - resource:
 type: topic
 name: email-events
 patternType: literal
 operations:
 - Write
 - Describe
 host: "*"
 # Consumer group
 - resource:
 type: group
 name: notification-service-group
 patternType: literal
 operations:
 - Read
 host: "*"
EOF

kubectl apply -f ./esercizi/notification-service.yaml
```

## Step 10.3: Crea utente email-sender
```bash
cat << 'EOF' > ./esercizi/email-sender.yaml
apiVersion: v1
kind: Secret
metadata:
 name: email-sender-password
 namespace: kafka-lab
type: Opaque
stringData:
 password: "EmailSender2026!"
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
 name: email-sender
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 authentication:
 type: scram-sha-512
 password:
 valueFrom:
 secretKeyRef:
 name: email-sender-password
 key: password
 authorization:
 type: simple
 acls:
 - resource:
 type: topic
 name: email-events
 patternType: literal
 operations:
 - Read
 - Describe
 host: "*"
 - resource:
 type: group
 name: email-sender-group
 patternType: literal
 operations:
 - Read
 host: "*"
EOF

kubectl apply -f ./esercizi/email-sender.yaml
```

## Step 10.4: Verifica tutto
```bash
# Verifica topic
kubectl get kafkatopic -n kafka-lab

# Verifica utenti
kubectl get kafkauser -n kafka-lab

# Verifica in Kafka UI
# http://localhost:30080
```

## Step 10.5: Test del flusso completo
```bash
# Entra nel pod
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Produci come notification-service su user-notifications
cat << 'EOF' > ./esercizi/notif.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="notification-service" password="NotificationService2026!";
EOF

echo '{"userId":"USER-001","message":"Il tuo ordine è stato spedito!"}' | \
/opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic user-notifications \
 --producer.config ./esercizi/notif.properties

# Esci
exit
```

## Checklist Esercizio 10
- [ ] Topic user-notifications creato (3 partizioni, 3 giorni)
- [ ] Topic email-events creato (6 partizioni, 30 giorni)
- [ ] Utente notification-service con ACL corrette
- [ ] Utente email-sender con ACL corrette
- [ ] Test messaggio funzionante
- [ ] Tutto visibile in Kafka UI

---

# CHECKLIST DAILY OPERATIONS

```
 MORNING CHECK (ogni mattina)
 kubectl get kafka -n kafka-lab
 kubectl get pods -n kafka-lab
 Grafana dashboard check
 Kafka UI - verifica broker online

 VERIFICHE PERIODICHE (settimanali)
 Consumer lag < threshold
 Disk usage < 80%
 Under-replicated partitions = 0
 Backup configurazioni

 INCIDENT RESPONSE (quando qualcosa non va)
 kubectl logs <pod> -n kafka-lab
 kubectl describe pod <pod> -n kafka-lab
 kubectl get events -n kafka-lab --sort-by='.lastTimestamp'
 Grafana per metriche storiche

 CHANGE MANAGEMENT (quando devi fare modifiche)
 Ticket approvato
 YAML preparato e reviewed
 Applicato via AWX o kubectl
 Verificato in Kafka UI
 Documentato
```

---

# RIFERIMENTI RAPIDI

## URLs
| Servizio | URL | Credenziali |
|----------|-----|-------------|
| Kafka UI | http://localhost:30080 | - |
| Grafana | http://localhost:30030 | admin/admin |
| Prometheus | http://localhost:30090 | - |
| AWX | http://localhost:30043 | admin/(vedi sotto) |

## Comandi Utili
```bash
# Password AWX
kubectl get secret awx-admin-password -n kafka-lab -o jsonpath="{.data.password}" | base64 -d; echo

# Stato cluster
kubectl get kafka -n kafka-lab

# Lista topic
kubectl get kafkatopic -n kafka-lab

# Lista utenti
kubectl get kafkauser -n kafka-lab

# Log di un pod
kubectl logs -f kafka-cluster-kafka-0 -n kafka-lab

# Eventi recenti
kubectl get events -n kafka-lab --sort-by='.lastTimestamp' | tail -20

# Entrare in un pod Kafka
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash
```

## Retention Time (millisecondi)
| Tempo | Millisecondi |
|-------|--------------|
| 1 giorno | 86400000 |
| 3 giorni | 259200000 |
| 7 giorni | 604800000 |
| 30 giorni | 2592000000 |
| 90 giorni | 7776000000 |

---

# COMPLETATO!

Hai imparato:
1. Health check del cluster
2. Creare topic con partizioni e retention
3. Creare utenti producer con ACL
4. Creare utenti consumer con ACL
5. Testare producer/consumer
6. Gestire failure e self-healing
7. Configurare AWX per automazione
8. Monitoring con Prometheus/Grafana
9. Backup configurazioni
10. Gestire scenari reali completi

**Prossimi passi:**
- Prova a "rompere" cose e ripararle
- Aggiungi più microservizi
- Configura alert in Grafana
- Prova scenari di disaster recovery
