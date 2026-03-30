FROM jenkins/jenkins:lts-jdk17

# Disabilita setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG="/var/jenkins_config/casc.yaml"

# Installa plugin (build time = Mac ha internet)
RUN jenkins-plugin-cli --plugins \
  kubernetes:latest \
  configuration-as-code:latest \
  job-dsl:latest \
  git:latest \
  git-client:latest \
  workflow-aggregator:latest \
  workflow-job:latest \
  workflow-scm-step:latest \
  workflow-step-api:latest \
  credentials:latest \
  plain-credentials:latest \
  structs:latest \
  scm-api:latest \
  pipeline-model-definition:latest \
  pipeline-stage-step:latest \
  pipeline-input-step:latest \
  pipeline-graph-analysis:latest \
  pipeline-build-step:latest \
  pipeline-milestone-step:latest \
  branch-api:latest \
  cloudbees-folder:latest \
  script-security:latest \
  matrix-auth:latest \
  mailer:latest
