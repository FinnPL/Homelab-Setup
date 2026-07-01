{{- define "gateway-external-routes.renderNginxConf" -}}
{{- $backend := .backend -}}
{{- $proxy := .proxy -}}
{{- $upstreamName := printf "%s_upstream" ($backend.name | replace "-" "_") -}}
{{- if $backend.endpoints }}
upstream {{ $upstreamName }} {
{{- range $backend.endpoints }}
  server {{ . }}:{{ default $backend.servicePort $backend.upstreamPort }};
{{- end }}
}

{{ end -}}
server {
  listen {{ $proxy.containerPort }};
  error_log /dev/stderr warn;
  access_log off;
{{- if $backend.upstreamHost }}
  resolver {{ $proxy.resolver }} valid=10s ipv6=off;
{{- end }}

  location / {
{{- $protocol := default "http" $backend.upstreamProtocol }}
{{- if $backend.endpoints }}
    proxy_pass {{ $protocol }}://{{ $upstreamName }};
{{- else }}
    set $upstream "{{ $backend.upstreamHost }}:{{ $backend.upstreamPort }}";
    proxy_pass {{ $protocol }}://$upstream;
{{- end }}
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
{{- if $backend.enableWebsockets }}
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
{{- else }}
    proxy_set_header Connection "";
{{- end }}
{{- if eq $protocol "https" }}
    proxy_ssl_verify off;
    proxy_ssl_server_name on;
{{- if $backend.upstreamHost }}
    proxy_ssl_name {{ $backend.upstreamHost }};
{{- end }}
{{- end }}
  }
}
{{- end }}

{{- define "gateway-external-routes.renderBackendProxy" -}}
{{- $root := .root -}}
{{- $backend := .backend -}}
{{- $namespace := $root.Values.namespace -}}
{{- $gateway := $root.Values.gateway -}}
{{- $proxy := $root.Values.proxy -}}
{{- $nginxConf := include "gateway-external-routes.renderNginxConf" (dict "backend" $backend "proxy" $proxy) -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $backend.name }}-external-proxy-nginx
  namespace: {{ $namespace }}
data:
  default.conf: |
{{ $nginxConf | indent 4 }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $backend.name }}-external-proxy
  namespace: {{ $namespace }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ $backend.name }}-external-proxy
  template:
    metadata:
      labels:
        app: {{ $backend.name }}-external-proxy
      annotations:
        checksum/nginx-conf: {{ $nginxConf | sha256sum }}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: nginx
          image: {{ $proxy.image }}
          ports:
            - name: http
              containerPort: {{ $proxy.containerPort }}
              protocol: TCP
          resources:
            {{- toYaml $proxy.resources | nindent 12 }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
              readOnly: true
            - name: nginx-cache
              mountPath: /var/cache/nginx
            - name: nginx-tmp
              mountPath: /tmp
      volumes:
        - name: nginx-conf
          configMap:
            name: {{ $backend.name }}-external-proxy-nginx
        - name: nginx-cache
          emptyDir:
            medium: Memory
        - name: nginx-tmp
          emptyDir:
            medium: Memory
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $backend.name }}-external
  namespace: {{ $namespace }}
spec:
  selector:
    app: {{ $backend.name }}-external-proxy
  ports:
    - name: http
      port: {{ $backend.servicePort }}
      targetPort: {{ $proxy.containerPort }}
      protocol: TCP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $backend.name }}
  namespace: {{ $namespace }}
spec:
  parentRefs:
    - name: {{ $gateway.name }}
      namespace: {{ $gateway.namespace }}
      sectionName: {{ $gateway.sectionName }}
  hostnames:
    - {{ $backend.hostname | quote }}
  rules:
    - backendRefs:
        - name: {{ $backend.name }}-external
          port: {{ $backend.servicePort }}
---
{{- end }}
