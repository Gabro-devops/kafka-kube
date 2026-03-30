# CORSO COMPLETO KAFKA SYSADMIN
## Esercizi Pratici per Kubernetes e VM/Bare Metal

---

# INDICE GENERALE

| Modulo | Argomento | Esercizi | Ambiente |
|--------|-----------|----------|----------|
| **1** | Fondamenti Kafka | 1-10 | Kubernetes |
| **2** | Kubernetes/Strimzi Avanzato | 11-20 | Kubernetes |
| **3** | VM/Bare Metal | 21-35 | VM Linux |
| **4** | Troubleshooting & Problemi Reali | 36-50 | Entrambi |
| **5** | Produzione & Best Practices | 51-60 | Entrambi |

---

# 
# MODULO 1: FONDAMENTI KAFKA
# 

## Introduzione: Architettura Kafka

Prima di iniziare gli esercizi, devi capire come funziona Kafka:

```

 KAFKA CLUSTER 


 TOPIC: order-events 

 Partition 0 Partition 1 Partition 2 

 0 1 2 → 0 1 2 → 0 1 → 
 msg msg msg msg msg msg msg msg 

 Leader: B0 Leader: B1 Leader: B2 
 Replicas: B1,B2 Replicas: B0,B2 Replicas: B0,B1 
 ISR: B0,B1,B2 ISR: B0,B1,B2 ISR: B0,B1,B2 



 Broker 0 Broker 1 Broker 2 
 (B0) (B1) (B2) 



CONCETTI CHIAVE:

• Topic = Categoria di messaggi (come una tabella in DB)
• Partition = Suddivisione parallela del topic (più partizioni = più throughput)
• Replica = Copia dei dati su un altro broker (per fault tolerance)
• Leader = Broker che gestisce read/write per una partizione
• ISR = In-Sync Replicas (repliche che sono aggiornate)
• Offset = Indice progressivo del messaggio nella partizione
• Consumer Group = Gruppo di consumer che si dividono le partizioni
```

---

## ESERCIZIO 1: Connessione al Cluster Kafka
**Difficoltà: Principiante | Ambiente: Kubernetes | Tempo: 10 min**

### Obiettivo
Imparare a connettersi al cluster Kafka e verificarne lo stato.

### Cosa Imparerai
- Come accedere ai pod Kafka in Kubernetes
- Come creare file di configurazione per l'autenticazione
- Comandi base per verificare lo stato del cluster

### Prerequisiti
- Cluster Kubernetes con Kafka deployato (il tuo kafka-lab)
- kubectl configurato

### Step-by-Step

**Step 1: Verifica che il cluster Kafka sia attivo**
```bash
# Lista i pod Kafka
kubectl get pods -n kafka-lab -l strimzi.io/cluster=kafka-cluster

# Output atteso:
# NAME READY STATUS RESTARTS AGE
# kafka-cluster-kafka-0 1/1 Running 0 1h
# kafka-cluster-kafka-1 1/1 Running 0 1h
# kafka-cluster-kafka-2 1/1 Running 0 1h
```

**Spiegazione:** I 3 pod sono i broker Kafka. "Running" significa che sono operativi.

**Step 2: Entra nel pod Kafka**
```bash
# Questo comando apre una shell DENTRO il container Kafka
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Ora sei "dentro" il broker Kafka!
# Il prompt cambia in qualcosa come: [kafka@kafka-cluster-kafka-0 kafka]$
```

**Spiegazione:** `kubectl exec -it` è come fare SSH nel container. `-it` significa interattivo con terminale.

**Step 3: Crea il file di autenticazione**
```bash
# Kafka nel tuo lab usa SCRAM-SHA-512 per autenticare
# Devi creare un file con le credenziali

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Verifica che il file sia stato creato
cat /tmp/admin.properties
```

**Spiegazione:**
- `security.protocol=SASL_PLAINTEXT`: usa autenticazione SASL senza TLS
- `sasl.mechanism=SCRAM-SHA-512`: tipo di autenticazione (hash della password)
- `username="admin"` e `password="admin-secret"`: credenziali definite nel values.yaml

**Step 4: Testa la connessione**
```bash
# Lista tutti i topic esistenti
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --list \
 --command-config /tmp/admin.properties

# Se funziona, vedrai i topic di sistema:
# __consumer_offsets
# __strimzi-topic-operator-kstreams-topic-store-changelog
# ... altri topic se ne hai creati
```

**Step 5: Verifica i metadata del cluster**
```bash
# Mostra informazioni sui broker
/opt/kafka/bin/kafka-metadata.sh --snapshot /var/lib/kafka/data-0/__cluster_metadata-0/00000000000000000000.log --command describe

# Oppure usa broker-api-versions per vedere i broker attivi
/opt/kafka/bin/kafka-broker-api-versions.sh \
 --bootstrap-server localhost:9092 \
 --command-config /tmp/admin.properties | head -20
```

### Verifica Completamento
Hai completato l'esercizio se:
- [x] Riesci a entrare nel pod Kafka
- [x] Il file admin.properties funziona
- [x] Vedi la lista dei topic

### Tips
- Se ricevi errori di autenticazione, verifica le credenziali nel values.yaml
- Il comando `--command-config` è SEMPRE necessario quando c'è autenticazione

---

## ESERCIZIO 2: Creare e Descrivere Topic
**Difficoltà: Principiante | Ambiente: Kubernetes | Tempo: 15 min**

### Obiettivo
Creare topic con diverse configurazioni e capire come leggerle.

### Cosa Imparerai
- Creare topic via CLI
- Scegliere partizioni e repliche
- Leggere l'output di describe

### Step-by-Step

**Step 1: Entra nel pod (se non ci sei già)**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

# Ricrea il file di config se necessario
cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF
```

**Step 2: Crea un topic semplice**
```bash
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic my-first-topic \
 --partitions 3 \
 --replication-factor 3 \
 --command-config /tmp/admin.properties

# Output: Created topic my-first-topic.
```

**Spiegazione parametri:**
- `--topic my-first-topic`: nome del topic
- `--partitions 3`: 3 "code" parallele (più partizioni = più throughput)
- `--replication-factor 3`: ogni partizione copiata su 3 broker (fault tolerance)

**Step 3: Descrivi il topic**
```bash
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --topic my-first-topic \
 --command-config /tmp/admin.properties
```

**Output e come leggerlo:**
```
Topic: my-first-topic TopicId: xxx PartitionCount: 3 ReplicationFactor: 3 Configs:
 Topic: my-first-topic Partition: 0 Leader: 2 Replicas: 2,0,1 Isr: 2,0,1
 Topic: my-first-topic Partition: 1 Leader: 0 Replicas: 0,1,2 Isr: 0,1,2
 Topic: my-first-topic Partition: 2 Leader: 1 Replicas: 1,2,0 Isr: 1,2,0

LETTURA:

Partition: 0 → Prima partizione (indice parte da 0)
Leader: 2 → Il broker 2 è responsabile delle read/write
Replicas: 2,0,1 → Copie sui broker 2, 0, e 1
Isr: 2,0,1 → Tutte le repliche sono sincronizzate (buono!)

 PROBLEMA se vedi: Isr: 2,0 (manca il broker 1 dall'ISR)
 Significa che il broker 1 è indietro con i dati!
```

**Step 4: Crea topic con configurazioni personalizzate**
```bash
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic orders-topic \
 --partitions 6 \
 --replication-factor 3 \
 --config retention.ms=604800000 \
 --config min.insync.replicas=2 \
 --config cleanup.policy=delete \
 --command-config /tmp/admin.properties
```

**Spiegazione config:**
- `retention.ms=604800000`: mantieni i messaggi per 7 giorni (604800000 ms)
- `min.insync.replicas=2`: una write ha successo solo se 2+ repliche la confermano
- `cleanup.policy=delete`: elimina i vecchi messaggi (vs `compact` che tiene solo l'ultimo per key)

**Step 5: Verifica le configurazioni**
```bash
/opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name orders-topic \
 --describe \
 --command-config /tmp/admin.properties
```

### Quiz di Verifica
1. Se hai 3 broker, qual è il massimo replication-factor possibile?
 <details><summary>Risposta</summary>3 - non puoi avere più repliche che broker</details>

2. Se `Replicas: 2,0,1` ma `Isr: 2`, cosa sta succedendo?
 <details><summary>Risposta</summary>I broker 0 e 1 non sono sincronizzati - forse sono down o lenti</details>

---

## ESERCIZIO 3: Producer e Consumer Console
**Difficoltà: Principiante | Ambiente: Kubernetes | Tempo: 20 min**

### Obiettivo
Capire come funziona il flusso di messaggi in Kafka.

### Cosa Imparerai
- Produrre messaggi con e senza key
- Consumare messaggi
- Come le key influenzano il partizionamento

### Step-by-Step

**Step 1: Apri DUE terminali**

Hai bisogno di due terminali: uno per il producer, uno per il consumer.

**Terminale 1 (Consumer) - Avvia prima il consumer:**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Avvia consumer che mostra anche partizione e offset
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic my-first-topic \
 --from-beginning \
 --property print.partition=true \
 --property print.offset=true \
 --property print.key=true \
 --consumer.config /tmp/admin.properties

# Lascia questo terminale aperto - mostrerà i messaggi in arrivo
```

**Terminale 2 (Producer) - Invia messaggi:**
```bash
kubectl exec -it kafka-cluster-kafka-1 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Producer SENZA key (round-robin tra partizioni)
/opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic my-first-topic \
 --producer.config /tmp/admin.properties

# Scrivi questi messaggi (premi Enter dopo ognuno):
> Primo messaggio senza key
> Secondo messaggio senza key
> Terzo messaggio senza key
# Premi CTRL+C per uscire
```

**Osserva il Terminale 1:** I messaggi arrivano su partizioni diverse (round-robin).

**Step 2: Producer CON key**
```bash
# Nel terminale 2, avvia producer con parsing delle key
/opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic my-first-topic \
 --property "parse.key=true" \
 --property "key.separator=:" \
 --producer.config /tmp/admin.properties

# Formato: KEY:VALORE
# Scrivi:
> user-1:Ordine di user-1 numero 1
> user-2:Ordine di user-2 numero 1
> user-1:Ordine di user-1 numero 2
> user-1:Ordine di user-1 numero 3
> user-2:Ordine di user-2 numero 2
# CTRL+C
```

**Osserva il Terminale 1:**
```
Partition:0 Offset:0 user-1 Ordine di user-1 numero 1
Partition:2 Offset:0 user-2 Ordine di user-2 numero 1
Partition:0 Offset:1 user-1 Ordine di user-1 numero 2
Partition:0 Offset:2 user-1 Ordine di user-1 numero 3
Partition:2 Offset:1 user-2 Ordine di user-2 numero 2
```

**Nota importante:** Tutti i messaggi con `user-1` finiscono nella STESSA partizione (0)!
Questo garantisce che siano **ordinati** tra loro.

### Concetto Chiave: Partizionamento

```
SENZA KEY:

Messaggio → Round-robin o Sticky Partitioning → Partizione casuale
Risultato: I messaggi sono distribuiti, ma NON ordinati!

CON KEY:

Messaggio con Key → hash(key) % num_partitions → Stessa partizione SEMPRE
Risultato: Messaggi con stessa key sono ORDINATI!

ESEMPIO PRATICO:
Se stai processando ordini di un utente, usa lo userId come key.
Così tutti gli ordini dello stesso utente sono ordinati.
```

### Verifica Completamento
- [x] Riesci a inviare messaggi senza key
- [x] Riesci a inviare messaggi con key
- [x] Noti che la stessa key finisce sempre nella stessa partizione

---

## ESERCIZIO 4: Consumer Groups
**Difficoltà: Base | Ambiente: Kubernetes | Tempo: 25 min**

### Obiettivo
Capire come i consumer group permettono di scalare il processing.

### Cosa Imparerai
- Differenza tra consumer singolo e gruppo
- Come le partizioni vengono assegnate
- Cosa succede durante un rebalance

### Step-by-Step

**Step 1: Crea topic con 6 partizioni (se non esiste)**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Crea topic
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic consumer-group-test \
 --partitions 6 \
 --replication-factor 3 \
 --command-config /tmp/admin.properties
```

**Step 2: Avvia il PRIMO consumer del gruppo**

**Terminale 1:**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Consumer nel gruppo "my-group"
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic consumer-group-test \
 --group my-group \
 --property print.partition=true \
 --consumer.config /tmp/admin.properties
```

**Step 3: Verifica assegnazione partizioni**

**Terminale 2:**
```bash
kubectl exec -it kafka-cluster-kafka-1 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Vedi come sono assegnate le partizioni
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group my-group \
 --command-config /tmp/admin.properties
```

**Output (1 consumer):**
```
GROUP TOPIC PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG CONSUMER-ID HOST CLIENT-ID
my-group consumer-group-test 0 0 0 0 consumer-1-xxx /10.x.x.x consumer-1
my-group consumer-group-test 1 0 0 0 consumer-1-xxx /10.x.x.x consumer-1
my-group consumer-group-test 2 0 0 0 consumer-1-xxx /10.x.x.x consumer-1
my-group consumer-group-test 3 0 0 0 consumer-1-xxx /10.x.x.x consumer-1
my-group consumer-group-test 4 0 0 0 consumer-1-xxx /10.x.x.x consumer-1
my-group consumer-group-test 5 0 0 0 consumer-1-xxx /10.x.x.x consumer-1

→ Un solo consumer ha TUTTE le 6 partizioni!
```

**Step 4: Aggiungi un SECONDO consumer (stesso gruppo)**

**Terminale 3:**
```bash
kubectl exec -it kafka-cluster-kafka-2 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Secondo consumer nello STESSO gruppo
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic consumer-group-test \
 --group my-group \
 --property print.partition=true \
 --consumer.config /tmp/admin.properties
```

**Step 5: Osserva il REBALANCE**

Torna al Terminale 2 e riesegui describe:
```bash
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group my-group \
 --command-config /tmp/admin.properties
```

**Output (2 consumer):**
```
GROUP TOPIC PARTITION CONSUMER-ID
my-group consumer-group-test 0 consumer-1-xxx ← Consumer 1
my-group consumer-group-test 1 consumer-1-xxx ← Consumer 1
my-group consumer-group-test 2 consumer-1-xxx ← Consumer 1
my-group consumer-group-test 3 consumer-2-yyy ← Consumer 2
my-group consumer-group-test 4 consumer-2-yyy ← Consumer 2
my-group consumer-group-test 5 consumer-2-yyy ← Consumer 2

→ Kafka ha REDISTRIBUITO le partizioni automaticamente!
 Consumer 1: partizioni 0,1,2
 Consumer 2: partizioni 3,4,5
```

**Step 6: Testa con messaggi**

**Terminale 2 (Producer):**
```bash
/opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic consumer-group-test \
 --producer.config /tmp/admin.properties

# Invia 6 messaggi
> msg-1
> msg-2
> msg-3
> msg-4
> msg-5
> msg-6
```

**Osserva:** Alcuni messaggi appaiono sul Terminale 1, altri sul Terminale 3!
Ogni consumer riceve solo i messaggi delle SUE partizioni.

### Concetto Chiave: Consumer Group

```

 CONSUMER GROUP: my-group 

 Topic: consumer-group-test (6 partizioni) 


 Part 0 Part 1 Part 2 Part 3 Part 4 Part 5 






 Consumer 1 Consumer 2 
 (0,1,2) (3,4,5) 


 REGOLA: Una partizione può essere letta da UN SOLO consumer del gruppo
 CONSEGUENZA: Max consumer = num partizioni (oltre sono idle) 

```

### Verifica Completamento
- [x] Hai visto il rebalance quando aggiungi un consumer
- [x] Capisci che ogni consumer legge partizioni diverse
- [x] Sai che non puoi avere più consumer che partizioni

---

## ESERCIZIO 5: Consumer Lag
**Difficoltà: Base | Ambiente: Kubernetes | Tempo: 20 min**

### Obiettivo
Imparare a monitorare il consumer lag - la metrica più importante per Kafka.

### Cosa Imparerai
- Cos'è il lag e perché è importante
- Come misurarlo
- Quando preoccuparsi

### Step-by-Step

**Step 1: Crea un topic e produci messaggi**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Crea topic
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic lag-test \
 --partitions 3 \
 --replication-factor 3 \
 --command-config /tmp/admin.properties

# Produci 100 messaggi
for i in $(seq 1 100); do
 echo "messaggio-$i" | /opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic lag-test \
 --producer.config /tmp/admin.properties 2>/dev/null
done
echo "Prodotti 100 messaggi"
```

**Step 2: Avvia consumer e fermalo subito**
```bash
# Consuma solo 10 messaggi poi esci
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic lag-test \
 --group lag-test-group \
 --max-messages 10 \
 --consumer.config /tmp/admin.properties
```

**Step 3: Misura il LAG**
```bash
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group lag-test-group \
 --command-config /tmp/admin.properties
```

**Output:**
```
GROUP TOPIC PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG
lag-test-group lag-test 0 4 35 31
lag-test-group lag-test 1 3 32 29
lag-test-group lag-test 2 3 33 30
 TOTAL: 90

LETTURA:

CURRENT-OFFSET: 4 → Il consumer ha letto fino al messaggio 4
LOG-END-OFFSET: 35 → L'ultimo messaggio scritto è il 35
LAG: 31 → Ci sono 31 messaggi da processare (35 - 4)

 LAG TOTALE: 90 messaggi non ancora processati!
```

**Step 4: Consuma tutto e verifica lag = 0**
```bash
# Consuma tutti i messaggi rimanenti
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic lag-test \
 --group lag-test-group \
 --consumer.config /tmp/admin.properties &

# Aspetta qualche secondo
sleep 5

# Ferma il consumer
kill %1 2>/dev/null

# Verifica lag
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group lag-test-group \
 --command-config /tmp/admin.properties
```

**Output atteso:** LAG = 0 (o molto basso)

### Interpretazione del LAG

```
LAG = 0 (costante)

 PERFETTO! Il consumer processa i messaggi alla stessa velocità
 con cui arrivano.

LAG = piccolo e stabile (es: 10-50)

 OK. Un piccolo ritardo è fisiologico.

LAG cresce lentamente

 ATTENZIONE. Il consumer è leggermente più lento dei producer.
 Azioni:
 - Monitora la tendenza
 - Prepara scaling se continua

LAG cresce rapidamente

 PROBLEMA! Il consumer non tiene il passo.
 Azioni IMMEDIATE:
 1. Scala i consumer (aggiungi istanze)
 2. Verifica se c'è un problema nel processing (query lente, API esterne)
 3. Verifica risorse (CPU, memoria del consumer)

LAG = numero enorme

 CRITICO! Il consumer è molto indietro.
 Considera se:
 - Ripartire da "latest" (perdendo i messaggi vecchi)
 - Scalare aggressivamente
 - C'è un bug nel consumer che lo blocca
```

### Verifica Completamento
- [x] Sai leggere l'output di describe group
- [x] Capisci la differenza tra CURRENT-OFFSET e LOG-END-OFFSET
- [x] Sai quando il lag è un problema

---

## ESERCIZIO 6: Creare Topic via Strimzi (Metodo K8s)
**Difficoltà: Base | Ambiente: Kubernetes | Tempo: 15 min**

### Obiettivo
Creare topic usando il metodo GitOps di Strimzi invece della CLI.

### Cosa Imparerai
- Creare KafkaTopic come risorsa Kubernetes
- Vantaggi del metodo dichiarativo
- Come Strimzi gestisce i topic

### Step-by-Step

**Step 1: Crea un file YAML per il topic**
```bash
# Esci dal pod se sei dentro
exit

# Crea il file sul tuo computer
cat << 'EOF' > /tmp/payment-events-topic.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
 name: payment-events
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
 # Labels personalizzate per organizzazione
 team: payments
 environment: development
spec:
 partitions: 6
 replicas: 3
 config:
 # Retention: 7 giorni
 retention.ms: "604800000"
 # Minimo 2 repliche sincronizzate per write
 min.insync.replicas: "2"
 # Politica di cleanup
 cleanup.policy: "delete"
 # Compressione messaggi
 compression.type: "producer"
EOF

cat /tmp/payment-events-topic.yaml
```

**Step 2: Applica la risorsa**
```bash
kubectl apply -f /tmp/payment-events-topic.yaml

# Output: kafkatopic.kafka.strimzi.io/payment-events created
```

**Step 3: Verifica creazione**
```bash
# Via kubectl
kubectl get kafkatopic payment-events -n kafka-lab

# Output:
# NAME CLUSTER PARTITIONS REPLICATION FACTOR READY
# payment-events kafka-cluster 6 3 True

# Dettagli
kubectl describe kafkatopic payment-events -n kafka-lab
```

**Step 4: Verifica che esista anche via CLI Kafka**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- \
 /opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --topic payment-events \
 --command-config /tmp/admin.properties
```

### Vantaggi di Strimzi vs CLI

| Aspetto | CLI (kafka-topics.sh) | Strimzi KafkaTopic |
|---------|----------------------|-------------------|
| Versionamento | Nessuno | Git |
| Audit | Chi l'ha fatto? | kubectl get events |
| Riproducibilità | Devi ricordare i comandi | YAML sempre uguale |
| Automazione | Script custom | GitOps, ArgoCD |
| Self-healing | No | Strimzi ricrea se eliminato |

### Verifica Completamento
- [x] Sai creare un KafkaTopic YAML
- [x] Il topic è stato creato correttamente
- [x] Capisci perché Strimzi è meglio in produzione

---

## ESERCIZIO 7: Creare Utenti Kafka con ACL
**Difficoltà: Intermedio | Ambiente: Kubernetes | Tempo: 20 min**

### Obiettivo
Creare utenti con permessi specifici per segregare gli accessi.

### Cosa Imparerai
- Modello di sicurezza Kafka (ACL)
- Creare utenti producer-only e consumer-only
- Testare che i permessi funzionino

### Step-by-Step

**Step 1: Crea utente Producer (solo scrittura)**
```bash
cat << 'EOF' > /tmp/orders-producer-user.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
 name: orders-producer
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 authentication:
 type: scram-sha-512
 authorization:
 type: simple
 acls:
 # Può scrivere su topic che iniziano con "orders-"
 - resource:
 type: topic
 name: orders-
 patternType: prefix
 operations:
 - Write
 - Describe
 - Create
EOF

kubectl apply -f /tmp/orders-producer-user.yaml
```

**Step 2: Crea utente Consumer (solo lettura)**
```bash
cat << 'EOF' > /tmp/orders-consumer-user.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
 name: orders-consumer
 namespace: kafka-lab
 labels:
 strimzi.io/cluster: kafka-cluster
spec:
 authentication:
 type: scram-sha-512
 authorization:
 type: simple
 acls:
 # Può leggere da topic che iniziano con "orders-"
 - resource:
 type: topic
 name: orders-
 patternType: prefix
 operations:
 - Read
 - Describe
 # Può usare consumer group che iniziano con "orders-"
 - resource:
 type: group
 name: orders-
 patternType: prefix
 operations:
 - Read
EOF

kubectl apply -f /tmp/orders-consumer-user.yaml
```

**Step 3: Recupera le password generate**
```bash
# Password producer
PRODUCER_PWD=$(kubectl get secret orders-producer -n kafka-lab -o jsonpath='{.data.password}' | base64 -d)
echo "Producer password: $PRODUCER_PWD"

# Password consumer
CONSUMER_PWD=$(kubectl get secret orders-consumer -n kafka-lab -o jsonpath='{.data.password}' | base64 -d)
echo "Consumer password: $CONSUMER_PWD"
```

**Step 4: Crea topic orders-events**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic orders-events \
 --partitions 3 \
 --replication-factor 3 \
 --command-config /tmp/admin.properties
```

**Step 5: Testa il producer (DEVE FUNZIONARE)**
```bash
# Usa la password ottenuta prima
cat << EOF > /tmp/producer.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="orders-producer" password="$PRODUCER_PWD";
EOF

# Questo DEVE funzionare
echo '{"orderId": "ORD-001"}' | /opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic orders-events \
 --producer.config /tmp/producer.properties

echo " Write su orders-events: OK"
```

**Step 6: Testa che producer NON possa leggere**
```bash
# Questo DEVE FALLIRE (producer non ha permessi di lettura)
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic orders-events \
 --from-beginning \
 --max-messages 1 \
 --consumer.config /tmp/producer.properties 2>&1 | head -5

# Output atteso: TopicAuthorizationException
echo " Read negato al producer: OK (comportamento corretto)"
```

**Step 7: Testa che producer NON possa scrivere su altri topic**
```bash
# Questo DEVE FALLIRE (producer può scrivere solo su orders-*)
echo 'test' | /opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic payment-events \
 --producer.config /tmp/producer.properties 2>&1 | head -5

# Output atteso: TopicAuthorizationException
echo " Write su payment-events negato: OK (comportamento corretto)"
```

### Verifica Completamento
- [x] Sai creare KafkaUser con ACL specifiche
- [x] Capisci la differenza tra prefix e literal pattern
- [x] Hai verificato che i permessi funzionano

---

## ESERCIZIO 8: Reset degli Offset
**Difficoltà: Intermedio | Ambiente: Kubernetes | Tempo: 20 min**

### Obiettivo
Imparare a riprocessare messaggi resettando gli offset.

### Cosa Imparerai
- Quando serve resettare gli offset
- Diversi tipi di reset
- Come farlo in modo sicuro

### IMPORTANTE
Il consumer group DEVE essere FERMO (nessun consumer attivo) prima del reset!

### Step-by-Step

**Step 1: Prepara ambiente di test**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

# Crea topic
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic reset-test \
 --partitions 3 \
 --replication-factor 3 \
 --command-config /tmp/admin.properties 2>/dev/null || echo "Topic esiste già"

# Produci 50 messaggi
for i in $(seq 1 50); do
 echo "msg-$i" | /opt/kafka/bin/kafka-console-producer.sh \
 --bootstrap-server localhost:9092 \
 --topic reset-test \
 --producer.config /tmp/admin.properties 2>/dev/null
done
echo "Prodotti 50 messaggi"
```

**Step 2: Consuma alcuni messaggi**
```bash
# Consuma 20 messaggi
/opt/kafka/bin/kafka-console-consumer.sh \
 --bootstrap-server localhost:9092 \
 --topic reset-test \
 --group reset-test-group \
 --max-messages 20 \
 --consumer.config /tmp/admin.properties

# Verifica stato
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group reset-test-group \
 --command-config /tmp/admin.properties
```

**Step 3: Reset ALL'INIZIO (--to-earliest)**
```bash
# Prima: DRY RUN (mostra cosa farebbe senza eseguire)
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --group reset-test-group \
 --topic reset-test \
 --reset-offsets \
 --to-earliest \
 --dry-run \
 --command-config /tmp/admin.properties

# Output mostra i NEW-OFFSET (tutti a 0)
```

```bash
# Esegui per davvero
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --group reset-test-group \
 --topic reset-test \
 --reset-offsets \
 --to-earliest \
 --execute \
 --command-config /tmp/admin.properties

# Verifica: ora CURRENT-OFFSET è 0
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --group reset-test-group \
 --command-config /tmp/admin.properties
```

**Step 4: Reset ALLA FINE (--to-latest)**
```bash
# Salta tutti i messaggi esistenti, riparti dai nuovi
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --group reset-test-group \
 --topic reset-test \
 --reset-offsets \
 --to-latest \
 --execute \
 --command-config /tmp/admin.properties
```

**Step 5: Reset a una DATA SPECIFICA (--to-datetime)**
```bash
# Reset a ieri alle 10:00
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --group reset-test-group \
 --topic reset-test \
 --reset-offsets \
 --to-datetime "2024-01-15T10:00:00.000" \
 --dry-run \
 --command-config /tmp/admin.properties
```

**Step 6: SHIFT relativo (--shift-by)**
```bash
# Torna indietro di 10 messaggi
/opt/kafka/bin/kafka-consumer-groups.sh \
 --bootstrap-server localhost:9092 \
 --group reset-test-group \
 --topic reset-test \
 --reset-offsets \
 --shift-by -10 \
 --execute \
 --command-config /tmp/admin.properties
```

### Riepilogo Tipi di Reset

| Opzione | Descrizione | Caso d'uso |
|---------|-------------|------------|
| `--to-earliest` | Vai all'inizio | Riprocessa tutto |
| `--to-latest` | Vai alla fine | Salta tutto, riparti da ora |
| `--to-datetime` | Vai a una data | Bug: riprocessa ultimi 2 giorni |
| `--to-offset N` | Vai a offset specifico | Precisione chirurgica |
| `--shift-by -N` | Indietro di N messaggi | "Torna indietro un po'" |

### Attenzione: Idempotenza!
Se il tuo consumer non è **idempotente**, resettando gli offset potresti creare **duplicati**!

```
NON IDEMPOTENTE (problematico):
- Consumer riceve ordine → invia email
- Reset → riceve stesso ordine → invia ALTRA email!
- Utente riceve 2 email identiche 

IDEMPOTENTE (corretto):
- Consumer riceve ordine → controlla se già processato → se no, invia email
- Reset → riceve stesso ordine → già processato → skip
- Utente riceve 1 sola email 
```

### Verifica Completamento
- [x] Sai usare --dry-run prima di --execute
- [x] Conosci i diversi tipi di reset
- [x] Capisci il problema dell'idempotenza

---

## ESERCIZIO 9: Modificare Configurazione di un Topic
**Difficoltà: Base | Ambiente: Kubernetes | Tempo: 15 min**

### Obiettivo
Modificare configurazioni di topic esistenti (retention, partizioni, etc.).

### Step-by-Step

**Step 1: Vedi configurazione attuale**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

/opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name payment-events \
 --describe \
 --command-config /tmp/admin.properties
```

**Step 2: Modifica retention (riduci a 1 giorno)**
```bash
/opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name payment-events \
 --alter \
 --add-config retention.ms=86400000 \
 --command-config /tmp/admin.properties

# Verifica
/opt/kafka/bin/kafka-configs.sh \
 --bootstrap-server localhost:9092 \
 --entity-type topics \
 --entity-name payment-events \
 --describe \
 --command-config /tmp/admin.properties
```

**Step 3: Aumenta partizioni (SOLO AUMENTO, mai diminuzione!)**
```bash
# Da 6 a 9 partizioni
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --alter \
 --topic payment-events \
 --partitions 9 \
 --command-config /tmp/admin.properties

# Verifica
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --topic payment-events \
 --command-config /tmp/admin.properties
```

 **ATTENZIONE:** Non puoi MAI ridurre le partizioni! I messaggi esistenti sono distribuiti
 e ridurre causerebbe perdita di dati.

### Verifica Completamento
- [x] Sai modificare retention
- [x] Sai aumentare partizioni
- [x] Capisci perché non si possono ridurre le partizioni

---

## ESERCIZIO 10: Eliminare un Topic
**Difficoltà: Base | Ambiente: Kubernetes | Tempo: 10 min**

### Obiettivo
Eliminare topic in modo sicuro.

### ATTENZIONE
L'eliminazione è **IRREVERSIBILE**! Tutti i dati vengono persi.

### Step-by-Step

**Step 1: Crea un topic di test da eliminare**
```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka-lab -- bash

cat << 'EOF' > /tmp/admin.properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="admin-secret";
EOF

/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --create \
 --topic topic-da-eliminare \
 --partitions 1 \
 --replication-factor 1 \
 --command-config /tmp/admin.properties
```

**Step 2: Verifica che esista**
```bash
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --list \
 --command-config /tmp/admin.properties | grep topic-da-eliminare
```

**Step 3: Elimina via CLI**
```bash
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --delete \
 --topic topic-da-eliminare \
 --command-config /tmp/admin.properties
```

**Step 4: Verifica eliminazione**
```bash
/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --list \
 --command-config /tmp/admin.properties | grep topic-da-eliminare

# Non dovrebbe restituire nulla
```

**Metodo Strimzi (se creato come KafkaTopic):**
```bash
# Esci dal pod
exit

# Elimina la risorsa K8s
kubectl delete kafkatopic payment-events -n kafka-lab

# Strimzi eliminerà automaticamente il topic dal cluster
```

### Verifica Completamento
- [x] Sai eliminare topic via CLI
- [x] Sai eliminare topic via Strimzi
- [x] Capisci che è irreversibile

---

# Fine Modulo 1

**Prossimo:** Modulo 2 - Kubernetes/Strimzi Avanzato (Esercizi 11-20)
