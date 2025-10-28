FROM jenkins/jenkins:lts-slim

# If necessary, update it to your host's GID
ARG DOCKER_GROUP=999

USER root

# Installs the official Docker client
RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
    https://download.docker.com/linux/debian/gpg
RUN echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
  https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
RUN apt-get update && \
    apt-get install -y docker-ce-cli  && \
    groupadd -g $DOCKER_GROUP docker && \
    usermod -aG dialout,docker jenkins

# Performs JCasC
ENV  JAVA_OPTS=-Djenkins.install.runSetupWizard=false
ENV  CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs/jenkins.yaml
COPY jcasc.yaml ${CASC_JENKINS_CONFIG}

# Install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN  jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

# Defaults to the `jenkins` user
USER jenkins
