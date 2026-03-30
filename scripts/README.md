# Scripts

## vault-reinit.sh

Ripristina Vault dopo un restart del pod.

Vault gira in **dev mode** — i dati sono in RAM e si perdono ad ogni restart.
Quando ESO mostra `SecretSyncedError` o Kafka UI non si connette:

```bash
./scripts/vault/vault-reinit.sh
```

Lo script in ~30 secondi:
1. Riabilita KV engine in Vault
2. Ricarica tutti i secret (legge la password dall'ultimo file passwords, altrimenti la chiede)
3. Riconfigura Kubernetes auth con il CA cert corretto (da `kube-root-ca.crt`)
4. Crea policy e role
5. Forza risync di tutti gli ExternalSecret
6. Riavvia Kafka UI

**Quando usarlo:**
- Dopo riavvio Docker Desktop
- Dopo Mac sleep/wake lungo
- Quando `kubectl get externalsecret -n kafka-lab` mostra `SecretSyncedError`
- Quando Kafka UI mostra errore di autenticazione SASL
