# Jenkins CI with the IAR Build Tools
The [IAR Build Tools](https://iar.com/cx) include command-line utilities for building projects created with IAR Embedded Workbench in continuous integration or headless environments, such as [Jenkins][url-jenkins]. [Gitea][url-gitea] is a lightweight Git server ideal for simple container deployments. Jenkins offers plugins for many popular Git providers, including GitHub, GitLab, and Bitbucket. For details, see [Managing Jenkins/Managing Plugins][url-jenkins-docs-plugins].

This tutorial provides a quick way to bootstrap IAR Build Tools, Gitea and Jenkins —each in its own container— for building and analyzing embedded projects on-premises. From this foundation, you can apply customizations to suit your organization’s needs. In a picture:

![cx-jenkins-ci](https://github.com/user-attachments/assets/bd02dbad-0f35-4ef7-89ca-8b1d4cada87a)

## Disclaimer
The information in this repository is subject to change without notice and does not constitute a commitment by IAR. While it serves as a valuable reference for DevOps Engineers implementing Continuous Integration with IAR Tools, IAR assumes no responsibility for any errors, omissions, or specific implementations.

## Pre-requisites
__This tutorial works out of the box with the [public container images](https://github.com/orgs/iarsystems/packages) using the latest generation of the IAR Build Tools and its Cloud License Service (CX). For the earlier generation of the IAR Build Tools (BX), it is necessary to manually build locally their respective Docker container images using the guidelines provided in the [__bx-docker tutorial__][url-bx-docker].__

You will also need a web browser to access webpages. It is assumed that the web browser is installed on a Windows PC in which you have privileges to execute administrative tasks and that can reach the Linux server containing the Docker daemon with the IAR Build Tools.

Install the Docker Engine on one of its [supported x86_64/amd64	environments](https://docs.docker.com/engine/install#server):
```bash
# Update APT's database
sudo apt update
sudo apt install curl
curl -fsSL https://get.docker.com -o get-docker.sh
sh ./get-docker.sh
# Add the current $USER to the docker group
sudo usermod -aG docker $USER
# Apply changes made to /etc/group (same as logging out and logging in again)
sudo -iu $USER
```

<img alt="Docker" align="right" src="https://avatars.githubusercontent.com/u/5429470?s=96&v=4" /><br>

## Setting up a Docker Network
For simplifying this setup let's create a [docker network][url-docker-docs-net] named __jenkins__ in the Linux server's shell:
```
docker network create jenkins
```
From here onwards, we spawn all the tutorial's containers with `--network-alias <name> --network jenkins` so that they become visible and reacheable from each other.

As administrator, edit the __%WINDIR%/system32/drivers/etc/hosts__ file in the Windows PC. Add the following line, replacing `192.168.1.2` by the actual Linux server's IP address. With that, the Windows PC can reach the containers' exposed service ports by their respective network-alias names:
```
192.168.1.2 gitea jenkins
```

<img alt="Gitea" align="right" src="https://avatars.githubusercontent.com/u/12724356?s=84&v=4"/><br>

## Setting up Gitea
Now it is time to setup the __gitea__ container. On the Linux server's shell, execute:
```
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

On the web browser, navigate to http://gitea:3000 to perform the initial Gitea setup:
- Unfold __Administrator Account Settings__ and enter with:
   - __Administrator Username__: `jenkins`
   - __Email Address__: `jenkins@localhost`
   - __Password__: `jenkins`
   - __Confirm Password__: `jenkins`
- Click __`Install Gitea`__.

### Setting up a webhook
A webhook is a mechanism which can be used to trigger associated build jobs in Jenkins whenever, for example, code is pushed into a Git repository.

Update `/data/gitea/conf/app.ini` for accepting webhooks from the __jenkins__ container:
```
docker exec gitea bash -c "echo -e '\n[webhook]\nALLOWED_HOST_LIST=jenkins\nDISABLE_WEBHOOKS=false' >> /data/gitea/conf/app.ini"
docker restart gitea
```

>[!NOTE]
>These configuration options will be written into `/data/gitea/conf/app.ini` stored inside the `gitea-data` volume.

### Migrating an existing example repository
For this example, we will use a repository containing a Jenkinsfile, a script to perform a pipeline on Jenkins. On the top-right corner of the page:
- Go to __`+`__ → __New Migration__ → __GitHub__ (http://gitea:3000/repo/migrate?service_type=2). 
- __Migrate / Clone from URL__: [`https://github.com/iarsystems/ewp-workspaces-ci`](https://github.com/iarsystems/ewp-workspaces-ci).
- Edit the [Jenkinsfile-cx](http://gitea:3000/jenkins/ewp-workspaces-ci/_edit/master/Jenkinsfile-cx) or edit the [Jenkinsfile-bx](http://gitea:3000/jenkins/ewp-workspaces-ci/_edit/master/Jenkinsfile-bx) updating any settings (such as __image__) to match the image you intend to use.

<img alt="Jenkins" align="right" src="https://avatars.githubusercontent.com/u/107424?s=72&v=4"/><br>

## Setting up Jenkins
It is finally time to set up the __jenkins__ container.

The standard Jenkins setup has a number of steps that can be automated with the [configuration-as-code][url-plugin-casc] plugin. For this, let's use a custom [Dockerfile](Dockerfile) that will:
* use the __jenkins/jenkins:lts-slim__, a stable version offering __LTS__ (Long-Term Support), as base image.
* use the __configuration-as-code__ plugin, so that we script the initial [Jenkins configuration](jcasc.yaml).
* use the `jenkins-plugin-cli` command line utility to install a collection of [plugins](plugins.txt) versions that are known to be working.
* and more... (check [Dockerfile](Dockerfile) for details).

In the Linux server's shell, clone this repository to the user's home directory (`~`):
```
git clone https://github.com/iarsystems/cx-jenkins-ci.git ~/cx-jenkins-ci
```

Check and update your [Jenkins configuration](jcasc.yaml) if necessary. Then build the container image, tagging it as __jenkins:jcasc__:
```
docker build --tag jenkins:jcasc --build-arg DOCKER_GROUP=$(getent group docker | cut -d: -f3) ~/cx-jenkins-ci
```
>[!TIP]
>Given its fast-paced and complex ecosystem, Jenkins' plugins sometimes might break compatibility regarding its interdependencies. If you try this tutorial at a point in time where a certain plugin prevents the Docker image from being created, it is possible to pin the broken plugin's version by replacing `<broken-plugin>:latest` for a plugin's earlier version in the `plugin.txt` file.

Now run the __jenkins__ container:
```
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
Log in into your Jenkins Dashboard (http://jenkins:8080, default user/pass is `admin`/`admin`) and then:
- Click __New Item__.
- __Enter an item name__ (e.g. `Organization`).
- Select __Organization Folder__ and click __` OK `__.

In the __Configuration__ page:
- Select __Projects__ → "Repository Sources" → __` Add `__ → __Gitea Organization__.
- Select the "Jenkins Token" from the __Credentials__ drop-down list.
- Fill the __Owner__ field with the username you created for your Gitea server (e.g., `jenkins`).
- In "Project Recognizers" → change the __Pipeline Jenkinsfile__ to `Jenkinsfile-cx` (or `Jenkinsfile-bx`).
- Finally __` Save `__.


## What happens next?
After that, Jenkins will use its multi-branch scan plugin to retrieve all the project repositories available on the Gitea Server.

![image](https://github.com/user-attachments/assets/700a8822-b433-4089-83fa-1b5d58b5d5fa)

When Jenkins finds the specified Jenkinsfile (e.g., [Jenkinsfile-cx](https://github.com/IARSystems/ewp-workspaces-ci/blob/master/Jenkinsfile-cx)) that uses a [declarative pipeline](https://www.jenkins.io/doc/book/pipeline/syntax/), Jenkins will then automatically execute the defined pipeline.

When the pipeline requests a Docker agent for the __docker-cloud__ plugin, it will automatically forward the request to the __jenkins__ container so a new container based on the selected image is dynamically spawned during the workflow execution.
```groovy
pipeline {
  agent {
    docker {
      image 'ghcr.io/iarsystems/<target_architecture>:<version>-<variant>'
      args '...'
  }
/* ... */
  stage('Build') {
    steps {
      sh 'iarbuild <project>.ewp -build <build_configuration> [-parallel <N>] [-log all]'
    }
  }
  stage('Static Code Analysis') {
    steps {
      sh 'iarbuild <project>.ewp -cstat_analyze <build_configuration> [-parallel <N>] [-log all]'
    }
  }
/* ... */
```

![image](https://github.com/user-attachments/assets/358b12e1-2774-43bf-9be0-0c229329ccf8)

Jenkins will get a push notification from Gitea (via webhooks) whenever a monitored event is generated on the __owner__'s repositories.

Now you can start developing using the [IAR Embedded Workbench][url-iar-ew] and committing the project's code to the Gitea Server so you get automated builds and reports.


### Highlights
* The [__warnings-ng__][url-plugin-warnings-ng] plugin gives instantaneous feedback for every build on compiler-generated warnings as well violation warnings on coding standards provided by [IAR C-STAT](https://www.iar.com/cstat), our static code analysis tool for C/C++:

![warnings-ng-cstat](https://github.com/user-attachments/assets/134daae4-99d6-46cb-b492-4eb13685f3d4)

* The [__gitea-checks__][url-plugin-gitea-checks] plugin has integrations with the [__warnings-ng__][url-plugin-warnings-ng] plugin. On the Gitea server, it can help you to spot failing checks on pull requests, preventing potentially defective code from being inadvertently merged into a project's production branch:

![gitea-checks-plugin](https://github.com/user-attachments/assets/46d1dbb7-6969-403e-b9cd-f5dabdb2ef13)


## Summary
This tutorial provides a quickly deployable and reproducible setup where everything runs on containers. This is just one of many ways to set up automated workflows using the IAR Build Tools. By using [Jenkins Configuration as Code][url-jenkins-jcasc] to set up a new Jenkins controller, you can simplify the initial configuration with YAML syntax. This configuration can be validated and reproduced across other Jenkins controllers.
   
You can learn from the provided scripts, [Dockerfile](Dockerfile) and official [Jenkins Documentation][url-jenkins-docs]. Together, these resources form a cornerstone for your organization, allowing you to use them as-is or customize them to ensure the environment runs to meet your specific needs.

[__` Follow us `__](https://github.com/iarsystems) on GitHub to get updates about tutorials like this and more.


## Issues
For technical support contact [IAR Customer Support][url-iar-customer-support].

For questions or suggestions related to this tutorial: try the [wiki][url-repo-wiki] or check [earlier issues][url-repo-issue-old]. If those don't help, create a [new issue][url-repo-issue-new] with detailed information.


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
