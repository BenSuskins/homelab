module "mediaserver" {
  source          = "./modules/vm"
  name            = "mediaserver"
  vm_id           = 201
  node_name       = var.proxmox_node
  cores           = 4
  memory          = 6144
  memory_floating = 4096
  disk_size       = 64
  ip_address      = "192.168.0.201/24"
  ssh_public_keys = [trimspace(file("~/.ssh/homelab.pub"))]
  description     = "Media Server"

  # Boots last so the NAS has time to come up first; the 240s gap is set as
  # gateway's up_delay (the preceding guest), since Proxmox up_delay
  # applies before the NEXT guest starts.
  startup_order = 5
}
