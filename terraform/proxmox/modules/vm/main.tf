terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  description = var.description
  vm_id       = var.vm_id
  node_name   = var.node_name
  tags        = var.tags
  pool_id     = var.pool_id

  reboot_after_update = var.reboot_after_update

  on_boot       = var.on_boot
  started       = var.started
  protection    = var.protection
  bios          = var.bios
  machine       = var.machine
  tablet_device = var.tablet_device

  clone {
    vm_id = var.clone_template_id
  }

  agent {
    enabled = var.agent_enabled
  }

  dynamic "startup" {
    for_each = var.startup_order == null ? [] : [1]
    content {
      order      = var.startup_order
      up_delay   = var.startup_up_delay
      down_delay = var.startup_down_delay
    }
  }

  cpu {
    cores   = var.cores
    sockets = var.cpu_sockets
    type    = var.cpu_type
    numa    = var.cpu_numa
    flags   = var.cpu_flags
  }

  memory {
    dedicated = var.memory
    floating  = var.memory_floating
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size
    ssd          = var.disk_ssd
    discard      = var.disk_discard
    iothread     = var.disk_iothread
    cache        = var.disk_cache
    backup       = var.disk_backup
    replicate    = var.disk_replicate
  }

  network_device {
    bridge      = var.bridge
    model       = var.network_model
    vlan_id     = var.vlan_id
    mac_address = var.network_mac_address
    firewall    = var.network_firewall
    rate_limit  = var.network_rate_limit
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.ip_address == "dhcp" ? null : var.gateway
      }
    }

    user_account {
      username = coalesce(var.username, var.name)
      keys     = var.ssh_public_keys
    }
  }
}
