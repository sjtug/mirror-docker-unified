#!/usr/bin/env bash
set -euo pipefail

OUT_DIR=${MIRROR_MONITOR_TEXTFILE_DIR:-/var/lib/mirror-monitor/textfile_collector}
OUT_FILE="$OUT_DIR/mirror_storage_tgt.prom"
TARGET_IQN=${MIRROR_STORAGE_TARGET_IQN:-iqn.2025-05.cn.edu.sjtu.mirror:storage.data55T}
BACKING_STORE=${MIRROR_STORAGE_BACKING_STORE:-/dev/sdc1}

install -d -m 0755 "$OUT_DIR"
TMP_FILE=$(mktemp "$OUT_DIR/.mirror_storage_tgt.prom.XXXXXX")
cleanup() { rm -f "$TMP_FILE"; }
trap cleanup EXIT

now=$(date +%s)
collector_success=1
service_active=0
target_ready=0
lun_online=0
lun_readonly=-1
backing_store_matches=0
active_nexus=0
active_connections=0
backing_block_readonly=-1
backing_block_size_bytes=0
backing_fs_ext4=0

systemctl is-active --quiet tgt.service && service_active=1
show=
if ! show=$(tgtadm --mode target --op show 2>/dev/null); then
  collector_success=0
fi
if printf '%s\n' "$show" | grep -q "Target [0-9].*: $TARGET_IQN"; then
  target_block=$(printf '%s\n' "$show" | awk -v iqn="$TARGET_IQN" '
    $0 ~ "Target [0-9]+: " iqn {in_target=1; print; next}
    in_target && /^Target [0-9]+:/ {exit}
    in_target {print}
  ')
  printf '%s\n' "$target_block" | grep -q 'State: ready' && target_ready=1
  active_nexus=$(printf '%s\n' "$target_block" | grep -cE '^        I_T nexus: [0-9]+' || true)
  active_connections=$(printf '%s\n' "$target_block" | grep -cE '^            Connection: [0-9]+' || true)
  lun_block=$(printf '%s\n' "$target_block" | awk '
    /LUN: 1/ {in_lun=1; print; next}
    in_lun && /LUN: [0-9]+/ {exit}
    in_lun && /^    Account information:/ {exit}
    in_lun {print}
  ')
  printf '%s\n' "$lun_block" | grep -q 'Online: Yes' && lun_online=1
  if printf '%s\n' "$lun_block" | grep -q 'Readonly: Yes'; then
    lun_readonly=1
  elif printf '%s\n' "$lun_block" | grep -q 'Readonly: No'; then
    lun_readonly=0
  fi
  printf '%s\n' "$lun_block" | grep -q "Backing store path: $BACKING_STORE" && backing_store_matches=1
fi

block_name=$(basename "$BACKING_STORE")
if [ -r "/sys/class/block/$block_name/ro" ]; then
  backing_block_readonly=$(cat "/sys/class/block/$block_name/ro" 2>/dev/null || echo -1)
fi
if command -v blockdev >/dev/null 2>&1 && [ -b "$BACKING_STORE" ]; then
  backing_block_size_bytes=$(blockdev --getsize64 "$BACKING_STORE" 2>/dev/null || echo 0)
fi
if [ "$(lsblk -no FSTYPE "$BACKING_STORE" 2>/dev/null | head -1)" = "ext4" ]; then
  backing_fs_ext4=1
fi

cat >"$TMP_FILE" <<METRICS
# HELP mirror_storage_tgt_collector_success Whether the g-storage tgt collector completed successfully.
# TYPE mirror_storage_tgt_collector_success gauge
mirror_storage_tgt_collector_success{host="g-storage"} $collector_success
# HELP mirror_storage_tgt_collector_timestamp_seconds Unix timestamp of the last g-storage tgt collector run.
# TYPE mirror_storage_tgt_collector_timestamp_seconds gauge
mirror_storage_tgt_collector_timestamp_seconds{host="g-storage"} $now
# HELP mirror_storage_tgt_service_active Whether tgt.service is active on g-storage.
# TYPE mirror_storage_tgt_service_active gauge
mirror_storage_tgt_service_active{host="g-storage"} $service_active
# HELP mirror_storage_tgt_target_ready Whether the expected tgt target state is ready.
# TYPE mirror_storage_tgt_target_ready gauge
mirror_storage_tgt_target_ready{host="g-storage",target_iqn="$TARGET_IQN"} $target_ready
# HELP mirror_storage_tgt_lun_online Whether LUN 1 for the expected target is online.
# TYPE mirror_storage_tgt_lun_online gauge
mirror_storage_tgt_lun_online{host="g-storage",target_iqn="$TARGET_IQN",lun="1"} $lun_online
# HELP mirror_storage_tgt_lun_readonly Whether LUN 1 is read-only; 0 is writable, 1 is read-only, -1 is unknown.
# TYPE mirror_storage_tgt_lun_readonly gauge
mirror_storage_tgt_lun_readonly{host="g-storage",target_iqn="$TARGET_IQN",lun="1"} $lun_readonly
# HELP mirror_storage_tgt_backing_store_matches Whether LUN 1 backing store matches the expected block device.
# TYPE mirror_storage_tgt_backing_store_matches gauge
mirror_storage_tgt_backing_store_matches{host="g-storage",target_iqn="$TARGET_IQN",backing_store="$BACKING_STORE"} $backing_store_matches
# HELP mirror_storage_tgt_active_nexus Number of active I_T nexus entries for the expected target.
# TYPE mirror_storage_tgt_active_nexus gauge
mirror_storage_tgt_active_nexus{host="g-storage",target_iqn="$TARGET_IQN"} $active_nexus
# HELP mirror_storage_tgt_active_connections Number of active iSCSI connections for the expected target.
# TYPE mirror_storage_tgt_active_connections gauge
mirror_storage_tgt_active_connections{host="g-storage",target_iqn="$TARGET_IQN"} $active_connections
# HELP mirror_storage_backing_block_readonly Kernel read-only flag for the backing block device; 0 is writable, 1 is read-only, -1 is unknown.
# TYPE mirror_storage_backing_block_readonly gauge
mirror_storage_backing_block_readonly{host="g-storage",device="$BACKING_STORE"} $backing_block_readonly
# HELP mirror_storage_backing_block_size_bytes Backing block device size in bytes.
# TYPE mirror_storage_backing_block_size_bytes gauge
mirror_storage_backing_block_size_bytes{host="g-storage",device="$BACKING_STORE"} $backing_block_size_bytes
# HELP mirror_storage_backing_fs_type_ext4 Whether the backing block device has ext4 filesystem metadata.
# TYPE mirror_storage_backing_fs_type_ext4 gauge
mirror_storage_backing_fs_type_ext4{host="g-storage",device="$BACKING_STORE"} $backing_fs_ext4
METRICS
chmod 0644 "$TMP_FILE"
mv "$TMP_FILE" "$OUT_FILE"
trap - EXIT
