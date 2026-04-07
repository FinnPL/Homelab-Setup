data "oci_core_images" "ubuntu" {
  compartment_id           = var.oci_compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

# Compute Instance (Always Free ARM)
resource "oci_core_instance" "edge" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
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
      sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
      systemctl restart sshd
    EOF
    )
  }

  # Prevent replacement after nixos-anywhere has installed NixOS
  lifecycle {
    ignore_changes = [
      source_details[0].source_id,
      metadata,
    ]
  }
}
