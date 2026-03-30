# AWX Setup — Kafka Lab

> AWX is configured automatically by `./deploy.sh`.
> Use this guide only if you need to reconfigure it manually.

---

## Common Issue: Python `kubernetes` Library Missing

```
Failed to import the required Python library (kubernetes)
```

AWX uses a container (Execution Environment) that by default does NOT have the Python `kubernetes` library. A custom EE must be built — this is already done and available on Docker Hub as `gabrodevops/kafka-ee:1.0.0`.

---

## Step 1: Add Execution Environment

1. **Administration -> Execution Environments -> Add**
2. **Name:** `Kafka EE`
3. **Image:** `gabrodevops/kafka-ee:1.0.0`
4. **Pull:** `Missing`
5. **Save**

---

## Step 2: Configure Project

1. **Projects -> Add**
2. **Name:** `kafka-kube`
3. **Source Control Type:** `Git`
4. **Source Control URL:** `https://github.com/Gabro-devops/kafka-kube.git`
5. **Branch:** `main`
6. **Update Revision on Launch:** enabled
7. **Save** (AWX will automatically download the code)

---

## Step 3: Create Inventory

1. **Inventories -> Add -> Inventory**
2. **Name:** `Kafka Inventory`
3. **Save**

---

## Step 4: Create Kubernetes Credential

```bash
# Get the ServiceAccount token
kubectl -n kafka-lab create token jenkins-admin --duration=8760h
```

1. **Credentials -> Add**
2. **Name:** `Kubernetes Local`
3. **Credential Type:** `OpenShift or Kubernetes API Bearer Token`
4. **Kubernetes API Endpoint:** `https://kubernetes.default.svc`
5. **API Authentication Bearer Token:** (token from the command above)
6. **Verify SSL:** Off
7. **Save**

---

## Step 5: Create Job Templates

### Kafka - Health Check
| Field | Value |
|---|---|
| Name | `Kafka - Health Check` |
| Inventory | `Kafka Inventory` |
| Project | `kafka-kube` |
| Execution Environment | `Kafka EE` |
| Playbook | `ansible/playbooks/kafka_health.yml` |

### Kafka - Create Topic
| Field | Value |
|---|---|
| Name | `Kafka - Create Topic` |
| Inventory | `Kafka Inventory` |
| Project | `kafka-kube` |
| Execution Environment | `Kafka EE` |
| Playbook | `ansible/playbooks/kafka_create_topic.yml` |
| Prompt on Launch | enabled |

### Kafka - Manage Users
| Field | Value |
|---|---|
| Name | `Kafka - Manage Users` |
| Inventory | `Kafka Inventory` |
| Project | `kafka-kube` |
| Execution Environment | `Kafka EE` |
| Playbook | `ansible/playbooks/kafka_manage_users.yml` |
| Prompt on Launch | enabled |

---

## AWX Admin Password

```bash
kubectl get secret awx-admin-password -n kafka-lab \
  -o jsonpath="{.data.password}" | base64 -d && echo ""
```

**URL:** http://localhost:30043
