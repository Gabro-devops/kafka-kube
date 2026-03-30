# Helm Chart — Kafka Lab

## Prerequisiti

- Kubernetes 1.25+
- Strimzi Operator installato (lo installa `deploy.sh`)
- External Secrets Operator installato (lo installa `deploy.sh`)
- Vault configurato (lo installa `deploy.sh`)

## Deploy

```bash
# Metodo consigliato: usa deploy.sh dalla root del progetto
./deploy.sh

# Oppure manualmente
helm install kafka-lab ./helm -n kafka-lab --timeout 15m
helm upgrade kafka-lab ./helm -n kafka-lab
helm uninstall kafka-lab -n kafka-lab
```

## Configurazione

Tutto è configurabile in `values.yaml`. Componenti abilitabili/disabilitabili:

```yaml
kafka.enabled: true
kafkaConnect.enabled: true
kafkaExporter.enabled: true # metriche consumer lag per Grafana
monitoring.enabled: true
jenkins.enabled: true
awx.enabled: true
kafkaUi.enabled: true
vault.enabled: true
```

## Note

- Le password NON sono in `values.yaml` — vengono tutte da Vault tramite ESO
- Il Kafka Exporter usa `scram-sha512` (senza trattino) — formato richiesto da danielqsj/kafka-exporter
- Il nodePool si chiama `kafka-nodes` — i pod Strimzi KRaft hanno il suffisso `-nodes` nel DNS
