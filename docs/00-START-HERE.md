# Start Here

Ambiente Kafka enterprise-grade su Kubernetes. Tre pilastri: cluster Kafka gestito da Strimzi, secret gestiti da Vault + ESO, automazione tramite Jenkins e AWX.

---

## Deploy

```bash
./deploy.sh # installa tutto
./cleanup.sh # rimuove tutto
```

---

## Dopo il Deploy

**1. Verifica:**
```bash
kubectl get pods -n kafka-lab
kubectl get externalsecret -n kafka-lab # tutti True
```

**2. Apri le UI:**
- Kafka UI -> http://localhost:30080
- Grafana -> http://localhost:30030 -> importa dashboard ID `7589`
- Jenkins -> http://localhost:32000
- AWX -> http://localhost:30043

**3. Configura AWX** (una tantum, ~10 minuti):
Segui [AWX_SETUP.md](AWX_SETUP.md)

---

## Dopo un Restart di Docker Desktop

```bash
./scripts/vault/vault-reinit.sh
```

---

## Struttura

```
kafka-lab-clean/
 deploy.sh # punto di ingresso
 cleanup.sh
 helm/ # tutto il cluster come Helm chart
 values.yaml # configurazione centralizzata
 templates/
 strimzi/ # Kafka cluster, utenti, connect
 vault/ # ESO SecretStore + RBAC
 monitoring/ # Prometheus, Grafana, Kafka Exporter
 jenkins/
 awx/
 kafka-ui/
 ansible/ # playbook AWX
 jenkins/ # Dockerfile + pipeline Groovy
 awx-ee/ # Execution Environment custom
 scripts/vault/
 vault-reinit.sh # ripristino Vault dopo restart
 docs/ # documentazione
 esercizi/ # materiale di studio Kafka
```

---

## Documentazione

| File | Quando leggerlo |
|---|---|
| [INSTALL.md](../INSTALL.md) | Vuoi capire i singoli step del deploy |
| [VAULT_SETUP_GUIDE.md](VAULT_SETUP_GUIDE.md) | Vuoi capire Vault + ESO |
| [JENKINS_GUIDE.md](JENKINS_GUIDE.md) | Vuoi usare le pipeline Jenkins |
| [AWX_SETUP.md](AWX_SETUP.md) | Devi configurare AWX |
| [guides/KAFKA_DEPLOYMENT.md](guides/KAFKA_DEPLOYMENT.md) | Deployment Kafka dettagliato |

---

## Esercizi Kafka

Tutto il materiale di studio è in `esercizi/`:

| File | Contenuto |
|---|---|
| CORSO_KAFKA_SYSADMIN_MOD1.md | Basi Kafka |
| CORSO_COMPLETO_KAFKA_SYSADMIN_60_ESERCIZI.md | 60 esercizi guidati |
| ESERCIZI_GUIDATI_COMPLETI.md | Scenari completi |
| KAFKA_CONNECT_GUIDE.md | Kafka Connect e CDC |
| *.yaml | Risorse Kubernetes pronte all'uso |
