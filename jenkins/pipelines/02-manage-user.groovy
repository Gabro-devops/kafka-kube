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
        string(name: 'USERNAME', defaultValue: '', description: 'Nome utente')
        choice(name: 'ROLE', choices: ['producer', 'consumer', 'producer-consumer', 'admin'], description: 'Ruolo')
        string(name: 'TOPIC_PATTERN', defaultValue: '*', description: 'Pattern Topic (es. ordini-*, o * per tutti)')
        string(name: 'CONSUMER_GROUP', defaultValue: '*', description: 'Consumer Group')
        string(name: 'CONFIRM_DELETE', defaultValue: '', description: 'Solo per DELETE: riscrivi username')
    }

    environment {
        KAFKA_NAMESPACE = 'kafka-lab'
        KAFKA_CLUSTER = 'kafka-cluster'
    }

    stages {
        stage('Validazione') {
            steps {
                script {
                    if (!params.USERNAME?.trim()) error "USERNAME obbligatorio!"
                }
            }
        }

        stage('Esecuzione') {
            steps {
                container('kubectl') {
                    script {
                        if (params.ACTION == 'CREATE') {
                            def finalName = params.TOPIC_PATTERN
                            def finalPattern = "literal"

                            if (params.TOPIC_PATTERN == "*") {
                                finalName = "*"
                                finalPattern = "literal"
                            } else if (params.TOPIC_PATTERN.endsWith("*")) {
                                finalName = params.TOPIC_PATTERN.replace("*", "")
                                finalPattern = "prefix"
                            }

                            def acls = ""
                            if (params.ROLE in ['producer', 'producer-consumer']) {
                                acls += """
  - resource:
      type: topic
      name: "${finalName}"
      patternType: ${finalPattern}
    operations: ["Write", "Describe", "Create"]"""
                            }
                            if (params.ROLE in ['consumer', 'producer-consumer']) {
                                acls += """
  - resource:
      type: topic
      name: "${finalName}"
      patternType: ${finalPattern}
    operations: ["Read", "Describe"]
  - resource:
      type: group
      name: "${params.CONSUMER_GROUP}"
      patternType: literal
    operations: ["Read"]"""
                            }
                            if (params.ROLE == 'admin') {
                                acls += """
  - resource:
      type: topic
      name: "*"
      patternType: literal
    operations: ["All"]
  - resource:
      type: group
      name: "*"
      patternType: literal
    operations: ["All"]
  - resource:
      type: cluster
    operations: ["All"]"""
                            }

                            sh """
cat <<EOF | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: ${params.USERNAME}
  namespace: ${env.KAFKA_NAMESPACE}
  labels:
    strimzi.io/cluster: ${env.KAFKA_CLUSTER}
    managed-by: jenkins
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
${acls}
EOF
"""
                            sleep 5
                            sh "kubectl wait kafkauser/${params.USERNAME} -n ${env.KAFKA_NAMESPACE} --for=condition=Ready --timeout=120s"
                            echo "Utente '${params.USERNAME}' pronto!"
                        } else {
                            sh "kubectl delete kafkauser ${params.USERNAME} -n ${env.KAFKA_NAMESPACE} --ignore-not-found"
                            echo "Utente eliminato!"
                        }
                    }
                }
            }
        }
    }
}
