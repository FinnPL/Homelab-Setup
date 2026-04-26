data "oci_core_images" "ubuntu" {
  compartment_id           = local.oci_compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = local.oci_tenancy_ocid
}

locals {
  instance_availability_domain = trimspace(var.instance_availability_domain) != "" ? trimspace(var.instance_availability_domain) : data.oci_identity_availability_domains.ads.availability_domains[var.instance_availability_domain_index].name
}

# Compute Instance (Always Free ARM)
resource "oci_core_instance" "edge" {
  compartment_id      = local.oci_compartment_ocid
  availability_domain = local.instance_availability_domain
  display_name        = var.instance_name
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.instance_boot_volume_gb
  }

  create_vnic_details {
    subnet_id                 = oci_core_subnet.public.id
    assign_public_ip          = true
    assign_private_dns_record = true
    display_name              = "${var.instance_name}-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    # OCI Ubuntu adds SSH keys to the 'ubuntu' user, not root.
    # nixos-anywhere needs root access, so bootstrap root SSH via cloud-init.
    user_data = base64encode(<<-EOF
      #!/bin/bash
      mkdir -p /root/.ssh
      cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
      install -d -m 0755 /etc/ssh/sshd_config.d
      printf '%s\n' 'PermitRootLogin prohibit-password' > /etc/ssh/sshd_config.d/00-cloud-init-root-login.conf
      chmod 644 /etc/ssh/sshd_config.d/00-cloud-init-root-login.conf
      systemctl restart sshd
    EOF
    )
  }

  lifecycle {
    ignore_changes = [
      availability_domain,
      source_details[0].source_id,
      metadata,
    ]
    replace_triggered_by = [oci_core_vcn.edge]
  }
}
