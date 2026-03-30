# Vault Configuration Examples

Questa cartella contiene esempi di configurazione Vault per diversi scenari.

## File Disponibili

### configuration-scenarios.yaml

**Contiene 9 scenari completi:**

1. **LAB / Development** - Vault dev mode, testing rapido
2. **Staging** - HA con persistent storage
3. **Production** - Vault esterno, TLS, AppRole
4. **Multi-Region** - Disaster recovery con replication
5. **Vault Agent Sidecar** - Caching locale
6. **Hybrid** - Vault + fallback K8s secrets
7. **Secret Rotation** - Rotation automatica
8. **Multi-Tenant** - Team separati
9. **Compliance** - PCI, audit logging

## Come Usare

### Opzione 1: Copia sezione nel tuo values.yaml

```bash
# Esempio: Config per staging
cat configuration-scenarios.yaml | \
 sed -n '/^staging_config:/,/^# ---/p' >> ../helm/values.yaml
```

### Opzione 2: Usa come reference

Apri `configuration-scenarios.yaml` e adatta le configurazioni al tuo caso.

### Opzione 3: Deploy environment specifico

```bash
# Crea values-staging.yaml
cat > values-staging.yaml <<EOF
vault:
 enabled: true
 address: "https://vault.vault-system.svc.cluster.local:8200"
 # ... copia da staging_config
EOF

# Deploy
helm install kafka-lab ../helm -f values-staging.yaml
```

## Guide Correlate

- **Setup Vault completo:** [../../docs/guides/VAULT_SETUP_GUIDE.md](../../docs/guides/VAULT_SETUP_GUIDE.md)
- **Troubleshooting:** [../../docs/guides/VAULT_SETUP_GUIDE.md#troubleshooting](../../docs/guides/VAULT_SETUP_GUIDE.md#troubleshooting)

## Scenari Consigliati

| Scenario | Quando usarlo |
|----------|---------------|
| LAB | Testing locale, learning |
| Staging | Pre-produzione, validation |
| Production | Deploy enterprise |
| Multi-Region | DR, geo-distribution |
| Compliance | PCI-DSS, SOC2, GDPR |

## Pro Tips

1. **Inizia da LAB** - Testa prima in dev mode
2. **Adatta, non copia** - Ogni ambiente è unico
3. **Testa failover** - Simula failure scenarios
4. **Documenta policy** - Mantieni policy in Git
5. **Monitora** - Abilita metrics Vault

## Security Checklist

Prima di andare in produzione:

- [ ] TLS abilitato
- [ ] Vault unsealed automaticamente
- [ ] Policy least-privilege
- [ ] Audit logging attivo
- [ ] Backup configurato
- [ ] DR testato
- [ ] Monitoring attivo
- [ ] Incident response plan

## Problemi Comuni

### Vault non raggiungibile da K8s

```bash
# Test connectivity
kubectl run test --rm -it --image=curlimages/curl \
 -- curl http://vault.vault-system.svc:8200/v1/sys/health
```

### External Secrets non sincronizzano

```bash
# Verifica SecretStore
kubectl describe secretstore vault-backend

# Logs ESO
kubectl -n external-secrets-system logs -l app.kubernetes.io/name=external-secrets
```

### Policy troppo restrittive

```bash
# Test capabilities
vault token capabilities secret/data/kafka/users/admin
```

---

**Domande?** -> [VAULT_SETUP_GUIDE.md](../../docs/guides/VAULT_SETUP_GUIDE.md)
