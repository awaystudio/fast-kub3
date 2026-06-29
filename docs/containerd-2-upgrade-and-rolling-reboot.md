# Upgrade containerd 1.x → 2.x + rolling reboot del cluster

> Guida operativa redatta dopo l'aggiornamento del **2026-06-29** sul cluster `awaystudio` (3 nodi, k8s v1.34.2 su Ubuntu 24.04).
> Autore: edgar

## Contesto

Dopo un `apt-get upgrade` su tutti i nodi, **containerd è stato aggiornato dalla 1.x alla 2.x**. La 2.x **non accetta più** la configurazione del registry mirror *inline* nel `config.toml` — va migrata al formato nativo `hosts.toml` sotto `certs.d/`. Se non si migra la config, al riavvio di containerd il nodo diventa **`NotReady`**.

I tre nodi avevano due situazioni diverse:

| Nodo | Ruolo | Stack containerd | Provenienza |
|------|-------|------------------|-------------|
| `dkr-ti-up101` (192.168.2.243) | worker | 2.2.1 | pacchetto **apt** Ubuntu |
| `dkr-ti-up102` (192.168.2.244) | worker | 2.2.1 | pacchetto **apt** Ubuntu |
| `dkrd-ti-up101` (192.168.2.240) | control-plane + **build/registry** | 2.3.2 | install **manuale** `nerdctl-full` in `/usr/local` |

> ⚠️ Il **master è anche il nodo di build** (buildkit + `registry:2` locale sulla `192.168.2.240:5000`), installato a mano via `nerdctl-full`. NON è gestito da apt: l'apt ci aveva messo una 2.x in `/usr/bin` **inutilizzata**, mentre il binario realmente in esecuzione era quello manuale in `/usr/local/bin` (la unit `/usr/local/lib/systemd/system/containerd.service` ha precedenza).

## Sintomo del problema config

Dopo riavvio di containerd il nodo va `NotReady`. Nei log:

```
failed to load TOML ... registry.mirrors ... config_path must be set
```

La causa è un blocco di questo tipo nel `config.toml`:

```toml
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = ""

# ...e in coda al file:
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.2.240:5000"]
  endpoint = ["http://192.168.2.240:5000"]
```

## Fix della config registry (vale per tutti i nodi)

### 1. Crea `hosts.toml` nativo

```bash
sudo mkdir -p "/etc/containerd/certs.d/192.168.2.240:5000"
sudo tee "/etc/containerd/certs.d/192.168.2.240:5000/hosts.toml" >/dev/null <<'EOF'
server = "http://192.168.2.240:5000"

[host."http://192.168.2.240:5000"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF
```

> `skip_verify = true` perché il registry locale è in **HTTP** (insicuro).

### 2. Modifica `config.toml`

```bash
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.bak-preedgar-$(date +%F)
```

- Imposta `config_path` nella sezione registry CRI:
  ```toml
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
  ```
- **Rimuovi** il blocco mirror inline in coda (`registry.mirrors."192.168.2.240:5000"`).

### 3. Riavvia e verifica

```bash
sudo systemctl daemon-reload
sudo systemctl restart containerd
containerd --version            # deve essere 2.x
sudo ctr version                # Server: v2.x
# test pull dal registry locale:
sudo nerdctl --namespace k8s.io image pull 192.168.2.240:5000/<repo>:latest
```

## Upgrade dello stack manuale del master (`nerdctl-full`)

Il master NON va aggiornato via apt. Si aggiorna lo **stack manuale** sostituendo i binari in `/usr/local`.

```bash
# 1. Scarica l'ultima release nerdctl-full e verifica il checksum
cd /tmp
VER=2.3.4   # ultima al 2026-06-29; verifica su github.com/containerd/nerdctl/releases/latest
curl -sL -o nerdctl-full.tgz \
  https://github.com/containerd/nerdctl/releases/download/v$VER/nerdctl-full-$VER-linux-amd64.tar.gz
curl -sL -o SHA256SUMS \
  https://github.com/containerd/nerdctl/releases/download/v$VER/SHA256SUMS
grep "nerdctl-full-$VER-linux-amd64.tar.gz" SHA256SUMS | sed 's| .*| nerdctl-full.tgz|' | sha256sum -c

# 2. Backup binari + unit + config
sudo cp -a /usr/local/bin/containerd /usr/local/bin/containerd.bak-1.7.14
sudo cp -a /usr/local/bin/nerdctl    /usr/local/bin/nerdctl.bak-1.7.5
sudo cp -a /usr/local/bin/buildkitd  /usr/local/bin/buildkitd.bak-0.12.5
sudo cp -a /usr/local/lib/systemd/system/containerd.service{,.bak-preedgar-$(date +%F)}
sudo cp -a /usr/local/lib/systemd/system/buildkit.service{,.bak-preedgar-$(date +%F)}

# 3. Drain del nodo (control-plane: l'API server andrà giù temporaneamente)
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl drain <fqdn-nodo> \
  --ignore-daemonsets --delete-emptydir-data --timeout=120s

# 4. Stop servizi ed estrai il nuovo stack in /usr/local
sudo systemctl stop buildkit
sudo systemctl stop containerd
sudo tar Cxzf /usr/local /tmp/nerdctl-full.tgz

# 5. Applica la fix config registry (vedi sopra), poi:
sudo systemctl daemon-reload
sudo systemctl restart containerd buildkit

# 6. Verifica e uncordon
containerd --version    # v2.x
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl uncordon <fqdn-nodo>
```

> Versioni ottenute con `nerdctl-full 2.3.4`: containerd **2.3.2**, runc **1.5.0**, buildkit **0.31.1**, nerdctl **2.3.4**.

## Rolling reboot del cluster (nuovo kernel)

Dopo `apt upgrade` i nodi hanno `/var/run/reboot-required` (nuovo kernel). Riavviare **uno alla volta**, control-plane **per ultimo**, aspettando `Ready` tra uno e l'altro per non perdere il quorum.

Ordine: **worker1 → worker2 → master**.

Per ogni nodo:

```bash
M=dkrd-ti-up101    # nodo da cui lanciare kubectl (ha admin.conf)
N=<fqdn-nodo-da-riavviare>

# 1. drain
ssh $M "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl drain $N \
  --ignore-daemonsets --delete-emptydir-data --timeout=120s"

# 2. reboot
ssh <nodo> 'sudo systemctl reboot'

# 3. attendi SSH + Ready, verifica reboot pulito
ssh <nodo> 'uname -r; systemctl is-active containerd kubelet; \
  test -f /var/run/reboot-required && echo PENDING || echo PULITO'

# 4. uncordon
ssh $M "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl uncordon $N"
```

> **Master**: dopo il reboot l'API server impiega qualche secondo a tornare (etcd + static pod). Attendere `kubectl get --raw=/healthz` prima di uncordonare. La fix containerd 2.x **persiste** al reboot (la unit manuale in `/usr/local/lib` ha precedenza su quella apt).

## Verifica finale

```bash
ssh dkrd-ti-up101 'sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide'
ssh dkrd-ti-up101 'sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A | grep -vE "Running|Completed"'
```

Atteso: 3 nodi `Ready` (master `containerd://2.3.2`, worker `containerd://2.2.1`), tutti i pod `Running`.

## Rollback

- **Config**: ripristina `config.toml.bak-preedgar-<data>` e riavvia containerd.
- **Binari master**: ripristina i `.bak-*` in `/usr/local/bin` + le unit `.bak-preedgar-*`, poi `daemon-reload` + restart.
- **VM intere**: snapshot Proxmox `pre_apt_2026_06_29` sui VMID 112/113/114; per il NAS (VMID 115) snapshot LVM del solo disco OS `vm-115-disk-0-snap-pre_apt_2026_06_29`.

## Note snapshot Proxmox / NAS

La VM NAS (VMID 115) ha **due dischi**:

| Disco | Storage | Tipo | Snapshottabile da `qm`? |
|-------|---------|------|--------------------------|
| `scsi0` 32G (OS) | `local-lvm` | lvm-**thin** | ✅ |
| `scsi1` 100G (dati) | `data` | lvm-**thick** | ❌ |

`qm snapshot` richiede che **tutti** i dischi siano snapshottabili → fallisce per via del 100G thick. **NON** usare l'opzione disco `snapshot=1`: in Proxmox attiva la *qemu snapshot mode* (disco temporaneo, le modifiche vengono scartate allo shutdown) — è una trappola.

Soluzione: snapshot **LVM-thin diretto** del solo disco OS, bypassando `qm`:

```bash
# sul nodo Proxmox (prmx-ti-up001, 192.168.1.201)
sudo lvcreate -s pve/vm-115-disk-0 -n vm-115-disk-0-snap-pre_apt_2026_06_29
# verifica
sudo lvs -o lv_name,origin,lv_size pve | grep 115
# rimozione quando non serve più
sudo lvremove pve/vm-115-disk-0-snap-pre_apt_2026_06_29
```
