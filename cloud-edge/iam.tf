resource "oci_identity_dynamic_group" "edge_ccm" {
  compartment_id = local.oci_tenancy_ocid
  name           = "${var.instance_name}-ccm-dg"
  description    = "Edge instance(s) allowed to run OCI cloud-controller-manager via instance principal"
  matching_rule  = "instance.id = '${oci_core_instance.edge.id}'"
}

resource "oci_identity_policy" "edge_ccm" {
  compartment_id = local.oci_compartment_ocid
  name           = "${var.instance_name}-ccm-policy"
  description    = "Allow edge CCM to manage load balancers and read networking in this compartment"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.edge_ccm.name} to manage load-balancers in compartment id ${local.oci_compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.edge_ccm.name} to manage network-load-balancers in compartment id ${local.oci_compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.edge_ccm.name} to use virtual-network-family in compartment id ${local.oci_compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.edge_ccm.name} to use instance-family in compartment id ${local.oci_compartment_ocid}",
  ]
}
