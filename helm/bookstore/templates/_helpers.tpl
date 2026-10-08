{{/* ---------- Names ---------- */}}
{{- define "bookstore.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "bookstore.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "bookstore.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Component resource name.
Usage: include "bookstore.componentName" (dict "root" $ "component" "website")
*/}}
{{- define "bookstore.componentName" -}}
{{- if and (eq .component "proxy") .root.Values.proxy.fullnameOverride }}
{{- .root.Values.proxy.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if eq .component "database" }}
{{- printf "%s-mysql" (include "bookstore.fullname" .root) | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" (include "bookstore.fullname" .root) .component | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* ---------- Labels ---------- */}}
{{- define "bookstore.labels" -}}
app.kubernetes.io/name: {{ include "bookstore.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{ include "bookstore.baseLabels" . }}
{{- end }}

{{/* Labels that are never part of a selector */}}
{{- define "bookstore.baseLabels" -}}
helm.sh/chart: {{ include "bookstore.chart" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: bookstore
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels for a component. Keeps the legacy `app: <name>` label so the
Service selectors match the original manifests (e.g. app: stateless-app).
*/}}
{{- define "bookstore.selectorLabels" -}}
app: {{ include "bookstore.componentName" . }}
app.kubernetes.io/name: {{ include "bookstore.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "bookstore.componentLabels" -}}
{{ include "bookstore.baseLabels" .root }}
{{ include "bookstore.selectorLabels" . }}
{{- end }}

{{/* ---------- Images ---------- */}}
{{- define "bookstore.image" -}}
{{- $reg := .root.Values.global.imageRegistry -}}
{{- if $reg -}}
{{- printf "%s/%s:%s" (trimSuffix "/" $reg) .image.repository (toString .image.tag) -}}
{{- else -}}
{{- printf "%s:%s" .image.repository (toString .image.tag) -}}
{{- end -}}
{{- end }}

{{- define "bookstore.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* ---------- Service accounts ---------- */}}
{{- define "bookstore.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "bookstore.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "bookstore.legacyServiceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (printf "%s-legacy" (include "bookstore.fullname" .)) .Values.serviceAccount.legacyName }}
{{- else }}
{{- default "default" .Values.serviceAccount.legacyName }}
{{- end }}
{{- end }}

{{/*
Pod securityContext. On OpenShift, fixed IDs are removed so the SCC can assign
them - except for legacy pods running under anyuid, which keep what is set.
Usage: include "bookstore.podSecurityContext" (dict "root" $ "ctx" .Values.x.podSecurityContext "legacy" false)
*/}}
{{- define "bookstore.podSecurityContext" -}}
{{- $psc := deepCopy (default dict .ctx) -}}
{{- if and .root.Values.openshift.enabled (not (and .legacy .root.Values.openshift.legacyAppsAnyuid)) -}}
{{- $_ := unset $psc "runAsUser" -}}
{{- $_ := unset $psc "runAsGroup" -}}
{{- $_ := unset $psc "fsGroup" -}}
{{- end -}}
{{- with $psc }}
securityContext:
{{ toYaml . | indent 2 }}
{{- end }}
{{- end }}

{{/* Container securityContext, same OpenShift handling. */}}
{{- define "bookstore.containerSecurityContext" -}}
{{- $sc := deepCopy (default dict .ctx) -}}
{{- if and .root.Values.openshift.enabled (not (and .legacy .root.Values.openshift.legacyAppsAnyuid)) -}}
{{- $_ := unset $sc "runAsUser" -}}
{{- $_ := unset $sc "runAsGroup" -}}
{{- end -}}
{{- with $sc }}
securityContext:
{{ toYaml . | indent 2 }}
{{- end }}
{{- end }}

{{/*
Scheduling block: component values win over .Values.defaults.
Usage: include "bookstore.scheduling" (dict "root" $ "c" .Values.website)
*/}}
{{- define "bookstore.scheduling" -}}
{{- $d := .root.Values.defaults -}}
{{- with (default $d.nodeSelector .c.nodeSelector) }}
nodeSelector:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with (default $d.tolerations .c.tolerations) }}
tolerations:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with (default $d.affinity .c.affinity) }}
affinity:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with (default $d.topologySpreadConstraints .c.topologySpreadConstraints) }}
topologySpreadConstraints:
{{ toYaml . | indent 2 }}
{{- end }}
{{- end }}

{{/* ---------- Database connection ---------- */}}
{{- define "bookstore.db.host" -}}
{{- if .Values.database.enabled -}}
{{- include "bookstore.componentName" (dict "root" . "component" "database") -}}
{{- else -}}
{{- required "externalDatabase.host is required when database.enabled=false" .Values.externalDatabase.host -}}
{{- end -}}
{{- end }}

{{- define "bookstore.db.port" -}}
{{- if .Values.database.enabled }}{{ .Values.database.service.port }}{{ else }}{{ .Values.externalDatabase.port }}{{ end -}}
{{- end }}

{{- define "bookstore.db.name" -}}
{{- if .Values.database.enabled }}{{ .Values.database.auth.database }}{{ else }}{{ .Values.externalDatabase.database }}{{ end -}}
{{- end }}

{{- define "bookstore.db.user" -}}
{{- if .Values.database.enabled }}{{ .Values.database.auth.username }}{{ else }}{{ .Values.externalDatabase.username }}{{ end -}}
{{- end }}

{{/* Secret holding the DB passwords */}}
{{- define "bookstore.db.secretName" -}}
{{- if and .Values.database.enabled .Values.database.auth.existingSecret -}}
{{- .Values.database.auth.existingSecret -}}
{{- else if and (not .Values.database.enabled) .Values.externalDatabase.existingSecret -}}
{{- .Values.externalDatabase.existingSecret -}}
{{- else -}}
{{- printf "%s-db-credentials" (include "bookstore.fullname" .) -}}
{{- end -}}
{{- end }}

{{/* Key in that secret holding the application user's password */}}
{{- define "bookstore.db.userPasswordKey" -}}
{{- if and (not .Values.database.enabled) .Values.externalDatabase.existingSecret -}}
{{- .Values.externalDatabase.existingSecretPasswordKey -}}
{{- else -}}
{{- .Values.database.auth.secretKeys.userPassword -}}
{{- end -}}
{{- end }}

{{- define "bookstore.db.createSecret" -}}
{{- if .Values.database.enabled -}}
{{- if not .Values.database.auth.existingSecret }}true{{ end -}}
{{- else -}}
{{- if not .Values.externalDatabase.existingSecret }}true{{ end -}}
{{- end -}}
{{- end }}

{{/*
initContainer that blocks until MySQL accepts the app user's credentials.
Reuses the MySQL image (client tools) so no extra image is required.
*/}}
{{- define "bookstore.waitForDb" -}}
- name: wait-for-db
  image: {{ include "bookstore.image" (dict "root" . "image" .Values.database.image) }}
  imagePullPolicy: {{ .Values.database.image.pullPolicy }}
  command:
    - sh
    - -c
    - |
      echo "waiting for MySQL at ${DB_HOST}:${DB_PORT}..."
      until mysqladmin ping -h "${DB_HOST}" -P "${DB_PORT}" -u"${DB_USER}" -p"${DB_PASSWORD}" --silent; do
        sleep 3
      done
      echo "MySQL is up"
  env:
    - name: DB_HOST
      value: {{ include "bookstore.db.host" . | quote }}
    - name: DB_PORT
      value: {{ include "bookstore.db.port" . | quote }}
    - name: DB_USER
      value: {{ include "bookstore.db.user" . | quote }}
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ include "bookstore.db.secretName" . }}
          key: {{ include "bookstore.db.userPasswordKey" . }}
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      memory: 128Mi
{{- end }}

{{/* Resolve a proxy route to "host:port". */}}
{{- define "bookstore.proxy.upstream" -}}
{{- $root := .root -}}
{{- if .route.upstream -}}
{{- .route.upstream -}}
{{- else -}}
{{- $c := required (printf "proxy.routes[%s]: set either component or upstream" .route.path) .route.component -}}
{{- if not (has $c (list "website" "shopui" "shopapi")) -}}
{{- fail (printf "proxy.routes[%s]: unknown component %q (website|shopui|shopapi)" .route.path $c) -}}
{{- end -}}
{{- $cv := index $root.Values $c -}}
{{- if not $cv.enabled -}}
{{- fail (printf "proxy.routes[%s] points to %s, but %s.enabled=false" .route.path $c $c) -}}
{{- end -}}
{{- printf "%s.%s.svc.%s:%v" (include "bookstore.componentName" (dict "root" $root "component" $c)) $root.Release.Namespace $root.Values.clusterDomain $cv.service.port -}}
{{- end -}}
{{- end }}
