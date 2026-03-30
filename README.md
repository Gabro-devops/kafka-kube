# Kafka Lab — Production-Ready Environment

Ambiente Kafka enterprise-grade su Kubernetes con secret management, CI/CD, monitoring e automazione.

## Stack

| Componente | Tecnologia | URL |
|---|---|---|
| Kafka Cluster | Apache Kafka 4.1.0 · KRaft · 3 broker | interno |
| Secret Management | HashiCorp Vault + External Secrets Operator | http://localhost:30372 |
| Kafka UI | Kafka UI | http://localhost:30080 |
| Monitoring | Prometheus + Grafana + Kafka Exporter | :30090 / :30030 |
| CI/CD | Jenkins | http://localhost:32000 |
| Automation | AWX (Ansible Tower OSS) | http://localhost:30043 |
| Data Integration | Kafka Connect | interno |

---

## Quick Start

```bash
./deploy.sh # installa tutto (~15-20 minuti)
./cleanup.sh # rimuove tutto
```

Lo script chiede una password unica usata per tutti i servizi.
Le credenziali vengono salvate in `scripts/vault/vault-passwords-TIMESTAMP.txt`.

---

## Accesso ai Servizi

| Servizio | URL | Credenziali |
|---|---|---|
| Kafka UI | http://localhost:30080 | — |
| Grafana | http://localhost:30030 | admin / password scelta nel deploy |
| Jenkins | http://localhost:32000 | admin / password scelta nel deploy |
| Prometheus | http://localhost:30090 | — |
| Vault | http://localhost:30372 | token: `root` |
| AWX | http://localhost:30043 | admin / vedi sotto |

```bash
# Password AWX (generata automaticamente)
kubectl get secret awx-admin-password -n kafka-lab -o jsonpath="{.data.password}" | base64 -d
```

---

## Checklist Post-Deploy

Dopo il deploy verifica questi punti nell'ordine indicato:

### 1. Kubernetes — Tutti i Pod Running
```bash
kubectl get pods -n kafka-lab
```
**Cosa controllare:** tutti i pod devono essere in stato `Running` o `Completed`.
Se qualcuno è in `CrashLoopBackOff`, aspetta 2-3 minuti e ricontrolla.
Il pod `awx-migration-*` deve essere `Completed` — è normale.

### 2. Kafka Cluster Ready
```bash
kubectl get kafka -n kafka-lab
```
**Cosa controllare:** la colonna `READY` deve mostrare `True`.
Se è vuota, Strimzi sta ancora creando i broker — aspetta.

### 3. External Secrets Sincronizzati
```bash
kubectl get externalsecret -n kafka-lab
```
**Cosa controllare:** tutti devono avere `READY=True` e `STATUS=SecretSynced`.
Se mostrano `SecretSyncedError`, esegui:
```bash
./scripts/vault/vault-reinit.sh
```

### 4. Kafka UI — Broker Visibili
Apri http://localhost:30080 -> clicca su **Brokers**.
**Cosa controllare:** devono comparire 3 broker (ID 0, 1, 2).
Se la pagina rimane in caricamento, i broker non sono ancora pronti.

### 5. Grafana — Dashboard Kafka
Apri http://localhost:30030 -> login con `admin` / tua password.
**Cosa controllare:** la dashboard **Kafka Overview** deve aprirsi automaticamente.
Deve mostrare i grafici: Messages In, Bytes In, Consumer Lag, Topic Partitions.
Se i grafici sono vuoti, Prometheus sta ancora raccogliendo le prime metriche — aspetta 2-3 minuti.

### 6. Prometheus — Target UP
Apri http://localhost:30090/targets.
**Cosa controllare:** i target `kafka` e `kafka-exporter` devono essere `UP`.
Se sono `DOWN`, il kafka-exporter non è ancora connesso ai broker.
```bash
kubectl rollout restart deployment/kafka-exporter -n kafka-lab
```

### 7. Jenkins — Pipeline Presenti
Apri http://localhost:32000 -> login con `admin` / tua password.
**Cosa controllare:** devono essere presenti 3 pipeline:
- `01-Kafka-Manage-Topic`
- `02-Kafka-Manage-User`
- `03-Kafka-Cluster-Health`

Se non compaiono, Jenkins sta ancora caricando la configurazione — aspetta 2-3 minuti e ricarica la pagina.

### 8. AWX — Job Templates Pronti
Apri http://localhost:30043 -> login con `admin` / password AWX.
Vai in **Templates**.
**Cosa controllare:** devono essere presenti 5 Job Templates:
- `Kafka - Health Check`
- `Kafka - Create Topic`
- `Kafka - Manage Users`
- `Kafka - Manage ACL`
- `Kafka - Full Test Suite`

Se non compaiono, la configurazione automatica non è riuscita. Vai in **Projects -> kafka-kube** e premi il tasto **Sync**. Poi rilancia `./deploy.sh` solo la parte AWX o configura manualmente seguendo `docs/AWX_SETUP.md`.

**Cosa controllare anche:**
- **Projects -> kafka-kube** -> status deve essere `Successful`
- **Credentials -> Kafka Admin Credential** -> deve esistere
- **Execution Environments -> Kafka EE** -> deve esistere

---

## Dopo un Restart di Docker Desktop

Vault gira in dev mode — i dati sono in RAM e si perdono ad ogni restart.
Quando `kubectl get externalsecret -n kafka-lab` mostra `SecretSyncedError`:

```bash
./scripts/vault/vault-reinit.sh
```

Ripristina tutto in ~30 secondi.

---

## Comandi Utili

```bash
kubectl get pods -n kafka-lab # status cluster
kubectl get externalsecret -n kafka-lab # ESO sincronizzato?
kubectl get kafkatopic -n kafka-lab # topic esistenti
kubectl get kafkauser -n kafka-lab # utenti Kafka
kubectl logs kafka-cluster-kafka-nodes-0 -n kafka-lab # log broker
```

---

## Documentazione

| File | Contenuto |
|---|---|
| [INSTALL.md](INSTALL.md) | Installazione manuale step-by-step |
| [docs/AWX_SETUP.md](docs/AWX_SETUP.md) | Configurazione AWX manuale |
| [docs/JENKINS_GUIDE.md](docs/JENKINS_GUIDE.md) | Uso pipeline Jenkins |
| [docs/VAULT_SETUP_GUIDE.md](docs/VAULT_SETUP_GUIDE.md) | Architettura Vault + ESO |
| [docs/guides/KAFKA_DEPLOYMENT.md](docs/guides/KAFKA_DEPLOYMENT.md) | Deployment Kafka dettagliato |
| [esercizi/](esercizi/) | Esercizi pratici Kafka |
