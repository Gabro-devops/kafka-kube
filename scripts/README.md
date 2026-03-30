# Scripts

## vault-reinit.sh

Restores Vault after a pod restart.

Vault runs in **dev mode** — data is stored in RAM and lost on every restart.
When ESO shows `SecretSyncedError` or Kafka UI cannot connect:

```bash
./scripts/vault/vault-reinit.sh
```

The script completes in ~30 seconds:
1. Re-enables KV engine in Vault
2. Reloads all secrets (reads the password from the latest passwords file, or prompts if not found)
3. Reconfigures Kubernetes auth with the correct CA cert (from `kube-root-ca.crt`)
4. Creates policy and role
5. Forces resync of all ExternalSecrets
6. Restarts Kafka UI, Grafana, Jenkins, and Kafka Exporter

**When to use it:**
- After Docker Desktop restart
- After a long Mac sleep/wake cycle
- When `kubectl get externalsecret -n kafka-lab` shows `SecretSyncedError`
- When Kafka UI shows a SASL authentication error
