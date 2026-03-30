# CORSO COMPLETO KAFKA SYSADMIN
## 60 Esercizi Pratici - Kubernetes e VM/Bare Metal

---

# INDICE RAPIDO

| # | Esercizio | Difficoltà | Ambiente |
|---|-----------|------------|----------|
| 1-10 | Fondamenti | - | Kubernetes |
| 11-20 | Troubleshooting K8s | | Kubernetes |
| 21-35 | VM/Bare Metal | - | VM Linux |
| 36-50 | Problemi Reali | - | Entrambi |
| 51-60 | Produzione | | Entrambi |

---

# 
# SEZIONE 1: FONDAMENTI (Esercizi 1-10)
# 

## ESERCIZIO 1: Connessione al Cluster
**Difficoltà: | Tempo: 10 min**

### Obiettivo
Connettersi al cluster Kafka e verificare che funzioni.

### Comandi
```bash
# 1. Entra nel pod Kafka
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# 2. Crea file di autenticazione
cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# 3. Lista i topic
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --list \
 --command-config /tmp/admin.properties

# 4. Verifica i broker attivi
/opt/kafka/bin/kafka-broker-api-versions.sh \
 --bootstrap-server localhost:9092 \
 --command-config /tmp/admin.properties | grep "id:"
```

### Risultato Atteso
- Vedi lista topic (almeno `__consumer_offsets`)
- Vedi 3 broker: id: 0, id: 1, id: 2

---

## ESERCIZIO 2: Creare un Topic
**Difficoltà: | Tempo: 10 min**

### Obiettivo
Creare topic con diverse configurazioni.

### Comandi
```bash
# Nel pod Kafka (con /tmp/admin.properties già creato)

# Crea topic semplice
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic test-topic \
 --partitions 3 \
 --replication-factor 3 \
 --command-config /tmp/admin.properties

# Crea topic con configurazioni custom
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic orders-events \
 --partitions 6 \
 --replication-factor 3 \
 --config retention.ms=604800000 \
 --config min.insync.replicas=2 \
 --command-config /tmp/admin.properties

# Verifica
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --topic orders-events \
 --command-config /tmp/admin.properties
```

### Come Leggere l'Output
```
Topic: orders-events Partition: 0 Leader: 2 Replicas: 2,0,1 Isr: 2,0,1
 ↑ ↑ ↑
 | | Repliche sincronizzate
 | Copie su broker 2,0,1
 Broker 2 gestisce read/write
```

---

## ESERCIZIO 3: Producer e Consumer
**Difficoltà: | Tempo: 15 min**

### Obiettivo
Produrre e consumare messaggi.

### Comandi

**Terminale 1 - Consumer:**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --from-beginning \
 --property print.key=true \
 --property print.partition=true \
 --consumer.config /tmp/admin.properties
```

**Terminale 2 - Producer:**
```bash
kubectl exec -it kafka-cluster-kafka-1 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Producer senza key
/opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --producer.config /tmp/admin.properties

# Scrivi: messaggio1, messaggio2, messaggio3 (poi CTRL+C)

# Producer CON key (formato key:value)
/opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --property "parse.key=true" \
 --property "key.separator=:" \
 --producer.config /tmp/admin.properties

# Scrivi: user1:ordine1, user1:ordine2, user2:ordine1
```

### Cosa Osservare
- Senza key: messaggi su partizioni diverse (round-robin)
- Con key: stessa key = stessa partizione (ordinamento garantito)

---

## ESERCIZIO 4: Consumer Groups
**Difficoltà: | Tempo: 20 min**

### Obiettivo
Capire come funzionano i consumer group.

### Comandi
```bash
# Terminale 1 - Consumer 1
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --group my-group \
 --consumer.config /tmp/admin.properties

# Terminale 2 - Consumer 2 (STESSO gruppo)
kubectl exec -it kafka-cluster-kafka-1 -n kafka-lab -- \
 /opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --group my-group \
 --consumer.config /tmp/admin.properties

# Terminale 3 - Vedi distribuzione partizioni
kubectl exec -it kafka-cluster-kafka-2 -n kafka-lab -- \
 /opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group my-group \
 --command-config /tmp/admin.properties
```

### Cosa Osservare
- Con 1 consumer: ha tutte le partizioni
- Con 2 consumer: partizioni divise (es. 0,1,2 e 3,4,5)
- Regola: max consumer = num partizioni

---

## ESERCIZIO 5: Monitorare Consumer Lag
**Difficoltà: | Tempo: 15 min**

### Obiettivo
Capire e monitorare il lag dei consumer.

### Comandi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Setup
cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Produci 100 messaggi
for i in $(seq 1 100); do
 echo "msg-$i" | /opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --producer.config /tmp/admin.properties 2>/dev/null
done

# Consuma solo 20
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic test-topic \
 --group lag-test \
 --max-messages 20 \
 --consumer.config /tmp/admin.properties

# Vedi il LAG
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group lag-test \
 --command-config /tmp/admin.properties
```

### Come Leggere
```
GROUP TOPIC PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG
lag-test test-topic 0 7 35 28
 ↑ ↑ ↑
 Letto fino a 7 Ultimo msg: 35 28 da processare!
```

---

## ESERCIZIO 6: Creare Topic via Strimzi YAML
**Difficoltà: | Tempo: 10 min**

### Obiettivo
Creare topic usando il metodo GitOps.

### Comandi
```bash
# Crea file YAML
cat << 'EOF' > /tmp/payment-topic.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
 name: payment-events
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 partitions: 6
 replicas: 3
 config:
 retention.ms: "604800000"
 min.insync.replicas: "2"
EOF

# Applica
kubectl apply -f /tmp/payment-topic.yaml

# Verifica
kubectl get kafkatopic payment-events -n kafka-lab
```

### Vantaggio
- Versionabile in Git
- Riproducibile
- GitOps ready

---

## ESERCIZIO 7: Creare Utenti con ACL
**Difficoltà: | Tempo: 20 min**

### Obiettivo
Creare utenti con permessi specifici.

### Comandi
```bash
# Utente PRODUCER (solo write)
cat << 'EOF' > /tmp/producer-user.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
 name: app-producer
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 authentication:
 type: scram-sha-512
 authorization:
 type: simple
 acls:
 - resource:
 type: topic
 name: "orders-"
 patternType: prefix
 operations: [Write, Describe, Create]
EOF

kubectl apply -f /tmp/producer-user.yaml

# Utente CONSUMER (solo read)
cat << 'EOF' > /tmp/consumer-user.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
 name: app-consumer
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 authentication:
 type: scram-sha-512
 authorization:
 type: simple
 acls:
 - resource:
 type: topic
 name: "orders-"
 patternType: prefix
 operations: [Read, Describe]
 - resource:
 type: group
 name: "orders-"
 patternType: prefix
 operations: [Read]
EOF

kubectl apply -f /tmp/consumer-user.yaml

# Ottieni password
kubectl get secret app-producer -n kafka-lab -o jsonpath='{.data.password}' | base64 -d
```

---

## ESERCIZIO 8: Reset Offset di un Consumer Group
**Difficoltà: | Tempo: 15 min**

### Obiettivo
Riprocessare messaggi resettando gli offset.

### IMPORTANTE: Il gruppo deve essere FERMO!

### Comandi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Verifica che il gruppo sia fermo
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group lag-test \
 --state \
 --command-config /tmp/admin.properties
# Deve mostrare: State: Empty

# RESET ALL'INIZIO (dry-run prima!)
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --group lag-test \
 --topic test-topic \
 --reset-offsets \
 --to-earliest \
 --dry-run \
 --command-config /tmp/admin.properties

# Esegui per davvero
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --group lag-test \
 --topic test-topic \
 --reset-offsets \
 --to-earliest \
 --execute \
 --command-config /tmp/admin.properties

# ALTRE OPZIONI:
# --to-latest → Vai alla fine (salta tutto)
# --to-datetime → Vai a una data specifica
# --shift-by -100 → Indietro di 100 messaggi
```

---

## ESERCIZIO 9: Modificare Configurazione Topic
**Difficoltà: | Tempo: 10 min**

### Obiettivo
Modificare retention, partizioni, etc.

### Comandi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Vedi config attuale
/opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name test-topic \
 --describe \
 --command-config /tmp/admin.properties

# Modifica retention (1 giorno)
/opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name test-topic \
 --alter \
 --add-config retention.ms=86400000 \
 --command-config /tmp/admin.properties

# Aumenta partizioni (DA 3 A 6) - solo aumento, mai diminuzione!
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --alter \
 --topic test-topic \
 --partitions 6 \
 --command-config /tmp/admin.properties
```

---

## ESERCIZIO 10: Eliminare un Topic
**Difficoltà: | Tempo: 5 min**

### IRREVERSIBILE!

### Comandi
```bash
# Via CLI
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --delete \
 --topic test-topic \
 --command-config /tmp/admin.properties

# Via Strimzi
kubectl delete kafkatopic payment-events -n kafka-lab
```

---

# 
# SEZIONE 2: TROUBLESHOOTING KUBERNETES (Esercizi 11-20)
# 

## ESERCIZIO 11: Pod in CrashLoopBackOff
**Difficoltà: | Tempo: 20 min**

### Scenario
Il pod kafka-cluster-kafka-2 non parte.

### Diagnosi
```bash
# Stato pod
kubectl get pods -n kafka-lab -l strimzi.io/cluster=kafka-cluster

# Dettagli (cerca Events in fondo)
kubectl describe pod kafka-cluster-kafka-2 -n kafka-lab

# Log attuale
kubectl logs kafka-cluster-kafka-2 -n kafka-lab --tail=50

# Log del CRASH PRECEDENTE (molto utile!)
kubectl logs kafka-cluster-kafka-2 -n kafka-lab --previous --tail=100

# Log Strimzi Operator
kubectl logs -n kafka-lab deployment/strimzi-cluster-operator --tail=100 | grep -i error
```

### Problemi Comuni

| Errore | Causa | Soluzione |
|--------|-------|-----------|
| `Insufficient memory` | Risorse insufficienti | Riduci requests o aggiungi nodi |
| `FailedMount` | PVC non si monta | Verifica StorageClass |
| `replication factor larger than brokers` | Config sbagliata | Aspetta altri broker o riduci RF |
| `cluster.id mismatch` | Storage corrotto | Elimina PVC (PERDI DATI!) |

---

## ESERCIZIO 12: Under-Replicated Partitions
**Difficoltà: | Tempo: 15 min**

### Scenario
Alcune partizioni non sono completamente replicate.

### Diagnosi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Trova partizioni problematiche
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --under-replicated-partitions \
 --command-config /tmp/admin.properties

# Output vuoto = OK
# Se vedi output = PROBLEMA!
```

### Come Leggere
```
Topic: orders Partition: 2 Replicas: 0,1,2 Isr: 0,1
 ↑
 Manca broker 2!
```

### Soluzioni
1. Verifica che tutti i broker siano Running
2. Controlla log del broker mancante
3. Verifica connettività di rete
4. Aspetta che si sincronizzi (può richiedere tempo)

---

## ESERCIZIO 13: Rolling Restart Sicuro
**Difficoltà: | Tempo: 20 min**

### Obiettivo
Riavviare i broker senza downtime.

### Pre-check (OBBLIGATORIO!)
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# 1. Nessuna partizione under-replicated
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --under-replicated-partitions \
 --command-config /tmp/admin.properties
# DEVE essere vuoto!

# 2. Nessuna partizione offline
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --unavailable-partitions \
 --command-config /tmp/admin.properties
# DEVE essere vuoto!
```

### Trigger Restart
```bash
# Esci dal pod
exit

# Metodo Strimzi
kubectl annotate kafka kafka-cluster -n kafka-lab \
 strimzi.io/manual-rolling-update=true --overwrite

# Monitora
kubectl get pods -n kafka-lab -l strimzi.io/cluster=kafka-cluster -w
```

---

## ESERCIZIO 14: Scaling - Aggiungere Broker
**Difficoltà: | Tempo: 30 min**

### Obiettivo
Scalare da 3 a 5 broker.

### Comandi
```bash
# Scala KafkaNodePool
kubectl patch kafkanodepool kafka -n kafka-lab \
 --type merge -p '{"spec":{"replicas": 5}}'

# Attendi
kubectl get pods -n kafka-lab -l strimzi.io/cluster=kafka-cluster -w

# Verifica nuovi broker
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-broker-api-versions.sh \
 --bootstrap-server localhost:9092 \
 --command-config /tmp/admin.properties | grep "id:"
```

### I nuovi broker sono VUOTI!
Devi riassegnare le partizioni manualmente con `kafka-reassign-partitions.sh`

---

## ESERCIZIO 15: Backup Configurazioni
**Difficoltà: | Tempo: 15 min**

### Comandi
```bash
mkdir -p /tmp/kafka-backup

# Backup Topic
kubectl get kafkatopic -n kafka-lab -o yaml > /tmp/kafka-backup/topics.yaml

# Backup User
kubectl get kafkauser -n kafka-lab -o yaml > /tmp/kafka-backup/users.yaml

# Backup Connector
kubectl get kafkaconnector -n kafka-lab -o yaml > /tmp/kafka-backup/connectors.yaml

# Backup Cluster
kubectl get kafka -n kafka-lab -o yaml > /tmp/kafka-backup/cluster.yaml

# Crea archivio
tar -czvf kafka-backup-$(date +%Y%m%d).tar.gz /tmp/kafka-backup/
```

### Restore
```bash
kubectl apply -f /tmp/kafka-backup/topics.yaml
kubectl apply -f /tmp/kafka-backup/users.yaml
```

---

## ESERCIZIO 16: Debug Kafka Connect
**Difficoltà: | Tempo: 20 min**

### Diagnosi
```bash
# Trova pod Connect
CONNECT_POD=$(kubectl get pods -n kafka-lab -l strimzi.io/kind=KafkaConnect -o name | head -1)

# Entra nel pod
kubectl exec -it $CONNECT_POD -n kafka-lab -- bash

# Lista connectors
curl -s localhost:8083/connectors | jq

# Status di un connector
curl -s localhost:8083/connectors/my-connector/status | jq

# Restart connector
curl -X POST localhost:8083/connectors/my-connector/restart

# Restart singolo task
curl -X POST localhost:8083/connectors/my-connector/tasks/0/restart
```

---

## ESERCIZIO 17: Performance Test
**Difficoltà: | Tempo: 15 min**

### Comandi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Crea topic per test
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic perf-test \
 --partitions 6 \
 --replication-factor 3 \
 --command-config /tmp/admin.properties

# Producer test: 100K messaggi, 1KB ciascuno
/opt/kafka/bin/kafka-producer-perf-test.sh \
 --topic perf-test \
 --num-records 100000 \
 --record-size 1000 \
 --throughput -1 \
 --producer.config /tmp/admin.properties \
 --producer-props bootstrap.servers=localhost:9092

# Consumer test
/opt/kafka/bin/kafka-consumer-perf-test.sh \
 --bootstrap-server localhost:9092 \
 --topic perf-test \
 --messages 100000 \
 --consumer.config /tmp/admin.properties
```

### Risultati Tipici
- Producer: 40-80K msg/sec
- Consumer: 50-100K msg/sec
- Dipende da risorse, rete, disco

---

## ESERCIZIO 18: Verificare lo Spazio Disco
**Difficoltà: | Tempo: 10 min**

### Comandi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Spazio totale
df -h /var/lib/kafka

# Spazio per topic
/opt/kafka/bin/kafka-log-dirs.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --command-config /tmp/admin.properties 2>/dev/null | head -50

# Se il disco si sta riempiendo: riduci retention
/opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name big-topic \
 --alter \
 --add-config retention.ms=86400000 \
 --command-config /tmp/admin.properties
```

---

## ESERCIZIO 19: Leader Election
**Difficoltà: | Tempo: 10 min**

### Scenario
Dopo un restart, i leader sono sbilanciati.

### Comandi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Vedi distribuzione leader attuale
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --command-config /tmp/admin.properties | grep "Leader:" | awk '{print $4}' | sort | uniq -c

# Forza preferred leader election
/opt/kafka/bin/kafka-leader-election.sh \
 --bootstrap-server localhost:9092 \
 --election-type preferred \
 --all-topic-partitions \
 --admin.config /tmp/admin.properties

# Verifica
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --command-config /tmp/admin.properties | grep "Leader:" | awk '{print $4}' | sort | uniq -c
```

---

## ESERCIZIO 20: Monitoraggio con Prometheus/Grafana
**Difficoltà: | Tempo: 15 min**

### Comandi
```bash
# Verifica che Prometheus sia attivo
kubectl get pods -n kafka-lab -l app=prometheus

# Port-forward Prometheus
kubectl port-forward -n kafka-lab svc/prometheus 9090:9090 &

# Apri http://localhost:9090

# Query utili:
# - kafka_server_replicamanager_underreplicatedpartitions
# - kafka_controller_kafkacontroller_offlinepartitionscount
# - kafka_server_brokertopicmetrics_messagesinpersec

# Grafana
kubectl port-forward -n kafka-lab svc/grafana 3000:3000 &
# http://localhost:3000 (admin/admin)
```

---

# 
# SEZIONE 3: VM/BARE METAL (Esercizi 21-35)
# 

## ESERCIZIO 21: Installazione Kafka su VM
**Difficoltà: | Tempo: 30 min**

### Prerequisiti
- VM con CentOS/RHEL/Ubuntu
- Java 17+
- 3 VM per cluster

### Comandi (su OGNI nodo)
```bash
# Installa Java
sudo yum install -y java-17-openjdk # RHEL/CentOS
# oppure
sudo apt install -y openjdk-17-jdk # Ubuntu

# Crea utente
sudo useradd -r -s /sbin/nologin kafka

# Scarica Kafka
cd /tmp
wget https://downloads.apache.org/kafka/3.9.0/kafka_2.13-3.9.0.tgz
sudo tar -xzf kafka_2.13-3.9.0.tgz -C /opt
sudo mv /opt/kafka_2.13-3.9.0 /opt/kafka

# Crea directory
sudo mkdir -p /var/lib/kafka/data
sudo mkdir -p /var/log/kafka
sudo chown -R kafka:kafka /opt/kafka /var/lib/kafka /var/log/kafka
```

---

## ESERCIZIO 22: Configurazione KRaft (Nodo 1)
**Difficoltà: | Tempo: 20 min**

### Comandi
```bash
# Genera cluster ID (SOLO su un nodo, poi usalo su tutti!)
KAFKA_CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
echo "CLUSTER_ID=$KAFKA_CLUSTER_ID" # SALVALO!

# Configura server.properties per Nodo 1
sudo tee /opt/kafka/config/kraft/server.properties << 'EOF'
# Nodo 1
node.id=1
process.roles=controller,broker

listeners=PLAINTEXT://:9092,CONTROLLER://:9093
advertised.listeners=PLAINTEXT://kafka-node-1:9092
controller.listener.names=CONTROLLER

# Tutti i controller del cluster
controller.quorum.voters=1@kafka-node-1:9093,2@kafka-node-2:9093,3@kafka-node-3:9093

log.dirs=/var/lib/kafka/data
num.partitions=3
default.replication.factor=3
min.insync.replicas=2

# Performance
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
EOF

# Formatta storage
sudo -u kafka /opt/kafka/bin/kafka-storage.sh format \
 -t $KAFKA_CLUSTER_ID \
 -c /opt/kafka/config/kraft/server.properties
```

---

## ESERCIZIO 23: Configurazione KRaft (Nodi 2 e 3)
**Difficoltà: | Tempo: 15 min**

### Comandi
```bash
# Nodo 2 - cambia node.id e advertised.listeners
sudo tee /opt/kafka/config/kraft/server.properties << 'EOF'
node.id=2
process.roles=controller,broker
listeners=PLAINTEXT://:9092,CONTROLLER://:9093
advertised.listeners=PLAINTEXT://kafka-node-2:9092
controller.listener.names=CONTROLLER
controller.quorum.voters=1@kafka-node-1:9093,2@kafka-node-2:9093,3@kafka-node-3:9093
log.dirs=/var/lib/kafka/data
EOF

# USA LO STESSO CLUSTER_ID!
sudo -u kafka /opt/kafka/bin/kafka-storage.sh format \
 -t $KAFKA_CLUSTER_ID \
 -c /opt/kafka/config/kraft/server.properties

# Ripeti per Nodo 3 con node.id=3 e kafka-node-3
```

---

## ESERCIZIO 24: Systemd Service
**Difficoltà: | Tempo: 15 min**

### Comandi
```bash
# Crea service file
sudo tee /etc/systemd/system/kafka.service << 'EOF'
[Unit]
Description=Apache Kafka
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=10

# Limiti
LimitNOFILE=100000
LimitNPROC=32768

# Environment
Environment="KAFKA_HEAP_OPTS=-Xms1g -Xmx1g"
Environment="KAFKA_JVM_PERFORMANCE_OPTS=-XX:+UseG1GC -XX:MaxGCPauseMillis=20"

[Install]
WantedBy=multi-user.target
EOF

# Abilita e avvia
sudo systemctl daemon-reload
sudo systemctl enable kafka
sudo systemctl start kafka
sudo systemctl status kafka

# Log
sudo journalctl -u kafka -f
```

---

## ESERCIZIO 25: Verifica Cluster VM
**Difficoltà: | Tempo: 10 min**

### Comandi
```bash
# Da qualsiasi nodo
/opt/kafka/bin/kafka-broker-api-versions.sh \
 --bootstrap-server kafka-node-1:9092,kafka-node-2:9092,kafka-node-3:9092 | grep "id:"

# Crea topic di test
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server kafka-node-1:9092 \
 --create \
 --topic test \
 --partitions 6 \
 --replication-factor 3

# Verifica
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server kafka-node-1:9092 \
 --describe \
 --topic test
```

---

## ESERCIZIO 26: Configurazione SASL su VM
**Difficoltà: | Tempo: 30 min**

### Comandi
```bash
# Crea file JAAS per il broker
sudo tee /opt/kafka/config/kafka_server_jaas.conf << 'EOF'
KafkaServer {
 org.apache.kafka.common.security.scram.ScramLoginModule required
 username="admin"
 password="admin-secret";
};
EOF

# Modifica server.properties
sudo tee -a /opt/kafka/config/kraft/server.properties << 'EOF'

# SASL Configuration
listeners=SASL_PLAINTEXT://:9092,CONTROLLER://:9093
advertised.listeners=SASL_PLAINTEXT://kafka-node-1:9092
sasl.enabled.mechanisms=SCRAM-SHA-512
sasl.mechanism.inter.broker.protocol=SCRAM-SHA-512
security.inter.broker.protocol=SASL_PLAINTEXT
EOF

# Aggiungi JAAS al startup
# In /etc/systemd/system/kafka.service aggiungi:
# Environment="KAFKA_OPTS=-Djava.security.auth.login.config=/opt/kafka/config/kafka_server_jaas.conf"

# Restart
sudo systemctl restart kafka

# Crea utente admin
/opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server kafka-node-1:9092 \
 --alter \
 --add-config 'SCRAM-SHA-512=[password=admin-secret]' \
 --entity-type users \
 --entity-name admin
```

---

## ESERCIZIO 27: Monitoraggio VM con JMX
**Difficoltà: | Tempo: 20 min**

### Comandi
```bash
# Abilita JMX nel service
# Aggiungi a /etc/systemd/system/kafka.service:
# Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"

sudo systemctl daemon-reload
sudo systemctl restart kafka

# Verifica JMX
netstat -tlnp | grep 9999

# Usa jconsole o VisualVM per connetterti a:
# kafka-node-1:9999
```

---

## ESERCIZIO 28: Log Rotation su VM
**Difficoltà: | Tempo: 10 min**

### Comandi
```bash
# Configura logrotate
sudo tee /etc/logrotate.d/kafka << 'EOF'
/var/log/kafka/*.log {
 daily
 rotate 7
 compress
 delaycompress
 missingok
 notifempty
 create 0644 kafka kafka
 postrotate
 systemctl reload kafka > /dev/null 2>&1 || true
 endscript
}
EOF

# Testa
sudo logrotate -d /etc/logrotate.d/kafka
```

---

## ESERCIZIO 29: Backup Dati su VM
**Difficoltà: | Tempo: 15 min**

### Comandi
```bash
# Script di backup
sudo tee /opt/kafka/scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=/backup/kafka/$(date +%Y%m%d)
mkdir -p $BACKUP_DIR

# Backup config
cp -r /opt/kafka/config $BACKUP_DIR/

# Backup metadata (NON i dati dei topic!)
cp -r /var/lib/kafka/data/__cluster_metadata-0 $BACKUP_DIR/

# Lista topic e config
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe > $BACKUP_DIR/topics.txt
/opt/kafka/bin/kafka-configs.sh --bootstrap-server localhost:9092 --entity-type topics --describe --all > $BACKUP_DIR/topic-configs.txt

echo "Backup completato: $BACKUP_DIR"
EOF

sudo chmod +x /opt/kafka/scripts/backup.sh

# Cron per backup giornaliero
echo "0 2 * * * /opt/kafka/scripts/backup.sh" | sudo crontab -
```

---

## ESERCIZIO 30: Rolling Restart su VM
**Difficoltà: | Tempo: 20 min**

### Comandi
```bash
# Script di rolling restart
sudo tee /opt/kafka/scripts/rolling-restart.sh << 'EOF'
#!/bin/bash
set -e

BROKERS="kafka-node-1 kafka-node-2 kafka-node-3"

for broker in $BROKERS; do
 echo "=== Checking $broker before restart ==="

 # Pre-check: no under-replicated
 URP=$(/opt/kafka/bin/kafka-topics.sh --bootstrap-server $broker:9092 --describe --under-replicated-partitions 2>/dev/null | wc -l)
 if [ $URP -gt 0 ]; then
 echo "ERROR: $URP under-replicated partitions! Aborting."
 exit 1
 fi

 echo "=== Restarting $broker ==="
 ssh $broker "sudo systemctl restart kafka"

 echo "=== Waiting for $broker to be ready ==="
 sleep 30

 # Verifica che sia tornato
 /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server $broker:9092 > /dev/null

 echo "=== $broker restarted successfully ==="
 echo ""
done

echo "Rolling restart completato!"
EOF

chmod +x /opt/kafka/scripts/rolling-restart.sh
```

---

## ESERCIZIO 31: Upgrade Kafka su VM
**Difficoltà: | Tempo: 45 min**

### Procedura
```bash
# 1. Scarica nuova versione
wget https://downloads.apache.org/kafka/3.9.0/kafka_2.13-3.9.0.tgz

# 2. Ferma broker
sudo systemctl stop kafka

# 3. Backup
sudo cp -r /opt/kafka /opt/kafka.backup

# 4. Estrai nuova versione
sudo tar -xzf kafka_2.13-3.9.0.tgz -C /opt
sudo mv /opt/kafka /opt/kafka.old
sudo mv /opt/kafka_2.13-3.9.0 /opt/kafka

# 5. Copia config
sudo cp /opt/kafka.old/config/kraft/server.properties /opt/kafka/config/kraft/

# 6. Fix permessi
sudo chown -R kafka:kafka /opt/kafka

# 7. Avvia
sudo systemctl start kafka

# 8. Verifica
/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# 9. Ripeti per ogni nodo (rolling upgrade)
```

---

## ESERCIZIO 32: Troubleshooting VM - Broker Non Parte
**Difficoltà: | Tempo: 20 min**

### Diagnosi
```bash
# Log systemd
sudo journalctl -u kafka --since "10 minutes ago"

# Log Kafka
sudo tail -100 /var/log/kafka/server.log

# Verifica processo
ps aux | grep kafka

# Verifica porte
netstat -tlnp | grep -E "9092|9093"

# Verifica disco
df -h /var/lib/kafka

# Verifica Java
java -version

# Verifica permessi
ls -la /var/lib/kafka/data
```

### Problemi Comuni VM

| Errore | Causa | Soluzione |
|--------|-------|-----------|
| `Address already in use` | Porta occupata | `kill` processo o cambia porta |
| `Permission denied` | Permessi errati | `chown -R kafka:kafka` |
| `No space left` | Disco pieno | Elimina log o aggiungi disco |
| `OutOfMemoryError` | RAM insufficiente | Aumenta heap o RAM |

---

## ESERCIZIO 33: Firewall e Sicurezza VM
**Difficoltà: | Tempo: 15 min**

### Comandi
```bash
# Apri porte necessarie
sudo firewall-cmd --permanent --add-port=9092/tcp # Client
sudo firewall-cmd --permanent --add-port=9093/tcp # Controller
sudo firewall-cmd --permanent --add-port=9999/tcp # JMX (opzionale)
sudo firewall-cmd --reload

# Verifica
sudo firewall-cmd --list-ports

# Limita accesso (solo dalla rete interna)
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port port="9092" protocol="tcp" accept'
```

---

## ESERCIZIO 34: Kafka Connect su VM
**Difficoltà: | Tempo: 25 min**

### Comandi
```bash
# Configura Connect
sudo tee /opt/kafka/config/connect-distributed.properties << 'EOF'
bootstrap.servers=kafka-node-1:9092,kafka-node-2:9092,kafka-node-3:9092
group.id=connect-cluster

key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter

offset.storage.topic=connect-offsets
offset.storage.replication.factor=3
config.storage.topic=connect-configs
config.storage.replication.factor=3
status.storage.topic=connect-status
status.storage.replication.factor=3

rest.port=8083
plugin.path=/opt/kafka/plugins
EOF

# Crea directory plugin
sudo mkdir -p /opt/kafka/plugins
sudo chown kafka:kafka /opt/kafka/plugins

# Avvia Connect
sudo -u kafka /opt/kafka/bin/connect-distributed.sh \
 /opt/kafka/config/connect-distributed.properties &

# Verifica
curl http://localhost:8083/connectors
```

---

## ESERCIZIO 35: MirrorMaker 2 su VM
**Difficoltà: | Tempo: 30 min**

### Obiettivo
Replica cross-datacenter.

### Comandi
```bash
# Configura MirrorMaker 2
sudo tee /opt/kafka/config/mm2.properties << 'EOF'
# Cluster aliases
clusters=source,target

source.bootstrap.servers=source-kafka:9092
target.bootstrap.servers=target-kafka:9092

# Replica da source a target
source->target.enabled=true
source->target.topics=.*

# Sync dei consumer group
source->target.sync.group.offsets.enabled=true

# Replication factor per topic interni
replication.factor=3
EOF

# Avvia
sudo -u kafka /opt/kafka/bin/connect-mirror-maker.sh \
 /opt/kafka/config/mm2.properties &
```

---

# 
# SEZIONE 4: PROBLEMI REALI E SOLUZIONI (Esercizi 36-50)
# 

## ESERCIZIO 36: PROBLEMA - Consumer Lag Cresce
**Difficoltà: | Tempo: 20 min**

### Scenario
Il lag continua ad aumentare, i messaggi si accumulano.

### Diagnosi
```bash
# Vedi lag
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group problematic-group \
 --command-config /tmp/admin.properties

# Monitora trend (esegui ogni 10 sec)
watch -n10 'kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group problematic-group \
 --command-config /tmp/admin.properties 2>/dev/null | grep -v "^$"'
```

### Soluzioni

| Causa | Diagnosi | Soluzione |
|-------|----------|-----------|
| Consumer lento | CPU/mem alta nel consumer | Scala consumer o ottimizza codice |
| Troppi messaggi | Producer rate > consumer rate | Aggiungi più consumer (max = partizioni) |
| Poche partizioni | Num consumer >= num partizioni | Aumenta partizioni |
| Processing bloccato | Consumer fermo | Verifica errori nel consumer app |

---

## ESERCIZIO 37: PROBLEMA - Producer Riceve Timeout
**Difficoltà: | Tempo: 15 min**

### Scenario
I producer ricevono `TimeoutException`.

### Diagnosi
```bash
# Verifica broker attivi
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-broker-api-versions.sh \
 --bootstrap-server localhost:9092 \
 --command-config /tmp/admin.properties

# Verifica under-replicated
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --under-replicated-partitions \
 --command-config /tmp/admin.properties

# Verifica risorse broker
kubectl top pods -n kafka-lab -l strimzi.io/cluster=kafka-cluster
```

### Soluzioni
- Broker sovraccarico → scala cluster
- Network issues → verifica connettività
- min.insync.replicas non soddisfatto → verifica ISR
- Disco lento → verifica I/O

---

## ESERCIZIO 38: PROBLEMA - Messaggio Perso
**Difficoltà: | Tempo: 25 min**

### Scenario
Un messaggio prodotto non viene consumato.

### Diagnosi
```bash
# Verifica che il messaggio sia stato scritto
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic problem-topic \
 --from-beginning \
 --property print.offset=true \
 --property print.partition=true \
 --consumer.config /tmp/admin.properties | head -100

# Verifica config acks del producer
# acks=0: può perdere messaggi
# acks=1: può perdere se leader muore prima di replicare
# acks=all: più sicuro
```

### Prevenzione
```bash
# Config producer per durabilità
acks=all
retries=3
enable.idempotence=true

# Config topic
min.insync.replicas=2
unclean.leader.election.enable=false
```

---

## ESERCIZIO 39: PROBLEMA - Rebalance Continui
**Difficoltà: | Tempo: 20 min**

### Scenario
I consumer fanno rebalance continuamente, causando pause.

### Diagnosi
```bash
# Log consumer (cerca "rebalance")
kubectl logs -n kafka-lab -l app=my-consumer --tail=500 | grep -i rebalance

# Verifica stato gruppo
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group problematic-group \
 --state \
 --command-config /tmp/admin.properties
```

### Cause e Soluzioni

| Causa | Soluzione |
|-------|-----------|
| session.timeout troppo basso | Aumenta a 30-45 secondi |
| max.poll.interval troppo basso | Aumenta (processing lento) |
| Consumer che crashano | Fix bug, aggiungi health check |
| Network instabile | Verifica connettività |

---

## ESERCIZIO 40: PROBLEMA - Disco Pieno
**Difficoltà: | Tempo: 15 min**

### Scenario
I broker si fermano per disco pieno.

### Diagnosi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- df -h /var/lib/kafka

# Trova topic più grandi
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-log-dirs.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --command-config /tmp/admin.properties 2>/dev/null | grep size | sort -t: -k2 -rn | head
```

### Soluzioni
```bash
# Riduci retention dei topic grandi
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name big-topic \
 --alter \
 --add-config retention.ms=86400000 \
 --command-config /tmp/admin.properties

# Elimina topic non necessari
kubectl delete kafkatopic old-topic -n kafka-lab

# Aumenta storage (K8s)
kubectl patch pvc data-kafka-cluster-kafka-0 -n kafka-lab \
 --type merge -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

---

## ESERCIZIO 41: PROBLEMA - Partizioni Offline
**Difficoltà: | Tempo: 20 min**

### Scenario
Alcune partizioni non sono accessibili.

### Diagnosi
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --unavailable-partitions \
 --command-config /tmp/admin.properties
```

### Soluzioni
1. Verifica che tutti i broker siano Running
2. Se un broker è down permanentemente, considera `unclean.leader.election.enable=true` (PERDI DATI!)
3. Ripristina il broker o riassegna partizioni

---

## ESERCIZIO 42: PROBLEMA - Certificati TLS Scaduti
**Difficoltà: | Tempo: 20 min**

### Scenario (K8s/Strimzi)
La comunicazione TLS fallisce.

### Diagnosi
```bash
# Verifica secret dei certificati
kubectl get secret kafka-cluster-cluster-ca-cert -n kafka-lab -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -text -noout | grep -A2 "Validity"

# Se scaduto, Strimzi li rigenera automaticamente
# Forza rolling restart per applicare nuovi cert
kubectl annotate kafka kafka-cluster -n kafka-lab \
 strimzi.io/manual-rolling-update=true --overwrite
```

---

## ESERCIZIO 43: PROBLEMA - ACL Troppo Restrittive
**Difficoltà: | Tempo: 15 min**

### Scenario
Un'applicazione riceve `TopicAuthorizationException`.

### Diagnosi
```bash
# Lista ACL per utente
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-acls.sh \
 --bootstrap-server localhost:9092 \
 --list \
 --principal User:app-producer \
 --command-config /tmp/admin.properties
```

### Soluzione
```bash
# Aggiungi permessi mancanti via KafkaUser
kubectl edit kafkauser app-producer -n kafka-lab
# Aggiungi le ACL necessarie
```

---

## ESERCIZIO 44: PROBLEMA - Connect Task in FAILED
**Difficoltà: | Tempo: 15 min**

### Diagnosi
```bash
CONNECT_POD=$(kubectl get pods -n kafka-lab -l strimzi.io/kind=KafkaConnect -o name | head -1)

# Status dettagliato
kubectl exec $CONNECT_POD -n kafka-lab -- \
 curl -s localhost:8083/connectors/my-connector/status | jq '.tasks[].trace'

# Risolvi il problema (es: crea file mancante)
kubectl exec $CONNECT_POD -n kafka-lab -- touch /tmp/input.txt

# Restart task
kubectl exec $CONNECT_POD -n kafka-lab -- \
 curl -X POST localhost:8083/connectors/my-connector/tasks/0/restart
```

---

## ESERCIZIO 45: PROBLEMA - Duplicati nei Messaggi
**Difficoltà: | Tempo: 20 min**

### Causa
Producer senza idempotenza + retry.

### Soluzione
```properties
# Producer config
enable.idempotence=true
acks=all
retries=3

# Per exactly-once semantics
transactional.id=my-transactional-producer
```

### Consumer deve essere idempotente
```java
// Pseudo-codice
if (alreadyProcessed(message.id)) {
 skip();
} else {
 process(message);
 markAsProcessed(message.id);
}
```

---

## ESERCIZIO 46: PROBLEMA - Network Partition
**Difficoltà: | Tempo: 25 min**

### Scenario
Alcuni broker non comunicano tra loro.

### Diagnosi
```bash
# Verifica connettività tra broker
kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- \
 nc -zv kafka-cluster-kafka-1.kafka-cluster-kafka-brokers 9092

kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- \
 nc -zv kafka-cluster-kafka-2.kafka-cluster-kafka-brokers 9092
```

### Soluzioni
- Verifica Network Policy
- Verifica DNS
- Verifica CNI plugin

---

## ESERCIZIO 47: PROBLEMA - JVM Out of Memory
**Difficoltà: | Tempo: 15 min**

### Diagnosi (VM)
```bash
# Verifica heap
jcmd $(pgrep -f kafka) VM.flags | grep -i heap

# GC stats
jstat -gc $(pgrep -f kafka) 1000 5
```

### Soluzione
```bash
# Aumenta heap in KAFKA_HEAP_OPTS
# Da: -Xmx1g
# A: -Xmx4g

# In K8s, modifica resources:
kubectl edit kafka kafka-cluster -n kafka-lab
# spec.kafka.jvmOptions.-Xmx: "4g"
```

---

## ESERCIZIO 48: PROBLEMA - Slow Broker
**Difficoltà: | Tempo: 20 min**

### Scenario
Un broker è molto più lento degli altri.

### Diagnosi
```bash
# Confronta latenza
kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-producer-perf-test.sh \
 --topic perf-test \
 --num-records 10000 \
 --record-size 1000 \
 --throughput -1 \
 --producer-props bootstrap.servers=kafka-cluster-kafka-0:9092

# Ripeti per kafka-1 e kafka-2, confronta risultati

# Verifica disco
kubectl exec kafka-cluster-kafka-X -n kafka-lab -- iostat -x 1 5
```

### Soluzioni
- Disco lento → migra a SSD
- CPU throttling → aumenta limits
- Network → verifica node placement

---

## ESERCIZIO 49: PROBLEMA - Consumer Bloccato
**Difficoltà: | Tempo: 15 min**

### Scenario
Un consumer smette di processare senza errori.

### Diagnosi
```bash
# Thread dump dell'applicazione consumer
jstack $(pgrep -f consumer-app)

# Verifica se sta facendo poll
# Cerca "Waiting" su I/O o lock
```

### Cause Comuni
- Deadlock nel codice
- Chiamata bloccante a servizio esterno
- Processing troppo lento (max.poll.interval.ms superato)

---

## ESERCIZIO 50: PROBLEMA - Message Too Large
**Difficoltà: | Tempo: 10 min**

### Scenario
Producer riceve `RecordTooLargeException`.

### Soluzione
```bash
# Aumenta max message size sul TOPIC
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name big-messages-topic \
 --alter \
 --add-config max.message.bytes=10485760 \
 --command-config /tmp/admin.properties

# Configura anche BROKER
# message.max.bytes=10485760

# E il PRODUCER
# max.request.size=10485760
```

---

# 
# SEZIONE 5: PRODUZIONE E BEST PRACTICES (Esercizi 51-60)
# 

## ESERCIZIO 51: Checklist Pre-Produzione
**Difficoltà: | Tempo: 30 min**

### Lista Controlli
```bash
# 1. CLUSTER HEALTH
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash -c '
echo "=== BROKER COUNT ==="
/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 --command-config /tmp/admin.properties 2>/dev/null | grep -c "id:"

echo "=== UNDER-REPLICATED ==="
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-replicated-partitions --command-config /tmp/admin.properties

echo "=== OFFLINE PARTITIONS ==="
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --unavailable-partitions --command-config /tmp/admin.properties
'

# 2. TOPIC CONFIG CHECK
# Tutti i topic critici hanno:
# - replication.factor >= 3
# - min.insync.replicas >= 2
# - retention adeguata

# 3. MONITORING
# - Prometheus scraping attivo
# - Alert configurati
# - Dashboard Grafana funzionante

# 4. BACKUP
# - Backup config automatici
# - Procedura DR documentata

# 5. SECURITY
# - TLS abilitato
# - Autenticazione attiva
# - ACL configurate
```

---

## ESERCIZIO 52: Capacity Planning
**Difficoltà: | Tempo: 20 min**

### Calcoli
```
THROUGHPUT RICHIESTO: 100 MB/s

FORMULA BROKER:

Throughput per broker ≈ 50-100 MB/s (dipende da disco)
Brokers necessari = (Throughput richiesto × Replication Factor) / Throughput per broker

Esempio:
100 MB/s × 3 RF = 300 MB/s totali
300 MB/s / 75 MB/s per broker = 4 broker (minimo)
Raccomandato: 5-6 broker per headroom

FORMULA PARTIZIONI:

Una partizione = ~10 MB/s (conservativo)
Partizioni per topic = Throughput topic / 10 MB/s

Esempio:
50 MB/s per topic / 10 = 5 partizioni (minimo)
Raccomandato: 10-20 partizioni per crescita futura

FORMULA STORAGE:

Storage = Throughput × Retention × Replication Factor × 1.2 (overhead)

Esempio:
100 MB/s × 86400 sec (1 giorno) × 3 RF × 1.2 = ~31 TB
Per 7 giorni: ~217 TB
```

---

## ESERCIZIO 53: High Availability Setup
**Difficoltà: | Tempo: 25 min**

### Configurazioni Critiche
```yaml
# Kafka Cluster (values.yaml)
kafka:
 replicas: 5 # Dispari per quorum KRaft
 config:
 default.replication.factor: 3
 min.insync.replicas: 2
 unclean.leader.election.enable: false # MAI true in prod!
 auto.leader.rebalance.enable: true

# Anti-affinity per distribuire broker su nodi diversi
# In Strimzi:
spec:
 kafka:
 template:
 pod:
 affinity:
 podAntiAffinity:
 requiredDuringSchedulingIgnoredDuringExecution:
 - labelSelector:
 matchLabels:
 strimzi.io/cluster: kafka-cluster
 topologyKey: kubernetes.io/hostname
```

---

## ESERCIZIO 54: Monitoring Alert Rules
**Difficoltà: | Tempo: 20 min**

### Alert Prometheus
```yaml
groups:
 - name: kafka-alerts
 rules:
 # Under-replicated partitions
 - alert: KafkaUnderReplicatedPartitions
 expr: kafka_server_replicamanager_underreplicatedpartitions > 0
 for: 5m
 labels:
 severity: critical
 annotations:
 summary: "Kafka has under-replicated partitions"

 # Offline partitions
 - alert: KafkaOfflinePartitions
 expr: kafka_controller_kafkacontroller_offlinepartitionscount > 0
 for: 1m
 labels:
 severity: critical
 annotations:
 summary: "Kafka has offline partitions!"

 # Consumer lag
 - alert: KafkaConsumerLagHigh
 expr: kafka_consumergroup_lag > 10000
 for: 10m
 labels:
 severity: warning
 annotations:
 summary: "Consumer group {{ $labels.consumergroup }} has high lag"

 # Broker down
 - alert: KafkaBrokerDown
 expr: kafka_server_kafkaserver_brokerstate != 3
 for: 2m
 labels:
 severity: critical
 annotations:
 summary: "Kafka broker {{ $labels.instance }} is down"
```

---

## ESERCIZIO 55: Disaster Recovery Plan
**Difficoltà: | Tempo: 30 min**

### Procedura DR
```
SCENARIO: Cluster completamente perso

STEP 1: Ripristina Infrastruttura

 Cluster K8s funzionante
 Storage disponibile
 Network configurato

STEP 2: Reinstalla Strimzi

helm install strimzi strimzi/strimzi-kafka-operator -n kafka-lab

STEP 3: Ripristina Cluster Kafka

kubectl apply -f backup/kafka-cluster.yaml
# Attendi che tutti i broker siano Running

STEP 4: Ripristina Topic

kubectl apply -f backup/kafkatopics.yaml
# I topic sono VUOTI (nessun dato)

STEP 5: Ripristina User

kubectl apply -f backup/kafkausers.yaml
# Le password sono NUOVE! Aggiorna le applicazioni

STEP 6: Ripristina Connect e Connector

kubectl apply -f backup/kafkaconnect.yaml
kubectl apply -f backup/kafkaconnectors.yaml

STEP 7: Verifica

 Tutti i pod Running
 Topic esistono
 Applicazioni si connettono

 NOTA: I DATI nei topic sono PERSI!
Per evitare: usa MirrorMaker2 per replica cross-region
```

---

## ESERCIZIO 56: Security Hardening
**Difficoltà: | Tempo: 25 min**

### Checklist Sicurezza
```
AUTENTICAZIONE:
 SASL/SCRAM o mTLS abilitato
 Password forti (non default!)
 Rotazione periodica credenziali

AUTORIZZAZIONE:
 ACL per ogni applicazione
 Principio least privilege
 No user admin per applicazioni

ENCRYPTION:
 TLS per dati in transito
 Encryption at rest (se richiesto)

NETWORK:
 Broker non esposti pubblicamente
 Network Policy in K8s
 Firewall rules su VM

AUDIT:
 Logging abilitato
 Audit log per operazioni admin
 Monitoring accessi
```

---

## ESERCIZIO 57: Performance Tuning
**Difficoltà: | Tempo: 25 min**

### Tuning Producer
```properties
# Aumenta batch size
batch.size=65536
linger.ms=10

# Compressione
compression.type=lz4

# Acknowledgment (tradeoff: durabilità vs velocità)
acks=all # Più sicuro
# acks=1 # Più veloce

# Buffer memory
buffer.memory=67108864
```

### Tuning Consumer
```properties
# Fetch size
fetch.min.bytes=1
fetch.max.wait.ms=500
max.partition.fetch.bytes=1048576

# Commit
enable.auto.commit=false # Meglio commit manuale
```

### Tuning Broker
```properties
# Thread
num.network.threads=8
num.io.threads=16

# Buffer
socket.send.buffer.bytes=1048576
socket.receive.buffer.bytes=1048576

# Log
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
```

---

## ESERCIZIO 58: Upgrade Strategy
**Difficoltà: | Tempo: 20 min**

### Procedura Upgrade Sicuro
```
1. BACKUP
 Backup configurazioni
 Documentare stato attuale

2. TEST
 Upgrade prima in ambiente DEV/STAGING
 Test applicazioni con nuova versione

3. PRE-CHECK PRODUZIONE
 Nessuna under-replicated partition
 Consumer lag sotto controllo
 Finestra di manutenzione comunicata

4. UPGRADE ROLLING
 Un broker alla volta
 Attendi sincronizzazione tra ogni restart
 Monitora metriche

5. POST-CHECK
 Tutti i broker sulla nuova versione
 Nessuna under-replicated partition
 Applicazioni funzionanti

6. ROLLBACK PLAN
 Procedura documentata
 Backup dei binari vecchi
```

---

## ESERCIZIO 59: Documentazione Operativa
**Difficoltà: | Tempo: 20 min**

### Template Runbook
```markdown
# RUNBOOK: [Nome Operazione]

## Prerequisiti
- [ ] Accesso al cluster
- [ ] Backup effettuato
- [ ] Finestra di manutenzione approvata

## Procedura
1. Step 1
2. Step 2
3. ...

## Verifica
- [ ] Check 1
- [ ] Check 2

## Rollback
1. In caso di errore, eseguire...

## Contatti
- Team: Kafka Ops
- Escalation: ...
```

---

## ESERCIZIO 60: Automazione con Jenkins
**Difficoltà: | Tempo: 25 min**

### Pipeline per Deploy Topic
```groovy
pipeline {
 agent { label 'kafka-agent' }

 parameters {
 string(name: 'TOPIC_NAME', description: 'Nome topic')
 string(name: 'PARTITIONS', defaultValue: '6')
 string(name: 'REPLICAS', defaultValue: '3')
 }

 stages {
 stage('Validate') {
 steps {
 sh '''
 if [ -z "$TOPIC_NAME" ]; then
 echo "ERROR: TOPIC_NAME required"
 exit 1
 fi
 '''
 }
 }

 stage('Create Topic') {
 steps {
 sh '''
 kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic $TOPIC_NAME \
 --partitions $PARTITIONS \
 --replication-factor $REPLICAS \
 --command-config /tmp/admin.properties
 '''
 }
 }

 stage('Verify') {
 steps {
 sh '''
 kubectl exec kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --topic $TOPIC_NAME \
 --command-config /tmp/admin.properties
 '''
 }
 }
 }
}
```

---

# COMPLETATO!

Hai completato tutti i 60 esercizi del corso Kafka SysAdmin.

## Riepilogo Competenze Acquisite

| Area | Competenze |
|------|------------|
| **Fondamenti** | Topic, Partizioni, Repliche, Consumer Group, Lag |
| **Kubernetes** | Strimzi, CRD, Troubleshooting pod, Rolling restart |
| **VM/Bare Metal** | Installazione, Systemd, KRaft, Backup |
| **Troubleshooting** | Under-replicated, Offline, Network, Performance |
| **Produzione** | HA, DR, Security, Monitoring, Automation |

## Prossimi Passi
1. Pratica ogni giorno nel tuo lab
2. Simula scenari di failure
3. Automatizza tutto con Jenkins
4. Studia per certificazioni (Confluent Certified Administrator)

**Buon lavoro come Kafka SysAdmin! **
