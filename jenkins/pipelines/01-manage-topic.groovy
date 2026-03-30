pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-admin
  containers:
    - name: kubectl
      image: bitnami/kubectl:latest
      command: ["/bin/sh", "-c", "cat"]
      tty: true
      securityContext:
        runAsUser: 0
"""
        }
    }

    options {
        timeout(time: 10, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    parameters {
        choice(name: 'ACTION', choices: ['CREATE', 'DELETE'], description: 'Operazione')
        string(name: 'TOPIC_NAME', defaultValue: '', description: 'Nome del topic')
        string(name: 'PARTITIONS', defaultValue: '3', description: 'Numero partizioni')
        string(name: 'REPLICAS', defaultValue: '3', description: 'Numero repliche')
        string(name: 'RETENTION_HOURS', defaultValue: '168', description: 'Retention (ore)')
        string(name: 'CONFIRM_DELETE', defaultValue: '', description: 'Solo per DELETE: riscrivi nome topic')
    }

    environment {
        KAFKA_NAMESPACE = 'kafka-lab'
        KAFKA_CLUSTER = 'kafka-cluster'
    }

    stages {
        stage('Validazione') {
            steps {
                script {
                    if (!params.TOPIC_NAME?.trim()) error "TOPIC_NAME obbligatorio!"
                    if (params.ACTION == 'DELETE' && params.TOPIC_NAME != params.CONFIRM_DELETE) {
                        error "Conferma eliminazione fallita!"
                    }
                }
            }
        }

        stage('Esecuzione') {
            steps {
                container('kubectl') {
                    script {
                        if (params.ACTION == 'CREATE') {
                            def retentionMs = params.RETENTION_HOURS.toInteger() * 3600000
                            sh """
cat <<EOF | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: ${params.TOPIC_NAME}
  namespace: ${env.KAFKA_NAMESPACE}
  labels:
    strimzi.io/cluster: ${env.KAFKA_CLUSTER}
    managed-by: jenkins
spec:
  partitions: ${params.PARTITIONS}
  replicas: ${params.REPLICAS}
  config:
    retention.ms: ${retentionMs}
    segment.bytes: 1073741824
EOF
"""
                            sleep 5
                            sh "kubectl wait kafkatopic/${params.TOPIC_NAME} -n ${env.KAFKA_NAMESPACE} --for=condition=Ready --timeout=60s"
                            echo "Topic '${params.TOPIC_NAME}' creato correttamente!"
                        } else {
                            sh "kubectl delete kafkatopic ${params.TOPIC_NAME} -n ${env.KAFKA_NAMESPACE} --ignore-not-found"
                            echo "Topic eliminato!"
                        }
                    }
                }
            }
        }
    }
}
