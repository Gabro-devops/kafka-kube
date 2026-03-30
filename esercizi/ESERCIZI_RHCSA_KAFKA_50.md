# ESERCIZI RHCSA APPLICATI A KAFKA
## Competenze Linux per Kafka SysAdmin su VM/Bare Metal

---

# INDICE

| # | Argomento RHCSA | Applicazione Kafka |
|---|-----------------|-------------------|
| 1-5 | Gestione Utenti e Permessi | Utente kafka, permessi directory |
| 6-10 | Systemd e Servizi | Kafka service, dipendenze, target |
| 11-15 | Storage e Filesystem | LVM per Kafka data, mount, quota |
| 16-20 | Networking | Firewall, SELinux, bonding |
| 21-25 | Processi e Performance | Tuning, cgroups, nice |
| 26-30 | Logging e Troubleshooting | Journald, rsyslog, log rotation |
| 31-35 | Automazione e Scripting | Bash, cron, at |
| 36-40 | Security | SSH, sudo, audit |
| 41-45 | Backup e Recovery | tar, rsync, rescue mode |
| 46-50 | Avanzati | Containers, Ansible, Kickstart |

---

# 
# SEZIONE 1: GESTIONE UTENTI E PERMESSI (Esercizi 1-5)
# 

## ESERCIZIO 1: Creare Utente kafka con Configurazione Sicura
**Competenze RHCSA:** useradd, usermod, /etc/passwd, /etc/shadow

### Scenario
Devi creare l'utente di sistema per eseguire Kafka in modo sicuro.

### Comandi
```bash
# Crea utente di sistema (no home, no login shell)
sudo useradd -r -s /sbin/nologin -c "Apache Kafka Service Account" kafka

# Verifica
grep kafka /etc/passwd
# Output: kafka:x:995:993:Apache Kafka Service Account:/home/kafka:/sbin/nologin

# Verifica che non possa fare login
sudo su - kafka
# Output: This account is currently not available.

# Se devi permettere login temporaneo per debug:
sudo usermod -s /bin/bash kafka
# Dopo il debug, rimetti:
sudo usermod -s /sbin/nologin kafka
```

### Spiegazione
- `-r`: utente di sistema (UID < 1000)
- `-s /sbin/nologin`: non può fare login interattivo
- Questo è uno standard di sicurezza per i servizi

---

## ESERCIZIO 2: Configurare Directory e Permessi Kafka
**Competenze RHCSA:** mkdir, chown, chmod, ACL (setfacl/getfacl)

### Scenario
Creare la struttura directory per Kafka con permessi corretti.

### Comandi
```bash
# Crea struttura directory
sudo mkdir -p /opt/kafka
sudo mkdir -p /var/lib/kafka/data
sudo mkdir -p /var/log/kafka
sudo mkdir -p /etc/kafka

# Imposta proprietario
sudo chown -R kafka:kafka /opt/kafka
sudo chown -R kafka:kafka /var/lib/kafka
sudo chown -R kafka:kafka /var/log/kafka
sudo chown -R kafka:kafka /etc/kafka

# Imposta permessi
# /opt/kafka: rwxr-xr-x (755) - binari leggibili da tutti
sudo chmod 755 /opt/kafka

# /var/lib/kafka: rwx------ (700) - dati solo per kafka
sudo chmod 700 /var/lib/kafka
sudo chmod 700 /var/lib/kafka/data

# /var/log/kafka: rwxr-x--- (750) - log leggibili dal gruppo
sudo chmod 750 /var/log/kafka

# /etc/kafka: rwxr-x--- (750) - config con credenziali
sudo chmod 750 /etc/kafka

# Verifica
ls -la /var/lib/kafka
ls -la /var/log/kafka
```

### Esercizio Extra: ACL per Team di Monitoring
```bash
# Permetti al gruppo "monitoring" di leggere i log
sudo setfacl -R -m g:monitoring:rx /var/log/kafka
sudo setfacl -R -d -m g:monitoring:rx /var/log/kafka # Default per nuovi file

# Verifica ACL
getfacl /var/log/kafka
```

---

## ESERCIZIO 3: Gestire Gruppi per Accesso Kafka
**Competenze RHCSA:** groupadd, usermod -aG, /etc/group

### Scenario
Creare gruppi per diversi livelli di accesso a Kafka.

### Comandi
```bash
# Crea gruppi
sudo groupadd kafka-admin # Amministratori Kafka
sudo groupadd kafka-ops # Operatori (restart, log)
sudo groupadd kafka-readonly # Solo lettura log

# Aggiungi utenti ai gruppi
sudo usermod -aG kafka-admin admin_user
sudo usermod -aG kafka-ops operator_user
sudo usermod -aG kafka-readonly monitoring_user

# L'utente kafka deve essere nel suo gruppo
sudo usermod -aG kafka kafka

# Verifica gruppi di un utente
groups admin_user
id admin_user

# Lista membri di un gruppo
getent group kafka-admin
```

### Configura Sudo per Gruppi
```bash
# Crea file sudoers per Kafka
sudo visudo -f /etc/sudoers.d/kafka

# Contenuto:
# kafka-admin può fare tutto su kafka
%kafka-admin ALL=(ALL) NOPASSWD: /bin/systemctl * kafka, /opt/kafka/bin/*

# kafka-ops può solo restart e vedere status
%kafka-ops ALL=(ALL) NOPASSWD: /bin/systemctl restart kafka, /bin/systemctl status kafka, /bin/journalctl -u kafka

# kafka-readonly può solo vedere log
%kafka-readonly ALL=(ALL) NOPASSWD: /bin/journalctl -u kafka --no-pager
```

---

## ESERCIZIO 4: Umask e Permessi Default per Kafka
**Competenze RHCSA:** umask, /etc/profile.d/, permessi default

### Scenario
I file creati da Kafka devono avere permessi restrittivi.

### Comandi
```bash
# Verifica umask attuale
umask

# Crea script per impostare umask per kafka
sudo tee /etc/profile.d/kafka-umask.sh << 'EOF'
# Umask restrittivo per utente kafka
if [ "$(whoami)" = "kafka" ]; then
 umask 0077 # File: 600, Directory: 700
fi
EOF

sudo chmod 644 /etc/profile.d/kafka-umask.sh

# Nel systemd service, aggiungi:
# UMask=0077
```

### Test
```bash
# Come kafka (se ha shell temporaneamente)
sudo -u kafka bash -c 'umask; touch /tmp/test-kafka-file; ls -la /tmp/test-kafka-file'
# Il file dovrebbe essere -rw-------
```

---

## ESERCIZIO 5: Limitare Risorse Utente kafka con limits.conf
**Competenze RHCSA:** /etc/security/limits.conf, ulimit

### Scenario
Kafka richiede molti file descriptor aperti. Configura i limiti.

### Comandi
```bash
# Verifica limiti attuali
ulimit -a
ulimit -n # File descriptor

# Configura limiti per kafka
sudo tee /etc/security/limits.d/kafka.conf << 'EOF'
# Limiti per Apache Kafka
kafka soft nofile 100000
kafka hard nofile 100000
kafka soft nproc 32768
kafka hard nproc 32768
kafka soft memlock unlimited
kafka hard memlock unlimited
EOF

# Verifica (richiede nuovo login)
sudo -u kafka bash -c 'ulimit -n'

# Nel systemd service, aggiungi anche:
# LimitNOFILE=100000
# LimitNPROC=32768
```

### Spiegazione Limiti Kafka
| Limite | Valore | Motivo |
|--------|--------|--------|
| nofile | 100000 | Kafka apre molti file (log segment, index) |
| nproc | 32768 | Thread pool per I/O |
| memlock | unlimited | Per memory-mapped files |

---

# 
# SEZIONE 2: SYSTEMD E SERVIZI (Esercizi 6-10)
# 

## ESERCIZIO 6: Creare Systemd Service per Kafka
**Competenze RHCSA:** systemctl, unit file, [Service], [Install]

### Scenario
Creare un service file completo per Kafka con tutte le best practice.

### Comandi
```bash
sudo tee /etc/systemd/system/kafka.service << 'EOF'
[Unit]
Description=Apache Kafka Message Broker
Documentation=https://kafka.apache.org/documentation/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=kafka
Group=kafka

# Directory di lavoro
WorkingDirectory=/opt/kafka

# Comando di avvio
ExecStart=/opt/kafka/bin/kafka-server-start.sh /etc/kafka/server.properties

# Comando di stop (graceful)
ExecStop=/opt/kafka/bin/kafka-server-stop.sh

# Restart automatico
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# Timeout (Kafka può essere lento a partire)
TimeoutStartSec=180
TimeoutStopSec=120

# Limiti risorse
LimitNOFILE=100000
LimitNPROC=32768

# Ambiente Java
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk"
Environment="KAFKA_HEAP_OPTS=-Xms1g -Xmx1g"
Environment="KAFKA_JVM_PERFORMANCE_OPTS=-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35"
Environment="KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:/etc/kafka/log4j.properties"

# Security
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Ricarica systemd
sudo systemctl daemon-reload

# Abilita e avvia
sudo systemctl enable kafka
sudo systemctl start kafka

# Verifica
sudo systemctl status kafka
```

---

## ESERCIZIO 7: Gestire Dipendenze tra Servizi
**Competenze RHCSA:** After=, Requires=, Wants=, BindsTo=

### Scenario
Se hai Kafka Connect che dipende da Kafka, configura le dipendenze.

### Comandi
```bash
# Kafka Connect service con dipendenza da Kafka
sudo tee /etc/systemd/system/kafka-connect.service << 'EOF'
[Unit]
Description=Kafka Connect Distributed
Documentation=https://kafka.apache.org/documentation/
# Dipendenze
After=kafka.service
Requires=kafka.service
# Se kafka muore, muore anche connect
BindsTo=kafka.service

[Service]
Type=simple
User=kafka
Group=kafka
ExecStart=/opt/kafka/bin/connect-distributed.sh /etc/kafka/connect-distributed.properties
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=10

Environment="KAFKA_HEAP_OPTS=-Xms512m -Xmx512m"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

# Ora quando avvii kafka-connect, parte prima kafka
sudo systemctl start kafka-connect

# Se stoppi kafka, si ferma anche connect
sudo systemctl stop kafka
```

---

## ESERCIZIO 8: Creare Target per Stack Kafka
**Competenze RHCSA:** target unit, systemctl isolate

### Scenario
Creare un target che avvia tutto lo stack Kafka insieme.

### Comandi
```bash
# Crea target
sudo tee /etc/systemd/system/kafka-stack.target << 'EOF'
[Unit]
Description=Kafka Full Stack (Broker + Connect)
Requires=kafka.service
Wants=kafka-connect.service
After=kafka.service kafka-connect.service

[Install]
WantedBy=multi-user.target
EOF

# Modifica i service per far parte del target
# Aggiungi in [Install] di kafka.service e kafka-connect.service:
# WantedBy=kafka-stack.target

sudo systemctl daemon-reload

# Avvia tutto lo stack
sudo systemctl start kafka-stack.target

# Verifica
sudo systemctl list-dependencies kafka-stack.target
```

---

## ESERCIZIO 9: Journald e Log di Kafka
**Competenze RHCSA:** journalctl, /etc/systemd/journald.conf

### Scenario
Configurare journald per mantenere log Kafka persistenti.

### Comandi
```bash
# Vedi log Kafka
sudo journalctl -u kafka -f # Follow
sudo journalctl -u kafka --since "1 hour ago" # Ultima ora
sudo journalctl -u kafka --since today # Oggi
sudo journalctl -u kafka -p err # Solo errori
sudo journalctl -u kafka -o json # Formato JSON

# Configura persistenza log
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal

# Modifica /etc/systemd/journald.conf
sudo tee -a /etc/systemd/journald.conf << 'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=2G
SystemMaxFileSize=100M
MaxRetentionSec=1month
EOF

# Riavvia journald
sudo systemctl restart systemd-journald

# Verifica spazio usato
journalctl --disk-usage
```

---

## ESERCIZIO 10: Troubleshooting Avvio Servizio
**Competenze RHCSA:** systemctl status, journalctl, systemd-analyze

### Scenario
Kafka non parte. Diagnostica il problema.

### Comandi
```bash
# Step 1: Status dettagliato
sudo systemctl status kafka -l

# Step 2: Log recenti
sudo journalctl -u kafka --since "5 minutes ago" --no-pager

# Step 3: Verifica errori di configurazione
sudo systemd-analyze verify /etc/systemd/system/kafka.service

# Step 4: Tempo di avvio
sudo systemd-analyze blame | grep kafka

# Step 5: Catena di dipendenze
sudo systemd-analyze critical-chain kafka.service

# Step 6: Problemi comuni
# a) Verifica che l'utente esista
id kafka

# b) Verifica permessi directory
ls -la /var/lib/kafka/data
ls -la /etc/kafka/server.properties

# c) Verifica che Java sia installato
java -version
which java

# d) Verifica porta già in uso
sudo ss -tlnp | grep 9092

# e) Prova ad avviare manualmente
sudo -u kafka /opt/kafka/bin/kafka-server-start.sh /etc/kafka/server.properties
```

---

# 
# SEZIONE 3: STORAGE E FILESYSTEM (Esercizi 11-15)
# 

## ESERCIZIO 11: Creare LVM per Kafka Data
**Competenze RHCSA:** pvcreate, vgcreate, lvcreate, mkfs, mount

### Scenario
Hai un nuovo disco /dev/sdb da 100GB per i dati Kafka.

### Comandi
```bash
# Verifica disco
lsblk
sudo fdisk -l /dev/sdb

# Crea Physical Volume
sudo pvcreate /dev/sdb
sudo pvs

# Crea Volume Group
sudo vgcreate vg_kafka /dev/sdb
sudo vgs

# Crea Logical Volume (usa 90% per lasciare spazio a snapshot)
sudo lvcreate -l 90%VG -n lv_kafka_data vg_kafka
sudo lvs

# Crea filesystem XFS (migliore per Kafka)
sudo mkfs.xfs /dev/vg_kafka/lv_kafka_data

# Crea mount point
sudo mkdir -p /var/lib/kafka/data

# Monta temporaneamente per test
sudo mount /dev/vg_kafka/lv_kafka_data /var/lib/kafka/data

# Verifica
df -h /var/lib/kafka/data
```

---

## ESERCIZIO 12: Configurare /etc/fstab per Mount Persistente
**Competenze RHCSA:** /etc/fstab, UUID, mount options

### Scenario
Rendere il mount permanente con opzioni ottimizzate per Kafka.

### Comandi
```bash
# Trova UUID del volume
sudo blkid /dev/vg_kafka/lv_kafka_data

# Aggiungi a fstab
sudo tee -a /etc/fstab << 'EOF'
# Kafka Data Volume
/dev/vg_kafka/lv_kafka_data /var/lib/kafka/data xfs defaults,noatime,nodiratime 0 2
EOF

# Spiegazione opzioni:
# noatime: non aggiorna access time (performance)
# nodiratime: non aggiorna access time directory
# 0 2: dump=0, fsck order=2

# Test senza reboot
sudo umount /var/lib/kafka/data
sudo mount -a

# Verifica
mount | grep kafka
df -h /var/lib/kafka/data

# Fix permessi dopo mount
sudo chown -R kafka:kafka /var/lib/kafka/data
```

---

## ESERCIZIO 13: Estendere LVM Quando il Disco si Riempie
**Competenze RHCSA:** lvextend, xfs_growfs

### Scenario
Il disco Kafka è al 90%. Hai aggiunto un nuovo disco /dev/sdc.

### Comandi
```bash
# Verifica spazio attuale
df -h /var/lib/kafka/data

# Aggiungi nuovo disco al VG
sudo pvcreate /dev/sdc
sudo vgextend vg_kafka /dev/sdc

# Verifica
sudo vgs
sudo pvs

# Estendi LV (aggiungi 50GB)
sudo lvextend -L +50G /dev/vg_kafka/lv_kafka_data

# Oppure usa tutto lo spazio disponibile
sudo lvextend -l +100%FREE /dev/vg_kafka/lv_kafka_data

# Estendi filesystem XFS (online, no downtime!)
sudo xfs_growfs /var/lib/kafka/data

# Verifica
df -h /var/lib/kafka/data
```

---

## ESERCIZIO 14: Configurare Disk Quota per Kafka
**Competenze RHCSA:** quota, edquota, repquota

### Scenario
Limitare lo spazio che Kafka può usare per evitare che riempia il disco.

### Comandi
```bash
# Installa quota
sudo dnf install -y quota

# Abilita quota nel mount (modifica fstab)
# Cambia: defaults,noatime,nodiratime
# In: defaults,noatime,nodiratime,usrquota,grpquota

# Rimonta
sudo mount -o remount /var/lib/kafka/data

# Crea file quota
sudo quotacheck -cug /var/lib/kafka/data
sudo quotaon /var/lib/kafka/data

# Imposta quota per utente kafka (80GB soft, 90GB hard)
sudo setquota -u kafka 83886080 94371840 0 0 /var/lib/kafka/data
# Valori in KB: 80GB=83886080KB, 90GB=94371840KB

# Verifica
sudo quota -u kafka
sudo repquota /var/lib/kafka/data
```

---

## ESERCIZIO 15: Monitorare I/O Disco
**Competenze RHCSA:** iostat, iotop, /proc/diskstats

### Scenario
Kafka è lento. Verifica se il disco è il collo di bottiglia.

### Comandi
```bash
# Installa strumenti
sudo dnf install -y sysstat iotop

# iostat - statistiche I/O
iostat -xz 1 5

# Output importante:
# %util: percentuale utilizzo disco (>80% = problema)
# await: tempo medio attesa I/O in ms (>10ms = lento)
# r/s, w/s: operazioni al secondo

# iotop - processi che fanno più I/O
sudo iotop -o

# Monitoraggio continuo
watch -n 1 'iostat -xz 1 1 | tail -10'

# Per Kafka, verifica il disco dove sono i dati
iostat -xz /dev/mapper/vg_kafka-lv_kafka_data 1

# Se il disco è saturo, considera:
# 1. SSD invece di HDD
# 2. Più dischi con RAID
# 3. Configurazione log.dirs su più dischi
```

---

# 
# SEZIONE 4: NETWORKING (Esercizi 16-20)
# 

## ESERCIZIO 16: Configurare Firewall per Kafka
**Competenze RHCSA:** firewall-cmd, zones, services, rich rules

### Scenario
Aprire solo le porte necessarie per Kafka.

### Comandi
```bash
# Verifica stato firewall
sudo systemctl status firewalld
sudo firewall-cmd --state

# Vedi zone attiva
sudo firewall-cmd --get-active-zones

# Metodo 1: Apri porte singole
sudo firewall-cmd --permanent --add-port=9092/tcp # Client
sudo firewall-cmd --permanent --add-port=9093/tcp # Controller (KRaft)
sudo firewall-cmd --permanent --add-port=9999/tcp # JMX (opzionale)

# Metodo 2: Crea servizio custom Kafka
sudo tee /etc/firewalld/services/kafka.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
 <short>Kafka</short>
 <description>Apache Kafka Message Broker</description>
 <port protocol="tcp" port="9092"/>
 <port protocol="tcp" port="9093"/>
</service>
EOF

sudo firewall-cmd --reload
sudo firewall-cmd --permanent --add-service=kafka

# Ricarica
sudo firewall-cmd --reload

# Verifica
sudo firewall-cmd --list-all
```

---

## ESERCIZIO 17: Limitare Accesso per IP con Rich Rules
**Competenze RHCSA:** rich rules, source address

### Scenario
Kafka deve accettare connessioni solo dalla rete interna 10.0.0.0/8.

### Comandi
```bash
# Rimuovi apertura generica
sudo firewall-cmd --permanent --remove-port=9092/tcp

# Aggiungi rich rule con filtro IP
sudo firewall-cmd --permanent --add-rich-rule='
 rule family="ipv4"
 source address="10.0.0.0/8"
 port protocol="tcp" port="9092"
 accept'

# Per controller quorum (solo tra broker)
sudo firewall-cmd --permanent --add-rich-rule='
 rule family="ipv4"
 source address="10.0.1.0/24"
 port protocol="tcp" port="9093"
 accept'

# Ricarica
sudo firewall-cmd --reload

# Verifica
sudo firewall-cmd --list-rich-rules

# Test da un IP non autorizzato
nc -zv kafka-server 9092 # Dovrebbe fallire
```

---

## ESERCIZIO 18: Configurare SELinux per Kafka
**Competenze RHCSA:** semanage, restorecon, audit2allow, sebool

### Scenario
SELinux blocca Kafka. Risolvere senza disabilitarlo.

### Comandi
```bash
# Verifica stato SELinux
getenforce
sestatus

# Verifica se ci sono denial
sudo ausearch -m avc --start today | grep kafka
sudo cat /var/log/audit/audit.log | grep denied | grep kafka

# Metodo 1: Permetti porta custom
sudo semanage port -a -t kafka_port_t -p tcp 9092
sudo semanage port -a -t kafka_port_t -p tcp 9093

# Se kafka_port_t non esiste, usa un tipo generico
sudo semanage port -a -t unreserved_port_t -p tcp 9092

# Metodo 2: Etichetta directory Kafka
sudo semanage fcontext -a -t var_lib_t "/var/lib/kafka(/.*)?"
sudo restorecon -Rv /var/lib/kafka

# Metodo 3: Se ancora non funziona, genera policy custom
sudo ausearch -m avc --start today | audit2allow -M kafka-custom
sudo semodule -i kafka-custom.pp

# Verifica context
ls -Z /var/lib/kafka
ls -Z /opt/kafka/bin/kafka-server-start.sh
```

---

## ESERCIZIO 19: Configurare Bonding per Alta Disponibilità Rete
**Competenze RHCSA:** nmcli, bonding, team

### Scenario
Il server Kafka ha 2 NIC. Configura bonding per failover.

### Comandi
```bash
# Verifica interfacce disponibili
nmcli device status
ip link show

# Crea bond (mode=active-backup per failover)
sudo nmcli connection add type bond con-name bond0 ifname bond0 \
 bond.options "mode=active-backup,miimon=100"

# Aggiungi slave
sudo nmcli connection add type ethernet con-name bond0-slave1 \
 ifname eth0 master bond0

sudo nmcli connection add type ethernet con-name bond0-slave2 \
 ifname eth1 master bond0

# Configura IP
sudo nmcli connection modify bond0 ipv4.addresses 10.0.1.10/24
sudo nmcli connection modify bond0 ipv4.gateway 10.0.1.1
sudo nmcli connection modify bond0 ipv4.dns "10.0.1.2"
sudo nmcli connection modify bond0 ipv4.method manual

# Attiva
sudo nmcli connection up bond0

# Verifica
cat /proc/net/bonding/bond0
ip addr show bond0

# Test failover
sudo ip link set eth0 down
# Il traffico continua su eth1!
```

---

## ESERCIZIO 20: Configurare /etc/hosts per Cluster Kafka
**Competenze RHCSA:** /etc/hosts, hostname, hostnamectl

### Scenario
Configurare risoluzione nomi per cluster Kafka a 3 nodi.

### Comandi
```bash
# Imposta hostname (su ogni nodo)
sudo hostnamectl set-hostname kafka-node-1.example.com

# Verifica
hostnamectl
hostname -f

# Configura /etc/hosts su TUTTI i nodi
sudo tee -a /etc/hosts << 'EOF'
# Kafka Cluster
10.0.1.10 kafka-node-1 kafka-node-1.example.com
10.0.1.11 kafka-node-2 kafka-node-2.example.com
10.0.1.12 kafka-node-3 kafka-node-3.example.com
EOF

# Test risoluzione
ping -c 2 kafka-node-1
ping -c 2 kafka-node-2
ping -c 2 kafka-node-3

# Aggiorna advertised.listeners in Kafka
# advertised.listeners=PLAINTEXT://kafka-node-1:9092
```

---

# 
# SEZIONE 5: PROCESSI E PERFORMANCE (Esercizi 21-25)
# 

## ESERCIZIO 21: Tuning Kernel per Kafka
**Competenze RHCSA:** sysctl, /etc/sysctl.d/

### Scenario
Ottimizzare parametri kernel per Kafka.

### Comandi
```bash
# Crea file sysctl per Kafka
sudo tee /etc/sysctl.d/99-kafka.conf << 'EOF'
# Network
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_max_syn_backlog = 32768

# Memory
vm.swappiness = 1
vm.dirty_ratio = 80
vm.dirty_background_ratio = 5

# File handles
fs.file-max = 1000000
EOF

# Applica
sudo sysctl --system

# Verifica
sysctl net.core.somaxconn
sysctl vm.swappiness
```

### Spiegazione
| Parametro | Valore | Motivo |
|-----------|--------|--------|
| vm.swappiness | 1 | Kafka non deve swappare (performance) |
| net.core.somaxconn | 32768 | Più connessioni in coda |
| vm.dirty_ratio | 80 | Più dati in page cache prima di flush |

---

## ESERCIZIO 22: Configurare cgroups per Kafka
**Competenze RHCSA:** systemd-cgls, CPUQuota, MemoryLimit

### Scenario
Limitare risorse che Kafka può usare per non impattare altri servizi.

### Comandi
```bash
# Vedi cgroup attuale di Kafka
systemd-cgls -u kafka.service

# Modifica service per limitare risorse
sudo systemctl edit kafka.service

# Aggiungi:
[Service]
# Limita CPU al 80%
CPUQuota=80%

# Limita memoria a 4GB
MemoryLimit=4G
MemoryHigh=3G

# Limita I/O
IOWeight=500

# Riavvia
sudo systemctl daemon-reload
sudo systemctl restart kafka

# Verifica
systemctl show kafka.service | grep -E "CPU|Memory|IO"
cat /sys/fs/cgroup/system.slice/kafka.service/memory.max
```

---

## ESERCIZIO 23: Nice e Priority dei Processi
**Competenze RHCSA:** nice, renice, ionice

### Scenario
Dare priorità alta a Kafka rispetto ad altri processi.

### Comandi
```bash
# Nel systemd service, aggiungi:
# Nice=-10 (più priorità, range -20 a 19)
# IOSchedulingClass=realtime
# IOSchedulingPriority=0

sudo systemctl edit kafka.service
# [Service]
# Nice=-10
# IOSchedulingClass=2
# IOSchedulingPriority=0

sudo systemctl daemon-reload
sudo systemctl restart kafka

# Verifica nice
ps -eo pid,ni,comm | grep java

# Cambia nice a runtime (senza restart)
sudo renice -n -10 -p $(pgrep -f kafka)

# Priorità I/O
sudo ionice -c 2 -n 0 -p $(pgrep -f kafka)
```

---

## ESERCIZIO 24: Monitorare Processi con top/htop
**Competenze RHCSA:** top, ps, /proc

### Scenario
Diagnosticare problemi di performance di Kafka.

### Comandi
```bash
# top filtrato su Kafka
top -p $(pgrep -f kafka | head -1)

# htop con filtro
htop -p $(pgrep -f kafka)

# Informazioni dettagliate processo
ps -p $(pgrep -f kafka) -o pid,ppid,user,%cpu,%mem,vsz,rss,stat,start,time,command

# Thread di Kafka
ps -T -p $(pgrep -f kafka) | head -20

# File aperti da Kafka
sudo ls -la /proc/$(pgrep -f kafka)/fd | wc -l

# Memoria dettagliata
sudo cat /proc/$(pgrep -f kafka)/status | grep -E "VmSize|VmRSS|VmSwap|Threads"

# Connessioni di rete
sudo ss -tnp | grep $(pgrep -f kafka) | wc -l
```

---

## ESERCIZIO 25: Troubleshoot con strace
**Competenze RHCSA:** strace, ltrace

### Scenario
Kafka è lento. Vedi cosa sta facendo a livello di system call.

### Comandi
```bash
# Installa strace
sudo dnf install -y strace

# Traccia system call (ATTENZIONE: impatta performance!)
sudo strace -p $(pgrep -f kafka) -f -e trace=write,read -t 2>&1 | head -100

# Conta system call per tipo
sudo strace -p $(pgrep -f kafka) -f -c -w &
sleep 30
kill %1

# Traccia solo file I/O
sudo strace -p $(pgrep -f kafka) -f -e trace=open,close,read,write -t

# Traccia solo network
sudo strace -p $(pgrep -f kafka) -f -e trace=network -t
```

---

# 
# SEZIONE 6: LOGGING E TROUBLESHOOTING (Esercizi 26-30)
# 

## ESERCIZIO 26: Configurare Log Rotation per Kafka
**Competenze RHCSA:** logrotate, /etc/logrotate.d/

### Scenario
I log Kafka stanno riempiendo il disco. Configura rotation.

### Comandi
```bash
# Crea config logrotate
sudo tee /etc/logrotate.d/kafka << 'EOF'
/var/log/kafka/*.log {
 daily
 rotate 7
 compress
 delaycompress
 missingok
 notifempty
 create 0640 kafka kafka
 sharedscripts
 postrotate
 # Segnala a Kafka di riaprire i file
 systemctl kill -s HUP kafka.service 2>/dev/null || true
 endscript
}

/opt/kafka/logs/*.log {
 daily
 rotate 7
 compress
 delaycompress
 missingok
 notifempty
 copytruncate
}
EOF

# Testa (dry-run)
sudo logrotate -d /etc/logrotate.d/kafka

# Forza rotation
sudo logrotate -f /etc/logrotate.d/kafka

# Verifica
ls -la /var/log/kafka/
```

---

## ESERCIZIO 27: Configurare Rsyslog per Log Centralizzati
**Competenze RHCSA:** rsyslog, /etc/rsyslog.d/, remote logging

### Scenario
Inviare log Kafka a un server syslog centrale.

### Comandi
```bash
# Crea config rsyslog per Kafka
sudo tee /etc/rsyslog.d/kafka.conf << 'EOF'
# Log Kafka in file separato
if $programname == 'kafka' then /var/log/kafka/kafka-syslog.log
& stop

# Invia anche a server remoto
if $programname == 'kafka' then @@logserver.example.com:514
EOF

# Riavvia rsyslog
sudo systemctl restart rsyslog

# Nel service Kafka, aggiungi logging a syslog:
# StandardOutput=syslog
# StandardError=syslog
# SyslogIdentifier=kafka
```

---

## ESERCIZIO 28: Analizzare Log con journalctl
**Competenze RHCSA:** journalctl query avanzate

### Scenario
Trova errori specifici nei log Kafka.

### Comandi
```bash
# Errori dell'ultima ora
sudo journalctl -u kafka --since "1 hour ago" -p err

# Cerca pattern specifico
sudo journalctl -u kafka | grep -i "OutOfMemory"
sudo journalctl -u kafka | grep -i "timeout"
sudo journalctl -u kafka | grep -i "exception"

# Log tra due date
sudo journalctl -u kafka --since "2024-01-15 10:00" --until "2024-01-15 12:00"

# Esporta per analisi
sudo journalctl -u kafka --since today -o json > /tmp/kafka-logs.json

# Statistiche log
sudo journalctl -u kafka --since today | wc -l

# Boot precedente (utile dopo crash)
sudo journalctl -u kafka -b -1

# Verifica dimensione log
journalctl --disk-usage
```

---

## ESERCIZIO 29: Troubleshoot con sosreport
**Competenze RHCSA:** sosreport, informazioni di sistema

### Scenario
Devi raccogliere tutte le info di sistema per il supporto.

### Comandi
```bash
# Installa sos
sudo dnf install -y sos

# Genera report completo
sudo sosreport --batch

# Report solo per Kafka (plugin custom se disponibile)
sudo sosreport --batch --only-plugins=systemd,logs,networking

# Il report è in /var/tmp/sosreport-*.tar.xz

# Estrai e analizza
cd /var/tmp
sudo tar -xf sosreport-*.tar.xz
ls sosreport-*/

# Parti importanti:
# sos_commands/systemd/ - stato servizi
# var/log/ - log di sistema
# etc/ - configurazioni
```

---

## ESERCIZIO 30: Diagnostica con dmesg
**Competenze RHCSA:** dmesg, kernel ring buffer

### Scenario
Kafka crasha senza log. Verifica problemi a livello kernel.

### Comandi
```bash
# Vedi messaggi kernel recenti
dmesg -T | tail -50

# Filtra per errori
dmesg -T --level=err,warn

# Cerca OOM killer (Kafka ucciso per memoria)
dmesg -T | grep -i "out of memory"
dmesg -T | grep -i "killed process"

# Cerca errori disco
dmesg -T | grep -i "error" | grep -i -E "sd|nvme|disk"

# Cerca errori di rete
dmesg -T | grep -i "link"

# Follow in tempo reale
dmesg -T -w
```

---

# 
# SEZIONE 7: AUTOMAZIONE E SCRIPTING (Esercizi 31-35)
# 

## ESERCIZIO 31: Script di Health Check Kafka
**Competenze RHCSA:** bash scripting, exit codes, conditionals

### Comandi
```bash
sudo tee /opt/kafka/scripts/health-check.sh << 'EOF'
#!/bin/bash
# Kafka Health Check Script

BOOTSTRAP_SERVER="localhost:9092"
ADMIN_CONFIG="/etc/kafka/admin.properties"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

check_passed() {
 echo -e "${GREEN}[PASS]${NC} $1"
}

check_failed() {
 echo -e "${RED}[FAIL]${NC} $1"
 ERRORS=$((ERRORS + 1))
}

ERRORS=0

echo "=== Kafka Health Check ==="
echo ""

# 1. Verifica processo
if pgrep -f kafka.Kafka > /dev/null; then
 check_passed "Kafka process running"
else
 check_failed "Kafka process NOT running"
fi

# 2. Verifica porta
if ss -tlnp | grep -q ":9092"; then
 check_passed "Port 9092 listening"
else
 check_failed "Port 9092 NOT listening"
fi

# 3. Verifica broker API
if /opt/kafka/bin/kafka-broker-api-versions.sh \
 --bootstrap-server $BOOTSTRAP_SERVER \
 --command-config $ADMIN_CONFIG > /dev/null 2>&1; then
 check_passed "Broker API responding"
else
 check_failed "Broker API NOT responding"
fi

# 4. Verifica under-replicated partitions
URP=$(/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server $BOOTSTRAP_SERVER \
 --describe \
 --under-replicated-partitions \
 --command-config $ADMIN_CONFIG 2>/dev/null | wc -l)

if [ "$URP" -eq 0 ]; then
 check_passed "No under-replicated partitions"
else
 check_failed "$URP under-replicated partitions found"
fi

# 5. Verifica spazio disco
DISK_USAGE=$(df /var/lib/kafka/data --output=pcent | tail -1 | tr -d ' %')
if [ "$DISK_USAGE" -lt 80 ]; then
 check_passed "Disk usage: ${DISK_USAGE}%"
else
 check_failed "Disk usage HIGH: ${DISK_USAGE}%"
fi

echo ""
echo "=== Summary ==="
if [ $ERRORS -eq 0 ]; then
 echo -e "${GREEN}All checks passed!${NC}"
 exit 0
else
 echo -e "${RED}$ERRORS checks failed!${NC}"
 exit 1
fi
EOF

chmod +x /opt/kafka/scripts/health-check.sh
```

---

## ESERCIZIO 32: Cron Job per Monitoraggio
**Competenze RHCSA:** crontab, /etc/cron.d/, anacron

### Comandi
```bash
# Metodo 1: crontab utente kafka
sudo -u kafka crontab -e
# Aggiungi:
# */5 * * * * /opt/kafka/scripts/health-check.sh >> /var/log/kafka/health-check.log 2>&1

# Metodo 2: file in /etc/cron.d/
sudo tee /etc/cron.d/kafka-monitoring << 'EOF'
# Kafka health check ogni 5 minuti
*/5 * * * * kafka /opt/kafka/scripts/health-check.sh >> /var/log/kafka/health-check.log 2>&1

# Backup config ogni notte alle 2
0 2 * * * kafka /opt/kafka/scripts/backup-config.sh >> /var/log/kafka/backup.log 2>&1

# Pulizia log vecchi ogni settimana
0 3 * * 0 root find /var/log/kafka -name "*.gz" -mtime +30 -delete
EOF

# Verifica cron
sudo systemctl status crond
crontab -l -u kafka
```

---

## ESERCIZIO 33: At per Task One-Time
**Competenze RHCSA:** at, atq, atrm

### Scenario
Schedulare un rolling restart stanotte alle 3.

### Comandi
```bash
# Verifica servizio at
sudo systemctl start atd
sudo systemctl enable atd

# Schedula restart
echo "/opt/kafka/scripts/rolling-restart.sh" | at 03:00

# Verifica job schedulati
atq

# Dettaglio job
at -c <job_number>

# Cancella job
atrm <job_number>

# Schedula per una data specifica
echo "/opt/kafka/scripts/maintenance.sh" | at 03:00 20240120

# Con output via email
echo "/opt/kafka/scripts/health-check.sh" | at now + 1 hour
```

---

## ESERCIZIO 34: Script di Rolling Restart
**Competenze RHCSA:** bash scripting, ssh, loops

### Comandi
```bash
sudo tee /opt/kafka/scripts/rolling-restart.sh << 'EOF'
#!/bin/bash
# Rolling restart Kafka cluster

BROKERS="kafka-node-1 kafka-node-2 kafka-node-3"
ADMIN_CONFIG="/etc/kafka/admin.properties"

echo "Starting rolling restart at $(date)"

for broker in $BROKERS; do
 echo ""
 echo "=== Processing $broker ==="

 # Pre-check
 echo "Checking under-replicated partitions..."
 URP=$(/opt/kafka/bin/kafka-topics.sh \
 --bootstrap-server localhost:9092 \
 --describe \
 --under-replicated-partitions \
 --command-config $ADMIN_CONFIG 2>/dev/null | wc -l)

 if [ "$URP" -gt 0 ]; then
 echo "ERROR: $URP under-replicated partitions. Aborting!"
 exit 1
 fi

 # Restart
 echo "Restarting Kafka on $broker..."
 ssh $broker "sudo systemctl restart kafka"

 # Wait for broker to come back
 echo "Waiting for $broker to be ready..."
 sleep 30

 # Verify
 for i in {1..12}; do
 if /opt/kafka/bin/kafka-broker-api-versions.sh \
 --bootstrap-server ${broker}:9092 > /dev/null 2>&1; then
 echo "$broker is back online"
 break
 fi
 echo "Waiting... ($i/12)"
 sleep 10
 done

 # Wait for ISR sync
 echo "Waiting for ISR synchronization..."
 sleep 60
done

echo ""
echo "Rolling restart completed at $(date)"
EOF

chmod +x /opt/kafka/scripts/rolling-restart.sh
```

---

## ESERCIZIO 35: Alerting con Script
**Competenze RHCSA:** mail, curl, scripting

### Comandi
```bash
sudo tee /opt/kafka/scripts/alert.sh << 'EOF'
#!/bin/bash
# Alert script for Kafka issues

ALERT_EMAIL="admin@example.com"
SLACK_WEBHOOK="https://hooks.slack.com/services/XXX/YYY/ZZZ"

send_alert() {
 local severity=$1
 local message=$2

 # Email
 echo "$message" | mail -s "[Kafka Alert - $severity] $(hostname)" $ALERT_EMAIL

 # Slack
 curl -X POST -H 'Content-type: application/json' \
 --data "{\"text\":\"[$severity] $(hostname): $message\"}" \
 $SLACK_WEBHOOK

 # Log
 logger -p local0.alert "Kafka Alert [$severity]: $message"
}

# Usa così:
# source /opt/kafka/scripts/alert.sh
# send_alert "CRITICAL" "Kafka broker down!"
EOF

# Integra in health-check.sh
# if [ $ERRORS -gt 0 ]; then
# source /opt/kafka/scripts/alert.sh
# send_alert "WARNING" "$ERRORS health checks failed"
# fi
```

---

# 
# SEZIONE 8: SECURITY (Esercizi 36-40)
# 

## ESERCIZIO 36: Configurare SSH Key per Automazione
**Competenze RHCSA:** ssh-keygen, ssh-copy-id, authorized_keys

### Scenario
Configurare SSH key per rolling restart automatico.

### Comandi
```bash
# Come utente che eseguirà gli script (es: kafka-admin)
su - kafka-admin

# Genera coppia di chiavi
ssh-keygen -t ed25519 -C "kafka-automation" -f ~/.ssh/kafka_automation

# Copia chiave pubblica su tutti i nodi
for node in kafka-node-1 kafka-node-2 kafka-node-3; do
 ssh-copy-id -i ~/.ssh/kafka_automation.pub $node
done

# Configura SSH per usare la chiave automaticamente
cat >> ~/.ssh/config << 'EOF'
Host kafka-node-*
 User kafka-admin
 IdentityFile ~/.ssh/kafka_automation
 StrictHostKeyChecking no
EOF

chmod 600 ~/.ssh/config

# Test
ssh kafka-node-2 "hostname"
```

---

## ESERCIZIO 37: Configurare Sudo Sicuro
**Competenze RHCSA:** visudo, sudoers, NOPASSWD

### Comandi
```bash
# Crea file sudoers per operazioni Kafka
sudo visudo -f /etc/sudoers.d/kafka-automation

# Contenuto:
# Defaults:kafka-admin !requiretty
# kafka-admin ALL=(ALL) NOPASSWD: /bin/systemctl * kafka
# kafka-admin ALL=(ALL) NOPASSWD: /bin/systemctl * kafka-connect
# kafka-admin ALL=(ALL) NOPASSWD: /bin/journalctl -u kafka*

# Verifica sintassi
sudo visudo -c -f /etc/sudoers.d/kafka-automation

# Test
sudo -l -U kafka-admin
```

---

## ESERCIZIO 38: Audit delle Operazioni Kafka
**Competenze RHCSA:** auditd, auditctl, ausearch

### Comandi
```bash
# Installa e abilita auditd
sudo dnf install -y audit
sudo systemctl enable --now auditd

# Aggiungi regole per Kafka
sudo tee /etc/audit/rules.d/kafka.rules << 'EOF'
# Monitor Kafka config files
-w /etc/kafka/ -p wa -k kafka-config

# Monitor Kafka binaries
-w /opt/kafka/bin/ -p x -k kafka-exec

# Monitor Kafka service
-w /etc/systemd/system/kafka.service -p wa -k kafka-service

# Monitor data directory
-w /var/lib/kafka/ -p wa -k kafka-data
EOF

# Ricarica regole
sudo augenrules --load

# Verifica regole attive
sudo auditctl -l

# Cerca eventi
sudo ausearch -k kafka-config
sudo ausearch -k kafka-exec --start today
```

---

## ESERCIZIO 39: Hardening Sistema per Kafka
**Competenze RHCSA:** sshd_config, security best practices

### Comandi
```bash
# 1. Disabilita login root SSH
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# 2. Solo SSH key, no password
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# 3. Riavvia SSHD
sudo systemctl restart sshd

# 4. Rimuovi pacchetti non necessari
sudo dnf remove -y telnet rsh

# 5. Abilita AIDE (file integrity)
sudo dnf install -y aide
sudo aide --init
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# 6. Verifica porte aperte
sudo ss -tlnp
# Solo porte necessarie dovrebbero essere aperte

# 7. Password policy
sudo vi /etc/security/pwquality.conf
# minlen = 12
# dcredit = -1
# ucredit = -1
# lcredit = -1
# ocredit = -1
```

---

## ESERCIZIO 40: LUKS per Encryption at Rest
**Competenze RHCSA:** cryptsetup, LUKS

### Scenario
Criptare il volume dati Kafka.

### Comandi
```bash
# ATTENZIONE: Questo distrugge i dati esistenti!
# Esegui solo su nuova installazione o dopo backup

# Crea partizione criptata
sudo cryptsetup luksFormat /dev/sdb

# Apri volume criptato
sudo cryptsetup luksOpen /dev/sdb kafka_data_crypt

# Crea LVM su volume criptato
sudo pvcreate /dev/mapper/kafka_data_crypt
sudo vgcreate vg_kafka_secure /dev/mapper/kafka_data_crypt
sudo lvcreate -l 100%FREE -n lv_kafka_data vg_kafka_secure

# Formatta e monta
sudo mkfs.xfs /dev/vg_kafka_secure/lv_kafka_data
sudo mount /dev/vg_kafka_secure/lv_kafka_data /var/lib/kafka/data

# Per auto-unlock al boot, usa keyfile:
sudo dd if=/dev/urandom of=/root/kafka-luks-key bs=1 count=256
sudo chmod 400 /root/kafka-luks-key
sudo cryptsetup luksAddKey /dev/sdb /root/kafka-luks-key

# Aggiungi a /etc/crypttab:
# kafka_data_crypt /dev/sdb /root/kafka-luks-key luks
```

---

# 
# SEZIONE 9: BACKUP E RECOVERY (Esercizi 41-45)
# 

## ESERCIZIO 41: Backup con tar
**Competenze RHCSA:** tar, compression, exclude

### Comandi
```bash
sudo tee /opt/kafka/scripts/backup-config.sh << 'EOF'
#!/bin/bash
# Backup configurazioni Kafka

BACKUP_DIR=/backup/kafka
DATE=$(date +%Y%m%d)
BACKUP_FILE=$BACKUP_DIR/kafka-config-$DATE.tar.gz

mkdir -p $BACKUP_DIR

# Backup config
tar -czvf $BACKUP_FILE \
 --exclude='*.tmp' \
 /etc/kafka \
 /opt/kafka/config \
 /etc/systemd/system/kafka.service \
 /etc/systemd/system/kafka-connect.service \
 2>/dev/null

# Verifica
tar -tzf $BACKUP_FILE

# Mantieni solo ultimi 7 backup
find $BACKUP_DIR -name "kafka-config-*.tar.gz" -mtime +7 -delete

echo "Backup completato: $BACKUP_FILE"
ls -lh $BACKUP_FILE
EOF

chmod +x /opt/kafka/scripts/backup-config.sh
```

---

## ESERCIZIO 42: Rsync per Backup Remoto
**Competenze RHCSA:** rsync, ssh, incremental backup

### Comandi
```bash
sudo tee /opt/kafka/scripts/backup-remote.sh << 'EOF'
#!/bin/bash
# Rsync backup a server remoto

BACKUP_SERVER="backup.example.com"
BACKUP_USER="backup"
BACKUP_PATH="/backup/kafka/$(hostname)"

# Config e binari (compressi, incrementale)
rsync -avz --delete \
 -e "ssh -i /root/.ssh/backup_key" \
 /etc/kafka \
 /opt/kafka/config \
 ${BACKUP_USER}@${BACKUP_SERVER}:${BACKUP_PATH}/

# Metadata cluster (NON i dati dei topic)
rsync -avz \
 -e "ssh -i /root/.ssh/backup_key" \
 /var/lib/kafka/data/__cluster_metadata-0 \
 ${BACKUP_USER}@${BACKUP_SERVER}:${BACKUP_PATH}/metadata/

echo "Remote backup completato"
EOF

chmod +x /opt/kafka/scripts/backup-remote.sh
```

---

## ESERCIZIO 43: LVM Snapshot per Backup Consistente
**Competenze RHCSA:** lvcreate --snapshot

### Comandi
```bash
# Crea snapshot (richiede spazio libero nel VG)
sudo lvcreate --size 10G --snapshot --name lv_kafka_snap /dev/vg_kafka/lv_kafka_data

# Monta snapshot (read-only)
sudo mkdir -p /mnt/kafka-snapshot
sudo mount -o ro /dev/vg_kafka/lv_kafka_snap /mnt/kafka-snapshot

# Backup dallo snapshot (mentre Kafka continua a funzionare)
tar -czvf /backup/kafka-data-$(date +%Y%m%d).tar.gz /mnt/kafka-snapshot/

# Smonta e rimuovi snapshot
sudo umount /mnt/kafka-snapshot
sudo lvremove -f /dev/vg_kafka/lv_kafka_snap

echo "Snapshot backup completato"
```

---

## ESERCIZIO 44: Recovery da Backup
**Competenze RHCSA:** tar extract, restore

### Scenario
Il server Kafka è stato reinstallato. Ripristina le configurazioni.

### Comandi
```bash
# Stop Kafka se running
sudo systemctl stop kafka

# Ripristina config da backup
sudo tar -xzvf /backup/kafka-config-20240115.tar.gz -C /

# Fix permessi
sudo chown -R kafka:kafka /etc/kafka
sudo chown -R kafka:kafka /opt/kafka/config

# Verifica
ls -la /etc/kafka/
cat /etc/kafka/server.properties

# Riavvia
sudo systemctl start kafka
sudo systemctl status kafka
```

---

## ESERCIZIO 45: Rescue Mode e Recovery
**Competenze RHCSA:** single user mode, rescue target

### Scenario
Il server non avvia. Kafka potrebbe essere la causa.

### Comandi
```bash
# 1. Boot in rescue mode:
# Al boot, premi 'e' su GRUB
# Aggiungi: systemd.unit=rescue.target
# Premi Ctrl+X per avviare

# 2. Oppure da sistema funzionante:
sudo systemctl isolate rescue.target

# 3. In rescue mode:
# Disabilita Kafka temporaneamente
systemctl disable kafka

# Verifica log del problema
journalctl -xb -p err

# Ripara configurazione se necessario
vi /etc/kafka/server.properties

# Riabilita e riavvia
systemctl enable kafka
systemctl reboot

# 4. Rescue da live USB:
# mount root filesystem
mount /dev/vg_root/lv_root /mnt/sysimage
chroot /mnt/sysimage
# ora puoi modificare file
```

---

# 
# SEZIONE 10: AVANZATI (Esercizi 46-50)
# 

## ESERCIZIO 46: Podman Container per Kafka Tools
**Competenze RHCSA:** podman, containers

### Scenario
Usa container per strumenti Kafka senza installarli sull'host.

### Comandi
```bash
# Installa Podman
sudo dnf install -y podman

# Pull immagine Kafka
podman pull docker.io/confluentinc/cp-kafka:latest

# Esegui kafka-topics.sh da container
podman run --rm -it \
 --network host \
 confluentinc/cp-kafka:latest \
 kafka-topics --bootstrap-server localhost:9092 --list

# Crea alias per comodità
alias kafka-topics='podman run --rm -it --network host confluentinc/cp-kafka:latest kafka-topics'
alias kafka-console-producer='podman run --rm -it --network host confluentinc/cp-kafka:latest kafka-console-producer'
alias kafka-console-consumer='podman run --rm -it --network host confluentinc/cp-kafka:latest kafka-console-consumer'

# Salva alias
echo "alias kafka-topics='podman run --rm -it --network host confluentinc/cp-kafka:latest kafka-topics'" >> ~/.bashrc
```

---

## ESERCIZIO 47: Ansible per Gestione Kafka
**Competenze RHCSA:** ansible basics

### Comandi
```bash
# Installa Ansible
sudo dnf install -y ansible

# Inventory
cat > /etc/ansible/hosts << 'EOF'
[kafka_brokers]
kafka-node-1 ansible_host=10.0.1.10
kafka-node-2 ansible_host=10.0.1.11
kafka-node-3 ansible_host=10.0.1.12

[kafka_brokers:vars]
ansible_user=kafka-admin
ansible_ssh_private_key_file=/home/kafka-admin/.ssh/kafka_automation
EOF

# Test connettività
ansible kafka_brokers -m ping

# Raccogli fatti
ansible kafka_brokers -m setup | grep ansible_hostname

# Esegui comando su tutti i nodi
ansible kafka_brokers -a "systemctl status kafka"

# Playbook per rolling restart
cat > rolling-restart.yml << 'EOF'
---
- name: Rolling restart Kafka
 hosts: kafka_brokers
 serial: 1
 tasks:
 - name: Restart Kafka
 systemd:
 name: kafka
 state: restarted
 become: yes

 - name: Wait for Kafka to be ready
 wait_for:
 port: 9092
 delay: 10
 timeout: 120
EOF

ansible-playbook rolling-restart.yml
```

---

## ESERCIZIO 48: Kickstart per Deploy Automatico
**Competenze RHCSA:** kickstart, anaconda

### Comandi
```bash
# Esempio kickstart per server Kafka
cat > /var/www/html/ks/kafka-server.ks << 'EOF'
#version=RHEL9
ignoredisk --only-use=sda,sdb

# System bootloader
bootloader --append="crashkernel=auto" --location=mbr --boot-drive=sda

# Partition
clearpart --all --initlabel
part /boot --fstype="xfs" --ondisk=sda --size=1024
part pv.01 --fstype="lvmpv" --ondisk=sda --size=1 --grow
part pv.02 --fstype="lvmpv" --ondisk=sdb --size=1 --grow

volgroup vg_root --pesize=4096 pv.01
volgroup vg_kafka --pesize=4096 pv.02

logvol / --fstype="xfs" --size=20480 --name=lv_root --vgname=vg_root
logvol swap --fstype="swap" --size=4096 --name=lv_swap --vgname=vg_root
logvol /var/lib/kafka --fstype="xfs" --size=1 --grow --name=lv_kafka_data --vgname=vg_kafka --fsoptions="noatime,nodiratime"

# Network
network --bootproto=dhcp --device=eth0 --onboot=on --hostname=kafka-node.example.com

# Root password
rootpw --iscrypted $6$rounds=4096$...

# User
user --name=kafka-admin --groups=wheel --iscrypted --password=$6$rounds=4096$...

# Packages
%packages
@core
java-17-openjdk
java-17-openjdk-devel
%end

# Post install
%post
# Crea utente kafka
useradd -r -s /sbin/nologin kafka

# Scarica e installa Kafka
curl -o /tmp/kafka.tgz https://downloads.apache.org/kafka/3.9.0/kafka_2.13-3.9.0.tgz
tar -xzf /tmp/kafka.tgz -C /opt
mv /opt/kafka_2.13-3.9.0 /opt/kafka
chown -R kafka:kafka /opt/kafka

# Fix permessi data dir
chown -R kafka:kafka /var/lib/kafka
%end
EOF
```

---

## ESERCIZIO 49: Performance Baseline con sysbench
**Competenze RHCSA:** benchmarking, baseline

### Comandi
```bash
# Installa sysbench
sudo dnf install -y sysbench

# CPU test
sysbench cpu --cpu-max-prime=20000 run

# Memory test
sysbench memory --memory-block-size=1K --memory-scope=global --memory-total-size=10G run

# Disk test (sequenziale - simile a Kafka)
sysbench fileio --file-total-size=10G prepare
sysbench fileio --file-total-size=10G --file-test-mode=seqwr run
sysbench fileio --file-total-size=10G --file-test-mode=seqrd run
sysbench fileio --file-total-size=10G cleanup

# Salva risultati come baseline
echo "Baseline $(date)" >> /root/performance-baseline.txt
sysbench cpu --cpu-max-prime=20000 run >> /root/performance-baseline.txt
sysbench memory --memory-block-size=1K --memory-scope=global --memory-total-size=10G run >> /root/performance-baseline.txt
```

---

## ESERCIZIO 50: Documentazione e Runbook
**Competenze RHCSA:** documentazione operativa

### Template Runbook
```bash
cat > /opt/kafka/docs/RUNBOOK.md << 'EOF'
# KAFKA OPERATIONS RUNBOOK

## Quick Reference

| Operazione | Comando |
|------------|---------|
| Start Kafka | `sudo systemctl start kafka` |
| Stop Kafka | `sudo systemctl stop kafka` |
| Status | `sudo systemctl status kafka` |
| Logs | `sudo journalctl -u kafka -f` |

## Procedure Operative

### Rolling Restart
1. Verificare pre-requisiti: `./scripts/health-check.sh`
2. Eseguire: `./scripts/rolling-restart.sh`
3. Verificare post-restart: `./scripts/health-check.sh`

### Scaling
Vedi: [SCALING.md](SCALING.md)

### Disaster Recovery
Vedi: [DR.md](DR.md)

## Contatti
- Team Kafka: kafka-team@example.com
- On-call: +39 123 456 789
- Escalation: Platform Lead

## Troubleshooting

### Kafka non parte
1. `sudo journalctl -u kafka --since "5 min ago"`
2. `sudo systemd-analyze verify /etc/systemd/system/kafka.service`
3. Verificare permessi: `ls -la /var/lib/kafka/data`

### Under-replicated partitions
1. `kafka-topics.sh --describe --under-replicated-partitions`
2. Verificare tutti i broker sono up
3. Attendere sincronizzazione (può richiedere tempo)
EOF
```

---

# COMPLETATO!

Hai completato tutti i 50 esercizi RHCSA applicati a Kafka.

## Competenze Acquisite

| Area | Skills |
|------|--------|
| **Utenti/Permessi** | useradd, chmod, ACL, limits.conf |
| **Systemd** | Unit file, dipendenze, target, journald |
| **Storage** | LVM, XFS, mount, quota, snapshot |
| **Network** | Firewall, SELinux, bonding, /etc/hosts |
| **Performance** | sysctl, cgroups, nice, iostat |
| **Security** | SSH, sudo, audit, LUKS |
| **Backup** | tar, rsync, recovery |
| **Automazione** | Bash, cron, Ansible |

Queste competenze sono fondamentali per gestire Kafka in produzione su VM/bare metal!
