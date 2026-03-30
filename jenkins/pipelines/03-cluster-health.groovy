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
    - name: kafka-tools
      image: quay.io/strimzi/kafka:0.44.0-kafka-3.8.0
      command: ["/bin/sh", "-c", "cat"]
      tty: true
      securityContext:
        runAsUser: 0
"""
        }
    }

    parameters {
        choice(
            name: 'CHECK_LEVEL',
            choices: ['BASIC', 'FULL', 'TOPICS_DETAIL', 'CONSUMER_LAG'],
            description: 'Livello di dettaglio del check'
        )
        string(
            name: 'TOPIC_FILTER',
            defaultValue: '',
            description: 'Filtra per nome topic (solo per TOPICS_DETAIL, lascia vuoto per tutti)'
        )
    }

    environment {
        KAFKA_NAMESPACE = 'kafka-lab'
        KAFKA_CLUSTER = 'kafka-cluster'
        KAFKA_BOOTSTRAP = 'kafka-cluster-kafka-bootstrap:9092'
    }

    stages {

        stage('Status Cluster Kubernetes') {
            steps {
                container('kubectl') {
                    script {
                        echo ""
                        echo "KAFKA LAB - CLUSTER HEALTH CHECK"
                        echo ""
                        echo "POD STATUS:"
                        sh "kubectl get pods -n ${env.KAFKA_NAMESPACE} --no-headers | awk '{printf \"  %-50s %s\\n\", \$1, \$3}'"
                        echo ""
                        echo "KAFKA CLUSTER STATUS:"
                        sh "kubectl get kafka ${env.KAFKA_CLUSTER} -n ${env.KAFKA_NAMESPACE} -o jsonpath='{.status.conditions[0].type}: {.status.conditions[0].status}' && echo ''"
                        sh "kubectl get kafka ${env.KAFKA_CLUSTER} -n ${env.KAFKA_NAMESPACE} -o jsonpath='Kafka version: {.spec.kafka.version}' && echo ''"
                    }
                }
            }
        }

        stage('Topics Status') {
            steps {
                container('kubectl') {
                    script {
                        echo ""
                        echo "KAFKA TOPICS (K8s Resources):"
                        sh """
                            kubectl get kafkatopic -n ${env.KAFKA_NAMESPACE} --no-headers | \
                            awk '{printf "  %-40s partitions=%-5s replicas=%-5s ready=%s\\n", \$1, \$3, \$4, \$5}' | sort
                        """
                    }
                }
            }
        }

        stage('Users Status') {
            steps {
                container('kubectl') {
                    script {
                        echo ""
                        echo "KAFKA USERS:"
                        sh """
                            kubectl get kafkauser -n ${env.KAFKA_NAMESPACE} --no-headers | \
                            awk '{printf "  %-30s auth=%-20s ready=%s\\n", \$1, \$3, \$5}' | sort
                        """
                    }
                }
            }
        }

        stage('Riepilogo Salute') {
            steps {
                container('kubectl') {
                    script {
                        echo ""
                        echo "RIEPILOGO SALUTE CLUSTER"
                        echo ""

                        def issues = 0

                        def badPods = sh(
                            script: "kubectl get pods -n ${env.KAFKA_NAMESPACE} --no-headers | grep -v 'Running\\|Completed' | wc -l | tr -d ' '",
                            returnStdout: true
                        ).trim().toInteger()

                        if (badPods > 0) {
                            echo "${badPods} pod non in stato Running!"
                            issues++
                        } else {
                            echo "Tutti i pod Running"
                        }

                        def kafkaReady = sh(
                            script: "kubectl get kafka ${env.KAFKA_CLUSTER} -n ${env.KAFKA_NAMESPACE} -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo 'False'",
                            returnStdout: true
                        ).trim()

                        if (kafkaReady == 'True') {
                            echo "Kafka cluster Ready"
                        } else {
                            echo "Kafka cluster non Ready!"
                            issues++
                        }

                        echo ""
                        if (issues == 0) {
                            echo "CLUSTER SANO - Nessun problema rilevato"
                        } else {
                            echo "ATTENZIONE - ${issues} problema/i rilevato/i"
                            currentBuild.result = 'UNSTABLE'
                        }
                        echo ""
                    }
                }
            }
        }
    }

    post {
        success { echo "Health check completato con successo" }
        failure { echo "Health check fallito" }
    }
}
