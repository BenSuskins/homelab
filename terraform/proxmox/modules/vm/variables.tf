variable "name" {
  description = "VM name (hostname)"
  type        = string
}

variable "username" {
  description = "Login user cloud-init creates (matches the Ansible ansible_user). Defaults to the VM name."
  type        = string
  default     = null
}

variable "vm_id" {
  description = "Numeric Proxmox VM ID"
  type        = number
}

variable "node_name" {
  description = "Proxmox node the VM is created on"
  type        = string
}

variable "clone_template_id" {
  description = "VM ID of the cloud-init template to clone from"
  type        = number
  default     = 9000
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Dedicated memory in MiB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Primary disk size in GiB"
  type        = number
  default     = 64
}

variable "datastore_id" {
  description = "Datastore for the VM disk (e.g. local-zfs, local-lvm)"
  type        = string
  default     = "local-zfs"
}

variable "bridge" {
  description = "Network bridge for the primary NIC"
  type        = string
  default     = "vmbr0"
}

variable "ip_address" {
  description = "Static IPv4 address in CIDR notation for cloud-init, e.g. 192.168.0.110/24. Use \"dhcp\" for DHCP."
  type        = string
}

variable "gateway" {
  description = "IPv4 gateway for cloud-init (ignored when ip_address is \"dhcp\")"
  type        = string
  default     = "192.168.0.1"
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to inject via cloud-init"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the VM"
  type        = list(string)
  default     = ["terraform"]
}

# --- Identity & lifecycle ---

variable "reboot_after_update" {
  description = "Allow Proxmox to restart the VM when an update requires it."
  type        = bool
  default     = true
}

variable "description" {
  description = "Free-text description shown in the Proxmox UI"
  type        = string
  default     = null
}

variable "pool_id" {
  description = "Resource pool to place the VM in (e.g. for pool-targeted backup jobs)"
  type        = string
  default     = null
}

variable "protection" {
  description = "Protect the VM from removal/disk deletion"
  type        = bool
  default     = false
}

variable "on_boot" {
  description = "Start the VM automatically when the node boots"
  type        = bool
  default     = true
}

variable "started" {
  description = "Whether the VM should be running"
  type        = bool
  default     = true
}

variable "agent_enabled" {
  description = "Wait for the QEMU guest agent. Requires qemu-guest-agent in the template (it is baked into ours)."
  type        = bool
  default     = true
}

# --- Boot ordering ---

variable "startup_order" {
  description = "Boot/shutdown order. When null, no startup config is set."
  type        = number
  default     = null
}

variable "startup_up_delay" {
  description = "Seconds to wait after this VM starts before starting the next (requires startup_order)"
  type        = number
  default     = null
}

variable "startup_down_delay" {
  description = "Seconds to wait after this VM stops before stopping the next (requires startup_order)"
  type        = number
  default     = null
}

# --- Firmware / chipset ---

variable "bios" {
  description = "BIOS implementation: seabios or ovmf"
  type        = string
  default     = "ovmf"
}

variable "machine" {
  description = "Machine type, e.g. i440 or q35"
  type        = string
  default     = "q35"
}

variable "tablet_device" {
  description = "Enable the USB tablet pointer device"
  type        = bool
  default     = true
}

# --- CPU ---

variable "cpu_sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "cpu_type" {
  description = "Emulated CPU type (host gives best performance on a homogeneous cluster)"
  type        = string
  default     = "host"
}

variable "cpu_numa" {
  description = "Enable NUMA"
  type        = bool
  default     = false
}

variable "cpu_flags" {
  description = "CPU flags, e.g. [\"+aes\"]"
  type        = list(string)
  default     = []
}

# --- Memory ---

variable "memory_floating" {
  description = "Minimum memory in MiB for ballooning. 0 disables ballooning (fixed memory). Set equal to memory to enable."
  type        = number
  default     = 0
}

# --- Disk ---

variable "disk_ssd" {
  description = "Present the disk as an SSD to the guest (rotational=0, so guest IO schedulers stop seek-optimising). Correct here: local-zfs is backed by a single SSD."
  type        = bool
  default     = true
}

variable "disk_discard" {
  description = "TRIM/discard handling: on or ignore. On passes guest fstrim down to ZFS, so freed guest blocks are released rather than held forever — this is what keeps pool free space coalescing into large contiguous runs."
  type        = string
  default     = "on"
}

variable "disk_iothread" {
  description = "Use a dedicated iothread for the disk"
  type        = bool
  default     = false
}

variable "disk_cache" {
  description = "Disk cache mode: none, directsync, writethrough, writeback, unsafe"
  type        = string
  default     = "none"
}

variable "disk_backup" {
  description = "Include this disk when vzdump backup jobs run"
  type        = bool
  default     = true
}

variable "disk_replicate" {
  description = "Include this disk in storage replication jobs"
  type        = bool
  default     = true
}

# --- Network ---

variable "network_model" {
  description = "NIC model: virtio, e1000, e1000e, vmxnet3, rtl8139"
  type        = string
  default     = "virtio"
}

variable "vlan_id" {
  description = "VLAN tag for the primary NIC (null = untagged)"
  type        = number
  default     = null
}

variable "network_mac_address" {
  description = "Static MAC for the primary NIC (null = auto). Set this to pin a DHCP reservation."
  type        = string
  default     = null
}

variable "network_firewall" {
  description = "Enable the Proxmox firewall on the primary NIC"
  type        = bool
  default     = false
}

variable "network_rate_limit" {
  description = "NIC rate limit in MB/s (null = unlimited)"
  type        = number
  default     = null
}
