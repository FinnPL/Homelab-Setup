{{- define "cnpg.crossplane.commonResources" -}}
- name: role-v2
  base:
    apiVersion: postgresql.sql.crossplane.io/v1alpha1
    kind: Role
    spec:
      forProvider:
        privileges:
          login: true
          createDb: false
      providerConfigRef:
        name: default
      writeConnectionSecretToRef:
        namespace: crossplane-system
        name: role-conn
  patches:
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: metadata.name
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.providerConfigName
      toFieldPath: spec.providerConfigRef.name
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.writeConnectionSecretToRef.name
      transforms:
        - type: string
          string:
            type: Format
            fmt: "%s-role"
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.providerConnectionSecretNamespace
      toFieldPath: spec.writeConnectionSecretToRef.namespace
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.createDb
      toFieldPath: spec.forProvider.privileges.createDb
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.deletionPolicy
      toFieldPath: spec.deletionPolicy
      policy:
        fromFieldPath: Optional
    - type: CombineFromComposite
      combine:
        variables:
          - fromFieldPath: {{ .endpointNameFromFieldPath | quote }}
          - fromFieldPath: spec.parameters.clusterNamespace
          - fromFieldPath: spec.parameters.clusterDomain
        strategy: string
        string:
          fmt: "%s-pooler-rw.%s.svc.%s"
      toFieldPath: metadata.annotations[database.lippok.dev/pooler-endpoint]
  connectionDetails:
    - type: FromConnectionSecretKey
      name: username
      fromConnectionSecretKey: username
    - type: FromConnectionSecretKey
      name: password
      fromConnectionSecretKey: password
    - type: FromFieldPath
      name: endpoint
      fromFieldPath: metadata.annotations[database.lippok.dev/pooler-endpoint]
    - type: FromValue
      name: port
      value: "5432"

- name: database
  base:
    apiVersion: postgresql.sql.crossplane.io/v1alpha1
    kind: Database
    spec:
      forProvider:
        encoding: UTF8
        owner: placeholder
      providerConfigRef:
        name: default
      deletionPolicy: Orphan
  patches:
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.databaseName
      toFieldPath: metadata.name
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.providerConfigName
      toFieldPath: spec.providerConfigRef.name
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.owner
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.deletionPolicy
      toFieldPath: spec.deletionPolicy
      policy:
        fromFieldPath: Optional

- name: grant
  base:
    apiVersion: postgresql.sql.crossplane.io/v1alpha1
    kind: Grant
    spec:
      forProvider:
        privileges:
          - ALL
        roleRef:
          name: placeholder
        databaseRef:
          name: placeholder
      providerConfigRef:
        name: default
      deletionPolicy: Orphan
  patches:
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.databaseName
      toFieldPath: metadata.name
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.providerConfigName
      toFieldPath: spec.providerConfigRef.name
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.roleRef.name
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.databaseName
      toFieldPath: spec.forProvider.databaseRef.name
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.privileges
      toFieldPath: spec.forProvider.privileges
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.deletionPolicy
      toFieldPath: spec.deletionPolicy
      policy:
        fromFieldPath: Optional
{{- end -}}

{{- define "cnpg.crossplane.dedicatedPoolerResource" -}}
- name: dedicated-pooler
  base:
    apiVersion: postgresql.cnpg.io/v1
    kind: Pooler
    metadata:
      namespace: cnpg-system
      name: dedicated-pooler
    spec:
      cluster:
        name: cnpg-cluster
      instances: 1
      type: rw
      pgbouncer:
        poolMode: transaction
        parameters:
          max_client_conn: "200"
          default_pool_size: "20"
          min_pool_size: "5"
          reserve_pool_size: "5"
          reserve_pool_timeout: "5"
  patches:
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: metadata.name
      transforms:
        - type: string
          string:
            type: Format
            fmt: "%s-pooler-rw"
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.clusterNamespace
      toFieldPath: metadata.namespace
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.clusterName
      toFieldPath: spec.cluster.name
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.dedicatedPoolerInstances
      toFieldPath: spec.instances
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.dedicatedPoolerPoolMode
      toFieldPath: spec.pgbouncer.poolMode
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.dedicatedPoolerMaxClientConn
      toFieldPath: spec.pgbouncer.parameters.max_client_conn
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.dedicatedPoolerDefaultPoolSize
      toFieldPath: spec.pgbouncer.parameters.default_pool_size
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.dedicatedPoolerMinPoolSize
      toFieldPath: spec.pgbouncer.parameters.min_pool_size
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.dedicatedPoolerReservePoolSize
      toFieldPath: spec.pgbouncer.parameters.reserve_pool_size
      policy:
        fromFieldPath: Optional
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.dedicatedPoolerReservePoolTimeout
      toFieldPath: spec.pgbouncer.parameters.reserve_pool_timeout
      policy:
        fromFieldPath: Optional
  readinessChecks:
    - type: NonEmpty
      fieldPath: status.instances
{{- end -}}