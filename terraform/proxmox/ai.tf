module "ai" {
  source          = "./modules/vm"
  name            = "ai"
  vm_id           = 206
  node_name       = var.proxmox_node
  cores           = 8
  memory          = 4096
  memory_floating = 4096
  disk_size       = 128
  ip_address      = "192.168.0.206/24"
  ssh_public_keys = [trimspace(file("~/.ssh/homelab.pub"))]
  description     = "AI / OpenClaw Agent Host"
  startup_order   = 6
}
