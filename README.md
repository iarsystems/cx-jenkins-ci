# Jenkins CI with IAR Build Tools
This repository demonstrates a continuous integration (CI) workflow using IAR Build Tools, Jenkins and Gitea, all running in Docker containers. The [IAR Build Tools](https://iar.com/cx) provide command-line utilities for building and analyzing projects created with IAR Embedded Workbench in headless environments like Jenkins. [Gitea][url-gitea] is a lightweight Git server suitable for containerized deployments, while [Jenkins][url-jenkins] integrates seamlessly with Git providers via plugins.

This tutorial guides you through setting up these tools in separate containers for on-premises building and analysis of embedded projects. You can customize this setup to fit your organization's requirements. Here is a visual overview:

![cx-jenkins-ci](https://github.com/user-attachments/assets/bd02dbad-0f35-4ef7-89ca-8b1d4cada87a)

Why This Setup? Amongst the reasons for adopting it, it is worth mentioning:
- __Zero manual configuration__: Jenkins is pre-configured via Configuration as Code ([JCasC][url-jenkins-jcasc])
- __Fully containerized__: No host pollution, easy to versionate and scale
- __[Webhooks][url-gitea-docs-webhooks]-triggered builds__: Push to Gitea → instant Jenkins pipeline execution
- __Dynamic Build Agents__: Docker agents spawn on-demand using [official IAR tool images](https://github.com/orgs/iarsystems/packages)
- __Rich feedback__: integrated C-STAT analysis, [warnings][url-plugin-warnings-ng] and [pull request checks][url-plugin-gitea-checks]

## Disclaimer
The information in this repository is provided as-is and may change without notice. It does not represent a commitment by IAR Systems. While useful as a reference for DevOps engineers implementing CI with IAR tools, IAR assumes no responsibility for errors, omissions, or specific implementations.

## Prerequisites
This tutorial uses public container images with the latest IAR Build Tools (CX generation) and its Cloud License Service. For the earlier BX generation, build custom Docker images following the [bx-docker guide][url-bx-docker].

You'll need:
- A web browser on a Windows PC with administrative privileges.
- The PC must access the Linux server running Docker.
- Docker Engine installed on a supported x86_64/amd64 Linux environment (e.g., Ubuntu).

Install Docker if not already present:
```bash
# Update package index and install cURL
sudo apt update && sudo apt install -y curl

# Download and run the official Docker install script
curl -fsSL https://get.docker.com -o get-docker.sh
sh ./get-docker.sh

# Add current $USER to docker group
sudo usermod -aG docker $USER

# Re-login to apply group changes
sudo -ui $USER
```
Wait for 20 seconds if you are installing the Docker Engine in WSL. For further details, refer to the [Docker installation guide](https://docs.docker.com/engine/install/).

<img alt="Docker" align="right" src="https://avatars.githubusercontent.com/u/5429470?s=96&v=4" /><br>

## Setting Up a Docker Network
Create a Docker network named `jenkins` for container communication:
```bash
docker network create jenkins
```
All containers in this tutorial use `--network jenkins` and `--network-alias <name>` for visibility and reachability.

On your Windows PC, edit `%WINDIR%\system32\drivers\etc\hosts` as administrator. Add this line, replacing `192.168.1.2` with your Linux server's IP:

```
192.168.1.2 gitea jenkins
```

This allows accessing services via aliases (e.g., `http://gitea:3000`).

<img alt="Gitea" align="right" src="https://avatars.githubusercontent.com/u/12724356?s=84&v=4"/><br>

## Setting Up Gitea
Run the Gitea container:

```bash
docker run \
  --name gitea \
  --network jenkins \
  --network-alias gitea \
  --detach \
  --restart=unless-stopped \
  --volume gitea-data:/data \
  --volume /etc/timezone:/etc/timezone:ro \
  --volume /etc/localtime:/etc/localtime:ro \
  --publish 3000:3000 \
  --publish 2222:2222 \
  gitea/gitea:1.24
```

Access http://gitea:3000 in your browser for initial setup:
- Under "Administrator Account Settings":
  - Administrator Username: `jenkins`
  - Email Address: `jenkins@localhost`
  - Password: `jenkins`
  - Confirm Password: `jenkins`
- Click "Install Gitea".

### Configuring a Webhook
Webhooks trigger Jenkins builds on events like code pushes. Update Gitea's configuration to accept webhooks from Jenkins:

```bash
docker exec gitea bash -c "echo -e '\n[webhook]\nALLOWED_HOST_LIST=jenkins\nDISABLE_WEBHOOKS=false' >> /data/gitea/conf/app.ini"
docker restart gitea
```

These changes persist in the `gitea-data` volume.

### Migrating an Existing Example Repository
For this tutorial, use a sample repository with a `Jenkinsfile` for pipeline execution. On Gitea's dashboard (top-right corner):
- Click `+` → __New Migration__.
- Select __Git__ as the migration type.
- Enter a repository URL 
   - (e.g., a public example repo with a Jenkinsfile. You can use <https://github.com/iarsystems/ewp-workspaces-ci> for reference).
- Fill in details and migrate.

Alternatively, create a new repository and push a sample project with a appropriate `Jenkinsfile-cx` or `Jenkinsfile-bx`.


<img alt="Jenkins" align="right" src="https://avatars.githubusercontent.com/u/107424?s=72&v=4"/><br>

## Setting Up Jenkins
This setup uses a custom Dockerfile for automated configuration:
- Base: `jenkins/jenkins:lts-slim` (Long-Term Support).
- Plugins: Installed via `jenkins-plugin-cli` for compatibility.
- Configuration: Handled as code (JCasC) for reproducibility.

Clone this repository on the Linux server:

```bash
git clone https://github.com/iarsystems/cx-jenkins-ci.git ~/cx-jenkins-ci
```

Review and edit configurations in `~/cx-jenkins-ci` if needed. Build the image:
```bash
docker build \
  --tag jenkins:jcasc \
  --build-arg DOCKER_GROUP=$(getent group docker | cut -d: -f3) \
  ~/cx-jenkins-ci
```
>[!TIP]
>If plugin compatibility issues arise, pin versions in `plugins.txt` (e.g., `<plugin>:specific-version`).

Set `IAR_LMS_BEARER_TOKEN` in your shell or `.env` and the Jenkins container:

```bash
docker run --name jenkins \
  --network jenkins \
  --network-alias jenkins \
  --detach \
  --restart unless-stopped \
  --privileged \
  --publish 8080:8080 \
  --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --env IAR_LMS_BEARER_TOKEN=${IAR_LMS_BEARER_TOKEN} \
  jenkins:jcasc
```

### Creating an Organization Folder
Access Jenkins at <http://jenkins:8080> (default credentials: `admin`/`admin`).
- Click __New Item__.
- Name it (e.g., `Organization`).
- Select __Organization Folder__ → `OK`.

In configuration:
- Projects → Repository Sources → Add → Gitea Organization.
- Credentials: Select "Jenkins Token".
- Owner: `jenkins` (or your Gitea username).
- Project Recognizers: Change to `Jenkinsfile-cx` (or `Jenkinsfile-bx`).
- __`Save`__.


## What Happens Next?
Jenkins scans Gitea repositories using the multi-branch plugin. When it finds a matching `Jenkinsfile`, it executes the pipeline.

The pipeline uses a Docker agent to spawn a container (e.g., `ghcr.io/iarsystems/<architecture>:<version>-<variant>`) for builds:

```groovy
pipeline {
  agent {
    docker {
      image 'ghcr.io/iarsystems/arm:9.70.1-st'
      args '-e VAR=VALUE'
    }
  }

  stages {
    stage('Build') {
      steps {
        sh 'iarbuild MyProject.ewp -build Release -parallel 4 -log all'
      }
    }

    stage('Analyze') {
      steps {
        sh 'iarbuild MyProject.ewp -cstat_analyze Release -parallel 4 -log all'
      }
    }
  post {
    always {
      recordIssues enabledForFailure: true, tool: iarCStat()
    }
  }
  }
}
```

Gitea webhooks notify Jenkins of changes, triggering automated builds.

In simple terms, develop in IAR Embedded Workbench, commit to Gitea while blocking bad PRs with failing checks, and get clean builds with instant compiler and MISRA/CERT feedback, using safe, reproducible, and version-controlled configuration in Jenkins.

![gitea-checks-plugin](https://github.com/user-attachments/assets/46d1dbb7-6969-403e-b9cd-f5dabdb2ef13)

![jenkins-pipeline](https://github.com/user-attachments/assets/358b12e1-2774-43bf-9be0-0c229329ccf8)

![warnings-ng-cstat](https://github.com/user-attachments/assets/134daae4-99d6-46cb-b492-4eb13685f3d4)


## Summary
This containerized setup is quick to deploy and reproducible. It leverages Jenkins Configuration as Code (JCasC) for YAML-based setup, ideal for validation and scaling.

Customize using the provided scripts, Dockerfile, and [Jenkins documentation](https://www.jenkins.io/doc/). [__` Follow us `__](https://github.com/iarsystems) on GitHub for updates.


## Issues
For technical support, contact [IAR Customer Support][url-iar-customer-support].
Questions or suggestions? Check the [Wiki][url-repo-wiki] or open an [issue][url-repo-issue-new].

_(c) 2020-2025 IAR Systems AB. This example is provided as-is for reference. Customize to fit your environment._ 


<!-- Links -->
[url-iar-customer-support]: https://iar.my.site.com/mypages/s/contactsupport

[url-iar-cx]:                 https://iar.com/cx
[url-iar-contact]:            https://iar.com/about/contact
[url-iar-cstat]:              https://iar.com/cstat
[url-iar-ew]:                 https://iar.com/products/overview
[url-iar-fs]:                 https://iar.com/products/requirements/functional-safety
[url-iar-mp]:                 https://iar.com/mypages
[url-iar-lms2]:               https://links.iar.com/lms2-server

[url-vi]:                     https://en.wikipedia.org/wiki/Vi
    
[url-bx-docker]:              https://github.com/iarsystems/bx-docker/tree/v2025.04
[url-ewp-workspaces-ci]:       https://github.com/iarsystems/ewp-workspaces-ci

[url-docker-registry]:        https://docs.docker.com/registry
[url-docker-docs-net]:        https://docs.docker.com/network
 
[url-gitea]:                  https://gitea.io
[url-gitea-docs-webhooks]:    https://docs.gitea.io/en-us/webhooks
 
[url-jenkins]:                https://www.jenkins.io
[url-jenkins-jcasc]:          https://www.jenkins.io/projects/jcasc
[url-jenkins-docs]:           https://www.jenkins.io/doc
[url-jenkins-docs-plugins]:   https://www.jenkins.io/doc/book/managing/plugins

[url-plugin-casc]:            https://plugins.jenkins.io/configuration-as-code
[url-plugin-docker-cloud]:    https://plugins.jenkins.io/docker-plugin
[url-plugin-docker-workflow]: https://plugins.jenkins.io/docker-workflow
[url-plugin-gitea]:           https://plugins.jenkins.io/gitea
[url-plugin-gitea-checks]:    https://plugins.jenkins.io/gitea-checks
[url-plugin-warnings-ng]:     https://plugins.jenkins.io/warnings-ng
 
[url-repo]:                   https://github.com/iarsystems/cx-jenkins-ci
[url-repo-wiki]:              https://github.com/iarsystems/cx-jenkins-ci/wiki
[url-repo-issue-new]:         https://github.com/iarsystems/cx-jenkins-ci/issues/new
[url-repo-issue-old]:         https://github.com/iarsystems/cx-jenkins-ci/issues?q=is%3Aissue+is%3Aopen%7Cclosed
