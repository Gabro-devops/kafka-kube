# Esercizi Kafka Connect

Questa guida ti accompagna nell'utilizzo di **Kafka Connect** per integrare Kafka con sistemi esterni.

---

## Cos'è Kafka Connect?

Kafka Connect è un framework per lo streaming di dati **dentro e fuori** Apache Kafka in modo scalabile e affidabile.

### Concetti Chiave

| Termine | Descrizione |
|---------|-------------|
| **Worker** | Processo JVM che esegue i connector |
| **Connector** | Plugin che definisce come connettersi a un sistema esterno |
| **Task** | Unità di lavoro che effettua il trasferimento dati |
| **Source** | Legge dati da sistema esterno → scrive su Kafka |
| **Sink** | Legge da Kafka → scrive su sistema esterno |

### Architettura

```

 PostgreSQL Elasticsearch 
 (Source) KAFKA (Sink) 


 Topics 
 File System Amazon S3 
 (Source) (Sink) 



 Kafka Connect 
 Workers 

```

---

## Esercizio 1: Verificare Kafka Connect

### 1.1 Controllare lo stato del cluster Connect

```bash
# Verifica che il pod KafkaConnect sia running
kubectl get kafkaconnect -n kafka-lab

# Output atteso:
# NAME DESIRED READY STATUS
# kafka-connect 1 1 Ready

# Dettagli del pod
kubectl get pods -n kafka-lab -l strimzi.io/kind=KafkaConnect
```

### 1.2 Verificare i connector disponibili

```bash
# Entra nel pod Connect
kubectl exec -it -n kafka-lab $(kubectl get pods -n kafka-lab -l strimzi.io/kind=KafkaConnect -o name | head -1) -- bash

# Lista i plugin connector disponibili
curl -s localhost:8083/connector-plugins | jq '.[].class'
```

### 1.3 Controllare lo stato del cluster Connect via REST API

```bash
# Dal pod o con port-forward
kubectl port-forward -n kafka-lab svc/kafka-connect-connect-api 8083:8083 &

# Info sul cluster
curl -s http://localhost:8083/ | jq

# Lista connector attivi
curl -s http://localhost:8083/connectors | jq
```

---

## Esercizio 2: FileStreamSource Connector

Creiamo un connector che legge da un file e pubblica su Kafka.

### 2.1 Creare il file YAML del connector

```yaml
# file-source-connector.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
 name: file-source-demo
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-connect
spec:
 class: org.apache.kafka.connect.file.FileStreamSourceConnector
 tasksMax: 1
 autoRestart:
 enabled: true
 maxRestarts: 5
 config:
 file: "/tmp/demo-input.txt"
 topic: "file-source-topic"
```

### 2.2 Applicare il connector

```bash
kubectl apply -f file-source-connector.yaml
```

### 2.3 Verificare lo stato

```bash
# Stato del connector
kubectl get kafkaconnector -n kafka-lab

# Dettagli
kubectl describe kafkaconnector file-source-demo -n kafka-lab
```

### 2.4 Testare il connector

```bash
# Crea un file di test nel pod Connect
kubectl exec -it -n kafka-lab $(kubectl get pods -n kafka-lab -l strimzi.io/kind=KafkaConnect -o name | head -1) -- \
 bash -c 'echo "Messaggio di test $(date)" >> /tmp/demo-input.txt'

# Consuma dal topic per vedere i messaggi
# NOTA: Usa la porta TLS (9093) con autenticazione SCRAM
kubectl run kafka-consumer --rm -it --restart=Never \
 --image=quay.io/strimzi/kafka:latest-kafka-3.6.0 \
 -n kafka-lab -- \
 bin/kafka-console-consumer.sh \
 --bootstrap-server kafka-cluster-kafka-bootstrap:9093 \
 --topic file-source-topic \
 --from-beginning \
 --consumer-property security.protocol=SASL_SSL \
 --consumer-property sasl.mechanism=SCRAM-SHA-512 \
 --consumer-property sasl.jaas.config='org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";' \
 --consumer-property ssl.truststore.type=PEM
```

---

## Esercizio 3: FileStreamSink Connector

Creiamo un connector che legge da Kafka e scrive su file.

### 3.1 Creare il file YAML del connector

```yaml
# file-sink-connector.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
 name: file-sink-demo
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-connect
spec:
 class: org.apache.kafka.connect.file.FileStreamSinkConnector
 tasksMax: 1
 config:
 file: "/tmp/demo-output.txt"
 topics: "file-source-topic"
```

### 3.2 Applicare e verificare

```bash
kubectl apply -f file-sink-connector.yaml

# Verifica che il file sia stato creato
kubectl exec -it -n kafka-lab $(kubectl get pods -n kafka-lab -l strimzi.io/kind=KafkaConnect -o name | head -1) -- \
 cat /tmp/demo-output.txt
```

---

## Esercizio 4: Connector con JSON Schema

### 4.1 Source con schema JSON

```yaml
# json-source-connector.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
 name: json-source-demo
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-connect
spec:
 class: org.apache.kafka.connect.file.FileStreamSourceConnector
 tasksMax: 1
 config:
 file: "/tmp/json-input.txt"
 topic: "json-events"
 # Override dei converter per questo connector
 value.converter: "org.apache.kafka.connect.json.JsonConverter"
 value.converter.schemas.enable: "true"
```

### 4.2 Preparare dati JSON

```bash
kubectl exec -it -n kafka-lab $(kubectl get pods -n kafka-lab -l strimzi.io/kind=KafkaConnect -o name | head -1) -- \
 bash -c 'cat >> /tmp/json-input.txt << EOF
{"schema":{"type":"struct","fields":[{"type":"string","field":"name"},{"type":"int32","field":"age"}]},"payload":{"name":"Mario","age":30}}
{"schema":{"type":"struct","fields":[{"type":"string","field":"name"},{"type":"int32","field":"age"}]},"payload":{"name":"Luigi","age":28}}
EOF'
```

---

## Esercizio 5: Gestire errori e Dead Letter Queue

### 5.1 Configurare una DLQ per messaggi falliti

```yaml
# connector-with-dlq.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
 name: sink-with-dlq
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-connect
spec:
 class: org.apache.kafka.connect.file.FileStreamSinkConnector
 tasksMax: 1
 config:
 file: "/tmp/output-with-dlq.txt"
 topics: "source-topic"
 # Error handling
 errors.tolerance: "all"
 errors.deadletterqueue.topic.name: "dlq-sink-errors"
 errors.deadletterqueue.topic.replication.factor: "3"
 errors.deadletterqueue.context.headers.enable: "true"
 errors.log.enable: "true"
 errors.log.include.messages: "true"
```

---

## Esercizio 6: Monitorare Kafka Connect

### 6.1 Metriche via JMX

```bash
# Port-forward per accedere alle metriche
kubectl port-forward -n kafka-lab svc/kafka-connect-connect-api 8083:8083 &

# Stato di tutti i connector
curl -s http://localhost:8083/connectors | jq

# Stato dettagliato di un connector
curl -s http://localhost:8083/connectors/file-source-demo/status | jq
```

### 6.2 Query Prometheus (se monitoring abilitato)

```promql
# Numero di task running
sum(kafka_connect_connector_task_status{status="running"})

# Errori nei connector
sum(rate(kafka_connect_connector_task_batch_size_avg[5m])) by (connector)

# Latenza media dei task
avg(kafka_connect_source_task_poll_batch_avg_time_ms) by (connector)
```

---

## Esercizio 7: Operazioni sui Connector

### 7.1 Pausa e Resume

```bash
# Pausa
curl -X PUT http://localhost:8083/connectors/file-source-demo/pause

# Resume 
curl -X PUT http://localhost:8083/connectors/file-source-demo/resume

# Restart
curl -X POST http://localhost:8083/connectors/file-source-demo/restart
```

### 7.2 Restart di un singolo task

```bash
# Restart del task 0
curl -X POST http://localhost:8083/connectors/file-source-demo/tasks/0/restart
```

### 7.3 Aggiornare la configurazione

```bash
# Aggiorna la config
curl -X PUT http://localhost:8083/connectors/file-source-demo/config \
 -H "Content-Type: application/json" \
 -d '{
 "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
 "file": "/tmp/new-input.txt",
 "topic": "new-topic"
 }'
```

### 7.4 Eliminare un connector

```bash
# Via kubectl
kubectl delete kafkaconnector file-source-demo -n kafka-lab

# O via REST API
curl -X DELETE http://localhost:8083/connectors/file-source-demo
```

---

## Riepilogo Comandi Utili

| Operazione | Comando |
|------------|---------|
| Lista connector | `curl localhost:8083/connectors` |
| Stato connector | `curl localhost:8083/connectors/{name}/status` |
| Config connector | `curl localhost:8083/connectors/{name}/config` |
| Pausa | `curl -X PUT localhost:8083/connectors/{name}/pause` |
| Resume | `curl -X PUT localhost:8083/connectors/{name}/resume` |
| Restart | `curl -X POST localhost:8083/connectors/{name}/restart` |
| Delete | `curl -X DELETE localhost:8083/connectors/{name}` |
| Plugin disponibili | `curl localhost:8083/connector-plugins` |

---

## Risorse Utili

- [Strimzi KafkaConnect](https://strimzi.io/docs/operators/latest/deploying.html#deploying-kafka-connect-str)
- [Debezium Connectors](https://debezium.io/documentation/)
- [Confluent Hub](https://www.confluent.io/hub/) - Repository di connector
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
