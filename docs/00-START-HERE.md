# Start Here

Enterprise-grade Kafka environment on Kubernetes. Three pillars: Kafka cluster managed by Strimzi, secrets managed by Vault + ESO, automation via Jenkins and AWX.

---

## Deploy

```bash
./deploy.sh      # install everything
./cleanup.sh     # remove everything
```

---

## After Deploy

**1. Verify:**
```bash
kubectl get pods -n kafka-lab
kubectl get externalsecret -n kafka-lab   # all True
```

**2. Open the UIs:**
- Kafka UI -> http://localhost:30080
- Grafana -> http://localhost:30030
- Jenkins -> http://localhost:32000
- AWX -> http://localhost:30043

---

## After a Docker Desktop Restart

```bash
./scripts/vault/vault-reinit.sh
```

---

## Project Structure

```
kafka-kube/
├── deploy.sh                     # entry point
├── cleanup.sh
├── helm/                         # entire cluster as a Helm chart
│   ├── values.yaml               # centralized configuration
│   └── templates/
│       ├── strimzi/              # Kafka cluster, users, connect
│       ├── vault/                # ESO SecretStore + RBAC
│       ├── monitoring/           # Prometheus, Grafana, Kafka Exporter
│       ├── jenkins/
│       ├── awx/
│       └── kafka-ui/
├── ansible/                      # AWX playbooks
├── jenkins/                      # Dockerfile + Groovy pipelines
├── awx-ee/                       # Custom Execution Environment
├── scripts/vault/
│   └── vault-reinit.sh           # Vault restore after restart
└── docs/                         # documentation
```

---

## Documentation

| File | When to read |
|---|---|
| [INSTALL.md](../INSTALL.md) | You want to understand the individual deploy steps |
| [VAULT_SETUP_GUIDE.md](VAULT_SETUP_GUIDE.md) | You want to understand Vault + ESO |
| [JENKINS_GUIDE.md](JENKINS_GUIDE.md) | You want to use Jenkins pipelines |
| [AWX_SETUP.md](AWX_SETUP.md) | You need to configure AWX manually |
| [guides/KAFKA_DEPLOYMENT.md](guides/KAFKA_DEPLOYMENT.md) | Detailed Kafka deployment |
