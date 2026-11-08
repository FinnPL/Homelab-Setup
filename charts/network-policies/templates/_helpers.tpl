{{/* Egress to kube-dns through Cilium's DNS proxy, needed by any pod with toFQDNs rules. */}}
{{- define "np.dnsProxy" -}}
- toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
  toPorts:
    - ports:
        - port: "53"
          protocol: ANY
      rules:
        dns:
          - matchPattern: "*"
{{- end }}

{{- define "np.toApiserver" -}}
- toEntities:
    - kube-apiserver
  toPorts:
    - ports:
        - port: "6443"
          protocol: TCP
{{- end }}

{{/* Calls through the Gateway by public name: the LB IP for the datapath, and each route backend for Envoy.
     Call as (dict "root" $ "via" (list "authentik" ...)), names from .Values.gatewayBackends. */}}
{{- define "np.toGateway" -}}
- toCIDR:
    - {{ .root.Values.gatewayIP }}/32
  toPorts:
    - ports:
        - port: "443"
          protocol: TCP
{{- range .via }}
{{- $b := index $.root.Values.gatewayBackends . }}
- toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: {{ $b.namespace }}
        {{- toYaml $b.labels | nindent 8 }}
  toPorts:
    - ports:
        - port: {{ $b.port | quote }}
          protocol: TCP
{{- end }}
{{- end }}

{{/* Admission webhooks: in tunnel mode the API server's calls arrive from the control plane's router IP, identity remote-node. */}}
{{- define "np.fromApiserver" -}}
- fromEntities:
    - kube-apiserver
    - remote-node
  toPorts:
    - ports:
      {{- range . }}
        - port: {{ . | quote }}
          protocol: TCP
      {{- end }}
{{- end }}

{{- define "np.fromGateway" -}}
- fromEntities:
    - ingress
  toPorts:
    - ports:
      {{- range . }}
        - port: {{ . | quote }}
          protocol: TCP
      {{- end }}
{{- end }}

{{- define "np.fromPrometheus" -}}
- fromEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: monitoring
        app.kubernetes.io/name: prometheus
  toPorts:
    - ports:
      {{- range . }}
        - port: {{ . | quote }}
          protocol: TCP
      {{- end }}
{{- end }}

{{/* Every pod in the namespace may reach the API server (operators, their jobs and hooks; RBAC is the control there). */}}
{{- define "np.namespaceApiserver" -}}
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: apiserver
  namespace: {{ . }}
spec:
  endpointSelector: {}
  egress:
    {{- include "np.toApiserver" . | nindent 4 }}
{{- end }}

{{/* App pods to the CNPG poolers; each database has its own credentials. */}}
{{- define "np.toPooler" -}}
- toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: cnpg-system
        cnpg.io/podRole: pooler
  toPorts:
    - ports:
        - port: "5432"
          protocol: TCP
{{- end }}
