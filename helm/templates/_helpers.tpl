{{- define "kafka-lab.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kafka-lab.namespace" -}}
{{- default .Values.global.namespace .Release.Namespace }}
{{- end }}

{{- define "kafka-lab.labels" -}}
app.kubernetes.io/name: {{ include "kafka-lab.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "kafka-lab.kafkaBootstrap" -}}
{{ .Values.kafka.name }}-kafka-bootstrap:9092
{{- end }}

{{- define "kafka-lab.kafkaBootstrapPlain" -}}
{{ .Values.kafka.name }}-kafka-bootstrap:9092
{{- end }}

{{- define "kafka-lab.kafkaBootstrapTls" -}}
{{ .Values.kafka.name }}-kafka-bootstrap:9093
{{- end }}
