# SR-IOV Setup (i915)

This covers enabling SR-IOV at boot and creating Virtual Functions (VFs) for the i915 PF.

---

## 1) Enable SR-IOV at Boot

### Configure GRUB

Edit `/etc/default/grub`:

```bash
sudo nano /etc/default/grub
```

Append to `GRUB_CMDLINE_LINUX`:

```
i915.enable_guc=3 i915.max_vfs=7 i915.force_probe=*
```

Example:

```
GRUB_CMDLINE_LINUX="i915.enable_guc=3 i915.max_vfs=7 i915.force_probe=* console=tty0 console=ttyS0,115200n8"
```

Apply and reboot:

```bash
sudo update-grub
sudo reboot
```

### Parameter reference

| Parameter | Purpose |
|-----------|---------|
| `i915.enable_guc=3` | Enable GuC submission + HuC loading (required for SR-IOV PF) |
| `i915.max_vfs=7` | Pre-allocate resources for up to N Virtual Functions |
| `i915.force_probe=*` | Force i915 to probe all supported device IDs |

---

## 2) Activate Virtual Functions

After booting with SR-IOV enabled:

```bash
# Check PF is visible and SR-IOV capable
lspci -d 8086: -nn | grep VGA

# Confirm VF capacity
cat /sys/bus/pci/devices/0000:00:02.0/sriov_totalvfs

# Create 2 VFs
echo 2 | sudo tee /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# Verify VFs appeared
lspci -d 8086: -nn | grep -i "virtual"
```

### Persist across reboots

To persist VF creation across reboots, add a udev rule or a systemd service that
writes to `sriov_numvfs` after the PF is bound.
