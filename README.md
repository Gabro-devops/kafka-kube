# kafka-kube — Production-Ready Kafka on Kubernetes

Enterprise-grade Kafka environment on Kubernetes, deployable with a single command.
This project is entirely focused on **Apache Kafka** and its ecosystem — from cluster management to secret handling, CI/CD automation, monitoring, and data integration.

---

## System Requirements

Before running the deploy, make sure you have the following installed:

| Tool | Minimum Version | How to Install |
|---|---|---|
| Docker Desktop | any | https://www.docker.com/products/docker-desktop |
| Kubernetes | enabled in Docker Desktop | Docker Desktop -> Settings -> Kubernetes -> Enable Kubernetes |
| Helm | 3.x | `brew install helm` |
| kubectl | any | included in Docker Desktop |
| vault CLI | any | `brew install vault` |

**Hardware:** at minimum 8GB RAM allocated to Docker Desktop is recommended (16GB preferred).
The deploy downloads all Docker images automatically on first run. Internet connection required.

---

## Quick Start

```bash
./deploy.sh      # installs everything (~15-20 minutes)
./cleanup.sh     # removes everything
```

The script asks for a single password used for all services.
Credentials are saved automatically in `scripts/vault/vault-passwords-TIMESTAMP.txt`.

---

## Full Technology Stack

### Kafka — Core (the focus of this project)

| Technology | Version | Role |
|---|---|---|
| Apache Kafka | 4.1.0 | Distributed message broker |
| KRaft | metadata version 4.1-IV0 | ZooKeeper-less mode — controllers and brokers unified |
| Strimzi Operator | 0.51.0 | Kafka lifecycle management on Kubernetes |
| Kafka Connect | 4.1.0 | Data integration with external systems |
| Cruise Control | included in Strimzi | Automatic partition rebalancing between brokers |

### Secret Management

| Technology | Version | Role |
|---|---|---|
| HashiCorp Vault | latest (dev mode) | Centralized vault for all secrets |
| External Secrets Operator (ESO) | latest | Automatic sync from Vault to Kubernetes Secrets |

### CI/CD and Automation

| Technology | Version | Role |
|---|---|---|
| Jenkins | LTS JDK17 | CI/CD pipelines for Kafka topic and user management |
| Jenkins Kubernetes Plugin | included | Dynamic Kubernetes agents per build |
| AWX (Ansible Tower OSS) | 24.6.1 | Operational automation with Ansible playbooks |
| Ansible | included in AWX EE | Playbooks for health check, topics, users, ACLs |
| kubernetes.core collection | 2.4.0+ | Ansible modules for Kubernetes interaction |

### Monitoring

| Technology | Version | Role |
|---|---|---|
| Prometheus | latest | Metrics collection from brokers and exporter |
| Grafana | latest | Kafka Overview dashboard |
| Kafka Exporter | latest | Exposes Kafka metrics in Prometheus format |
| JMX Prometheus Exporter | included in Strimzi | JVM metrics from Kafka broker nodes |

### Kubernetes Infrastructure

| Technology | Version | Role |
|---|---|---|
| Helm | 3.x | Package manager for the entire stack |
| AWX Operator | 2.19.1 | AWX lifecycle management on Kubernetes |
| PostgreSQL | 15 | AWX internal database |
| Kafka UI (Provectus) | latest | Web UI for brokers, topics, messages, consumer groups |

---

## Kafka Architecture — Deep Dive

### KRaft Mode (no ZooKeeper)

This project runs Kafka in **KRaft mode** — the architecture introduced in Kafka 3.x that eliminates the dependency on ZooKeeper entirely.

In KRaft, every node acts as both **controller** and **broker** simultaneously:
- **Controllers** manage cluster metadata: topic creation, partition assignment, replica management, leader election
- **Brokers** handle data: message production, consumption, replication
- The **Active Controller** is elected among the 3 nodes using the **Raft consensus algorithm**

This means the cluster can tolerate the loss of 1 node out of 3 and continue operating normally.

```
Cluster: 3 nodes (controller + broker)

  kafka-cluster-kafka-nodes-0  <-- Active Controller (elected)
  kafka-cluster-kafka-nodes-1
  kafka-cluster-kafka-nodes-2

Replication factor: 3
Min In-Sync Replicas (ISR): 2
Auto create topics: disabled
Metadata version: 4.1-IV0
```

### Authentication — SCRAM-SHA-512

All clients connecting to the cluster must authenticate using **SCRAM-SHA-512** (Salted Challenge Response Authentication Mechanism).

SCRAM is a challenge-response authentication protocol that **never transmits the password over the network** — not even in encrypted form. Only a cryptographic derivative is exchanged:

```
1. Client  -->  Broker: "I am admin"
2. Broker  -->  Client: challenge (random nonce + salt + iteration count)
3. Client  -->  Broker: cryptographic proof derived from password + challenge
4. Broker  -->  Client: authentication confirmed (verifies proof without knowing the password)
```

This means that even if the network traffic is intercepted, the password cannot be recovered. The broker stores only a salted hash of the password, never the password itself.

In Strimzi, SCRAM credentials are managed via `KafkaUser` resources — Strimzi handles the SCRAM credential generation and storage automatically.

### Kafka Listeners

The cluster exposes two listeners:

| Listener | Port | Protocol | Authentication |
|---|---|---|---|
| plain | 9092 | SASL_PLAINTEXT | SCRAM-SHA-512 |
| tls | 9093 | SASL_SSL | SCRAM-SHA-512 |

Internal cluster clients (Kafka UI, Kafka Exporter, Jenkins) use port **9092** (SASL_PLAINTEXT).
For production environments, port **9093** (SASL_SSL) should be preferred.

### Kafka Users and ACLs

Users are defined as `KafkaUser` Strimzi resources. Strimzi's User Operator watches these resources and configures SCRAM credentials and ACLs on the brokers automatically.

| User | Role | Permissions |
|---|---|---|
| `admin` | Administrator | All operations on all topics, consumer groups, cluster |
| `producer-user` | Producer | Write, Describe, Create on all topics |
| `consumer-user` | Consumer | Read, Describe on all topics |
| `kafka-connect` | Kafka Connect internal | All on topics, groups, cluster |

ACLs (Access Control Lists) define which operations each user can perform on which resources. The authorization type is `simple` — Kafka's built-in ACL system based on the `kafka-acls.sh` tool, managed declaratively via Strimzi.

### Secret Management Flow

All passwords are managed by Vault and never stored in Git or in `values.yaml`:

```
./deploy.sh
    |
    +--> HashiCorp Vault (dev mode, stores secrets in RAM)
         |
         Paths:
         secret/kafka/users/admin
         secret/kafka/users/producer-user
         secret/kafka/users/consumer-user
         secret/kafka/monitoring/grafana
         secret/kafka/jenkins/admin
              |
              v
         External Secrets Operator
         (syncs every 1h, or on demand)
              |
              +--> Kubernetes Secret: admin-password          (key: password)
              +--> Kubernetes Secret: producer-user-password  (key: password)
              +--> Kubernetes Secret: consumer-user-password  (key: password)
              +--> Kubernetes Secret: grafana-admin-secret    (key: admin-password)
              +--> Kubernetes Secret: jenkins-admin-secret    (key: admin-password)
                        |
                        v
                   Mounted as env vars in pods:
                   Grafana, Jenkins, Kafka UI, Kafka Exporter
                   Referenced by KafkaUser for SCRAM setup
```

### Kafka Connect

Kafka Connect is deployed via a Strimzi `KafkaConnect` resource with a custom build that includes the `connect-file` connector as a base example. It connects to the cluster using SCRAM-SHA-512 authentication on the TLS listener.

To add connectors, edit `helm/values.yaml` under the `kafkaConnect.connectors` section.

### Cruise Control

Cruise Control is deployed alongside the cluster and provides:
- **Partition rebalancing**: moves partitions between brokers to balance storage and traffic load
- **Resource analysis**: tracks CPU, disk, network per broker
- **Rebalancing proposals**: suggests optimal partition assignments

---

## Service Access

| Service | URL | Credentials |
|---|---|---|
| Kafka UI | http://localhost:30080 | none |
| Grafana | http://localhost:30030 | admin / password chosen at deploy |
| Jenkins | http://localhost:32000 | admin / password chosen at deploy |
| Prometheus | http://localhost:30090 | none |
| Vault | http://localhost:30372 | token: `root` |
| AWX | http://localhost:30043 | admin / see below |

```bash
# AWX admin password (auto-generated by AWX Operator)
kubectl get secret awx-admin-password -n kafka-lab -o jsonpath="{.data.password}" | base64 -d && echo
```

---

## Post-Deploy Checklist

### 1. All Pods Running
```bash
kubectl get pods -n kafka-lab
```
All must be `Running` or `Completed`. The `awx-migration-*` pod in `Completed` is normal.

### 2. Kafka Cluster Ready
```bash
kubectl get kafka -n kafka-lab
```
The `READY` column must show `True`.

### 3. External Secrets Synced
```bash
kubectl get externalsecret -n kafka-lab
```
All must have `STATUS=SecretSynced` and `READY=True`.
If they show `SecretSyncedError`:
```bash
./scripts/vault/vault-reinit.sh
```

### 4. Kafka UI — Brokers Visible
Open http://localhost:30080 and click on **Brokers**.
3 brokers must appear (ID 0, 1, 2).

### 5. Grafana — Kafka Dashboard
Open http://localhost:30030 and log in.
The **Kafka Overview** dashboard opens automatically.

### 6. Prometheus — Targets UP
Open http://localhost:30090/targets.
The `kafka-exporter` target must be `UP`.

### 7. Jenkins — 3 Pipelines Present
Open http://localhost:32000 and log in. Three pipelines must be present:
- `01-Kafka-Manage-Topic`
- `02-Kafka-Manage-User`
- `03-Kafka-Cluster-Health`

### 8. AWX — 5 Job Templates Ready
Open http://localhost:30043 and go to **Templates**. Five job templates must be present:
- `Kafka - Health Check`
- `Kafka - Create Topic`
- `Kafka - Manage Users`
- `Kafka - Manage ACL`
- `Kafka - Full Test Suite`

---

## After a Docker Desktop Restart

Vault runs in dev mode — data is stored in RAM and lost on every restart.
When `kubectl get externalsecret -n kafka-lab` shows `SecretSyncedError`:

```bash
./scripts/vault/vault-reinit.sh
```

Restores everything in ~30 seconds.

---

## Useful Commands

```bash
# General status
kubectl get pods -n kafka-lab
kubectl get kafka -n kafka-lab
kubectl get externalsecret -n kafka-lab

# Kafka resources
kubectl get kafkatopic -n kafka-lab
kubectl get kafkauser -n kafka-lab
kubectl logs kafka-cluster-kafka-nodes-0 -n kafka-lab

# Troubleshooting
kubectl describe pod <pod-name> -n kafka-lab
kubectl rollout restart deployment/kafka-exporter -n kafka-lab
```

---

## Project Structure

```
kafka-kube/
├── deploy.sh                          # entry point — installs everything
├── cleanup.sh                         # removes everything
├── helm/                              # main Helm chart
│   ├── Chart.yaml
│   ├── values.yaml                    # centralized configuration
│   └── templates/
│       ├── strimzi/                   # Kafka cluster, users, connect
│       ├── vault/                     # SecretStore + RBAC
│       ├── monitoring/                # Prometheus, Grafana, Kafka Exporter
│       ├── jenkins/                   # Jenkins deployment + RBAC
│       ├── awx/                       # AWX instance
│       └── kafka-ui/                  # Kafka UI
├── ansible/                           # AWX playbooks
│   ├── group_vars/all.yml
│   └── playbooks/
│       ├── kafka_health.yml
│       ├── kafka_create_topic.yml
│       ├── kafka_manage_users.yml
│       ├── kafka_manage_acl.yml
│       └── kafka_full_test.yml
├── jenkins/
│   ├── Dockerfile                     # custom Jenkins image
│   └── pipelines/                     # Groovy pipelines
├── awx-ee/
│   └── Dockerfile                     # custom Execution Environment with kubernetes.core
├── scripts/
│   └── vault/
│       └── vault-reinit.sh            # Vault restore after restart
└── docs/                              # detailed documentation
```

---

## Documentation

| File | Content |
|---|---|
| [INSTALL.md](INSTALL.md) | Manual installation step-by-step |
| [docs/AWX_SETUP.md](docs/AWX_SETUP.md) | Manual AWX configuration |
| [docs/JENKINS_GUIDE.md](docs/JENKINS_GUIDE.md) | Jenkins pipelines usage |
| [docs/VAULT_SETUP_GUIDE.md](docs/VAULT_SETUP_GUIDE.md) | Vault + ESO architecture |
| [docs/guides/KAFKA_DEPLOYMENT.md](docs/guides/KAFKA_DEPLOYMENT.md) | Detailed Kafka deployment |
