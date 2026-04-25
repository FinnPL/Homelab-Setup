resource "oci_core_vcn" "edge" {
  compartment_id = local.oci_compartment_ocid
  display_name   = "edge-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "edgevcn"
}

resource "oci_core_internet_gateway" "edge" {
  compartment_id = local.oci_compartment_ocid
  vcn_id         = oci_core_vcn.edge.id
  display_name   = "edge-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = local.oci_compartment_ocid
  vcn_id         = oci_core_vcn.edge.id
  display_name   = "edge-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.edge.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_security_list" "edge" {
  compartment_id = local.oci_compartment_ocid
  vcn_id         = oci_core_vcn.edge.id
  display_name   = "edge-security-list"

  # Egress: Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  # Ingress: HTTPS (443) — HAProxy TLS passthrough
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Ingress: Tailscale WireGuard (UDP 41641)
  ingress_security_rules {
    protocol  = "17" # UDP
    source    = "0.0.0.0/0"
    stateless = false

    udp_options {
      min = 41641
      max = 41641
    }
  }

  # Ingress: WireGuard tunnel to homelab mesh-router (UDP 51820)
  ingress_security_rules {
    protocol  = "17" # UDP
    source    = "0.0.0.0/0"
    stateless = false

    udp_options {
      min = 51820
      max = 51820
    }
  }

  # Ingress: SSH (22)
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress: ICMP (for path MTU discovery)
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = "0.0.0.0/0"
    stateless = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = var.vcn_cidr
    stateless = false

    icmp_options {
      type = 3
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = local.oci_compartment_ocid
  vcn_id                     = oci_core_vcn.edge.id
  display_name               = "edge-public-subnet"
  cidr_block                 = var.public_subnet_cidr
  dns_label                  = "edgepub"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.edge.id]
  prohibit_public_ip_on_vnic = false
}
