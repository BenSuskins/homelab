module "bumblebee" {
  source          = "./modules/vm"
  name            = "bumblebee"
  vm_id           = 200
  node_name       = var.proxmox_node
  cores           = 4
  memory          = 1536
  memory_floating = 1024
  disk_size       = 128
  ip_address      = "192.168.0.200/24"
  ssh_public_keys = [trimspace(file("~/.ssh/homelab.pub"))]
  description     = "Github Actions Runner"
  startup_order   = 1

  # This VM runs Terraform applies and must stay up until they finish.
  reboot_after_update = false
}
