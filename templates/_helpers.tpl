{{- define "labk8stack.name" -}}
labk8stack
{{- end -}}

{{- define "labk8stack.fullname" -}}
{{- .Release.Name | trunc 45 | trimSuffix "-" -}}
{{- end -}}

{{- define "labk8stack.labels" -}}
app.kubernetes.io/name: {{ include "labk8stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "labk8stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "labk8stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "labk8stack.image" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- $tag := required "image.tag is required" .Values.image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}

{{- define "labk8stack.dbSecret" -}}
{{- $cluster := required "database.clusterName is required" .Values.database.clusterName -}}
{{- $dbNamespace := default .Release.Namespace .Values.database.namespace -}}
{{- if ne $dbNamespace .Release.Namespace -}}
{{- required "database.appSecretName is required when CNPG is in another namespace; create a local Secret with a cross-namespace URI" .Values.database.appSecretName -}}
{{- else if .Values.database.appSecretName -}}
{{- .Values.database.appSecretName -}}
{{- else -}}
{{- printf "%s-app" $cluster -}}
{{- end -}}
{{- end -}}

{{- define "labk8stack.appSecret" -}}
{{- required "app.configSecretName is required" .Values.app.configSecretName -}}
{{- end -}}
