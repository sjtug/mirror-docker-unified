# Server Configuration

## Zhiyuan (legacy)

Login via `ssh mirror-zhiyuan`.
Mirror info: `/opt/mirror-docker-zhiyuan`, `sudo make up-zhiyuan` for startup

## Siyuan

Login via `ssh mirror-siyuan`.
Mirror info: `/opt/mirror-docker-siyuan`, `sudo make up-siyuan` for startup

iSCSI client (`open-iscsi.service`) with follow mount record:

```
#/etc/fstab

# iSCSI 55T storage - allow failures with nofail option (not tested)
/dev/disk/by-path/ip-... /mnt/data55T ext4 _netdev,nofail,x-systemd.requires=iscsi.service,x-systemd.after=iscsi.service,x-systemd.device-timeout=30,auto 0 0
/mnt/data55T/mirror-postgres-data /srv/mirror/postgres-data none bind,x-systemd.requires=/mnt/data55T,x-systemd.after=/mnt/data55T 0 0

```

## Storage (shared machine; private network only)

Login via `ssh g-storage`.

Mirror monitoring checkout:

- `/home/sjtug/mirror-docker-g-storage`; stack directory `monitor/g-storage`.
- Alertmanager joins the external containerd CNI network `metacubexd_default`
  and reaches the proxy through the `metacubexd` alias.

iSCSI server (`tgt.service`) reads from `/etc/tgt/conf.d/data55T.conf`

## Monitoring

The active monitoring stack runs on `g-storage` from:

```sh
ssh g-storage
cd /home/sjtug/mirror-docker-g-storage
```

Grafana is bound to `127.0.0.1:3000`:

```sh
ssh -L 3000:127.0.0.1:3000 g-storage
# open http://127.0.0.1:3000/
```

Grafana uses GitHub OAuth restricted to the `sjtug` organization and mirrors
maintainer team. Provisioned datasources and dashboards live under
`monitor/g-storage/grafana/`.
