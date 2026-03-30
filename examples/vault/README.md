# Vault Configuration Examples

This folder contains Vault configuration examples for different scenarios.

## Available Files

### configuration-scenarios.yaml

Contains 9 complete scenarios: LAB/Development, Staging, Production, Multi-Region, Vault Agent Sidecar, Hybrid, Secret Rotation, Multi-Tenant, and Compliance.

## How to Use

Open `configuration-scenarios.yaml` and adapt the configurations to your use case, or copy a section directly into your `helm/values.yaml`.

## Recommended Scenarios

| Scenario | When to use |
|---|---|
| LAB | Local testing, learning |
| Staging | Pre-production, validation |
| Production | Enterprise deployment |
| Multi-Region | DR, geo-distribution |
| Compliance | PCI-DSS, SOC2, GDPR |

## Security Checklist

Before going to production:

- [ ] TLS enabled
- [ ] Vault auto-unsealed
- [ ] Least-privilege policies
- [ ] Audit logging active
- [ ] Backup configured
- [ ] DR tested
- [ ] Monitoring active

## Common Issues

**Vault unreachable from K8s:**
```bash
kubectl run test --rm -it --image=curlimages/curl \
  -- curl http://vault.vault-system.svc:8200/v1/sys/health
```

**External Secrets not syncing:**
```bash
kubectl describe secretstore vault-backend -n kafka-lab
```

**Policy too restrictive:**
```bash
vault token capabilities secret/data/kafka/users/admin
```

For more details: [../../docs/VAULT_SETUP_GUIDE.md](../../docs/VAULT_SETUP_GUIDE.md)
