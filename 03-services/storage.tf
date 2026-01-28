resource "helm_release" "csi_driver_nfs" {
  name       = "csi-driver-nfs"
  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts" 
  chart      = "csi-driver-nfs"
  version    = "4.12.0"
  namespace  = "kube-system"
}

resource "kubernetes_storage_class_v1" "nfs" {
  metadata {
    name = "nfs-client"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "nfs.csi.k8s.io"
  reclaim_policy      = "Delete"
  parameters = {
    server = data.terraform_remote_state.infrastructure.outputs.nfs_server.ip
    share  = data.terraform_remote_state.infrastructure.outputs.nfs_server.export_path
  }
  mount_options = ["nfsvers=4.1"]
  depends_on    = [helm_release.csi_driver_nfs]
}