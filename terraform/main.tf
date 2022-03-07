terraform {
  required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.14"
    }
  }
}

# variables that can be overriden
variable "hostname" {
  type    = list(string)
  default = ["rke2lb", "rke2master", "rke2worker1", "rke2worker2"]
}

variable "addresses" {
  type    = list(string)
  default = ["192.168.122.90", "192.168.122.91", "192.168.122.92", "192.168.122.93"]
}

#variable "hostname" { default = "vm_u20" }
variable "domain" { default = "lcw.dev" }

variable "memoryMB" {
  type    = list(number)
  default = [1024, 4096, 4096, 4096]
}

variable "cpu" {
  type    = list(number)
  default = [1, 3, 3, 3]
}

# instance the provider
provider "libvirt" {
  uri = "qemu:///system"
}

# fetch the latest ubuntu release image from their mirrors.
#when ising cloud image- now allowed to increase disk-size
#only on localy downloaded image with command:
#qemu-img resize images/focal-server-cloudimg-amd64-disk-kvm.img 10G
resource "libvirt_volume" "os_image" {
  count = length(var.hostname)
  name  = "os_image.${var.hostname[count.index]}"
  pool  = "default"
  #source = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-disk-kvm.img"
  #source = "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2"
  source = "/home/emrah/images/cloud_images/focal-server-cloudimg-amd64-disk-kvm.img" #
  format = "qcow2"
}

# Use CloudInit ISO to add ssh-key to the instance
resource "libvirt_cloudinit_disk" "commoninit" {
  count = length(var.hostname)
  name  = "${var.hostname[count.index]}-commoninit.iso"
  #name = "${var.hostname}-commoninit.iso"
  # pool = "default"
  user_data      = data.template_file.user_data[count.index].rendered
  network_config = data.template_file.network_config.rendered
}

data "template_file" "user_data" {
  count    = length(var.hostname)
  template = file("${path.module}/cloud_init_ubuntu.cfg")
  vars = {
    hostname = element(var.hostname, count.index)
    fqdn     = "${var.hostname[count.index]}.${var.domain}"
  }
}

data "template_file" "network_config" {
  template = file("${path.module}/network_config_dhcp.cfg")
}

# Create the machine
resource "libvirt_domain" "domain-ubuntu" {
  count  = length(var.hostname)
  name   = var.hostname[count.index]
  memory = var.memoryMB[count.index]
  vcpu   = var.cpu[count.index]
  disk {
    volume_id = element(libvirt_volume.os_image.*.id, count.index)
  }

  network_interface {
    network_name   = "default"
    hostname       = var.hostname[count.index]
    addresses      = [var.addresses[count.index]]
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  # IMPORTANT
  # Ubuntu can hang is a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = "true"
  }
}

terraform {
  required_version = ">= 0.12"
}

output "ips" {
  # show IP, run 'terraform refresh' if not populated
  value = libvirt_domain.domain-ubuntu.*.network_interface.0.addresses
}
