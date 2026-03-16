resource "kubectl_manifest" "apollo_external_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "apollo-external"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      type         = "ExternalName"
      externalName = "apollo.athena"
      ports = [
        {
          name     = "http"
          port     = 5000
          protocol = "TCP"
        }
      ]
    }
  })
}

resource "kubectl_manifest" "apollo_http_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "apollo"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name        = "main-gateway"
          namespace   = kubernetes_namespace_v1.gateway.metadata[0].name
          sectionName = "https"
        }
      ]
      hostnames = [
        "apollo.lippok.dev"
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "apollo-external"
              port = 5000
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.main_gateway,
    kubectl_manifest.apollo_external_service
  ]
}

resource "kubectl_manifest" "zeus_external_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "zeus-external"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      type         = "ExternalName"
      externalName = "zeus.athena"
      ports = [
        {
          name     = "http"
          port     = 80
          protocol = "TCP"
        }
      ]
    }
  })
}

resource "kubectl_manifest" "zeus_http_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "zeus"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name        = "main-gateway"
          namespace   = kubernetes_namespace_v1.gateway.metadata[0].name
          sectionName = "https"
        }
      ]
      hostnames = [
        "zeus.lippok.dev"
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "zeus-external"
              port = 80
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.main_gateway,
    kubectl_manifest.zeus_external_service
  ]
}

resource "kubectl_manifest" "fritzbox_external_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "fritzbox-external"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      ports = [
        {
          name     = "http"
          port     = 80
          protocol = "TCP"
        }
      ]
    }
  })
}

resource "kubectl_manifest" "fritzbox_external_endpoints" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Endpoints"
    metadata = {
      name      = "fritzbox-external"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    subsets = [
      {
        addresses = [
          {
            ip = "192.168.178.1"
          }
        ]
        ports = [
          {
            name     = "http"
            port     = 80
            protocol = "TCP"
          }
        ]
      }
    ]
  })

  depends_on = [kubectl_manifest.fritzbox_external_service]
}

resource "kubectl_manifest" "fritzbox_http_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "fritzbox"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name        = "main-gateway"
          namespace   = kubernetes_namespace_v1.gateway.metadata[0].name
          sectionName = "https"
        }
      ]
      hostnames = [
        "fb.lippok.dev"
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "fritzbox-external"
              port = 80
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.main_gateway,
    kubectl_manifest.fritzbox_external_service,
    kubectl_manifest.fritzbox_external_endpoints
  ]
}
