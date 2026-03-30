# Kafka Deployment — Detailed Guide

## Overview

This project deploys a production-grade Kafka cluster on Kubernetes using **Strimzi** in **KRaft mode** (no ZooKeeper).

---

## Cluster Configuration

### KRaft Mode

KRaft replaces ZooKeeper with a Raft-based internal consensus mechanism. Each node acts as both controller and broker.

```
kafka-cluster-kafka-nodes-0  (controller + broker)
kafka-cluster-kafka-nodes-1  (controller + broker)
kafka-cluster-kafka-nodes-2  (controller + broker)
```

Active Controller is elected via Raft among the 3 nodes.

### Key Parameters

```yaml
version: 4.1.0
metadataVersion: 4.1-IV0
replicas: 3
replication.factor: 3
min.insync.replicas: 2
auto.create.topics.enable: false
```

---

## Authentication — SCRAM-SHA-512

All clients must authenticate with SCRAM-SHA-512.

SCRAM (Salted Challenge Response Authentication Mechanism) never transmits the password over the network — only a cryptographic derivative is exchanged:

1. Client sends username
2. Broker responds with challenge (salt + iterations)
3. Client computes cryptographic response from password
4. Broker verifies response without receiving the password

### Listeners

| Listener | Port | Protocol | Auth |
|---|---|---|---|
| plain | 9092 | SASL_PLAINTEXT | SCRAM-SHA-512 |
| tls | 9093 | SASL_SSL | SCRAM-SHA-512 |

Internal cluster clients use port 9092.

---

## Kafka Users and ACLs

Users are managed via Strimzi `KafkaUser` resources.

| User | Role | Permissions |
|---|---|---|
| `admin` | Admin | All on topics, groups, cluster |
| `producer-user` | Producer | Write, Describe, Create on all topics |
| `consumer-user` | Consumer | Read, Describe on all topics |
| `kafka-connect` | Kafka Connect | All on topics, groups, cluster |

Passwords are managed via Vault + ESO and never stored in the Git repository.

---

## Kafka Connect

Kafka Connect is deployed with a Strimzi build that includes the `connect-file` connector as a base example.

To add connectors, edit `helm/values.yaml` under the `kafkaConnect.connectors` section.

---

## Cruise Control

Cruise Control is deployed alongside the cluster and handles:
- Automatic partition rebalancing between brokers
- Resource usage analysis
- Rebalancing proposals

---

## Strimzi Operator

The Strimzi Operator manages the Kafka lifecycle:
- Creates and configures broker pods
- Manages certificates for TLS
- Handles rolling updates
- Manages KafkaTopic and KafkaUser resources

---

## Deploy Order

```
1. Vault (secrets)
2. External Secrets Operator (secret sync)
3. Strimzi Operator (Kafka lifecycle)
4. Kafka Lab Helm chart (all resources)
   - KafkaNodePool
   - Kafka cluster
   - KafkaUsers
   - Kafka Connect
   - Jenkins, AWX, Grafana, Prometheus, Kafka Exporter, Kafka UI
```

---

## Useful Commands

```bash
# Cluster status
kubectl get kafka -n kafka-lab
kubectl get kafkanodepool -n kafka-lab

# Brokers
kubectl get pods -n kafka-lab -l strimzi.io/kind=Kafka

# Topics
kubectl get kafkatopic -n kafka-lab

# Users
kubectl get kafkauser -n kafka-lab

# Broker logs
kubectl logs kafka-cluster-kafka-nodes-0 -n kafka-lab

# Describe Kafka cluster
kubectl describe kafka kafka-cluster -n kafka-lab
```

---

## Troubleshooting

**Brokers in CrashLoopBackOff with "Invalid cluster.id":**
```bash
# Old PVCs have a different cluster ID
kubectl delete pvc --all -n kafka-lab
kubectl delete pod kafka-cluster-kafka-nodes-{0,1,2} -n kafka-lab
```

**Kafka not Ready:**
```bash
kubectl describe kafka kafka-cluster -n kafka-lab | grep -A 5 Conditions
```

**SCRAM authentication error:**
```bash
# Secrets not synced
kubectl get externalsecret -n kafka-lab
./scripts/vault/vault-reinit.sh
```
