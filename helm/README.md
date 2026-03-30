# Helm Chart — Kafka Lab

## Prerequisites

- Kubernetes 1.25+
- Strimzi Operator installed (installed by `deploy.sh`)
- External Secrets Operator installed (installed by `deploy.sh`)
- Vault configured (installed by `deploy.sh`)

## Deploy

```bash
# Recommended: use deploy.sh from the project root
./deploy.sh

# Or manually
helm install kafka-lab ./helm -n kafka-lab --timeout 15m
helm upgrade kafka-lab ./helm -n kafka-lab
helm uninstall kafka-lab -n kafka-lab
```

## Configuration

Everything is configurable in `values.yaml`. Components can be enabled/disabled:

```yaml
kafka.enabled: true
kafkaConnect.enabled: true
kafkaExporter.enabled: true   # consumer lag metrics for Grafana
monitoring.enabled: true
jenkins.enabled: true
awx.enabled: true
kafkaUi.enabled: true
vault.enabled: true
```

## Notes

- Passwords are NOT in `values.yaml` — they all come from Vault via ESO
- Kafka Exporter uses `scram-sha512` (no hyphen) — format required by danielqsj/kafka-exporter
- The nodePool is named `kafka-nodes` — Strimzi KRaft pods have the `-nodes` suffix in DNS
