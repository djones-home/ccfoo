% jenkins.rb

## Install Jenkins service.

Install jenkins from an rpm - the self-contained package, confugure init scripts, to accomidate the CIE.

- Jenkins CLI
- Security Authentication and Authorization
- Set a minimal list of plugins in the cieSetup.groovy template, those given in __node[:jenkins_plugins]__.
- YTBD: Do we support pinned plugin versions here or do that elsewhere (AMIs, backups, restore script w/cli) ?.
The latest version of these will be installed from the updatecenter.
For specific versions of jenkins plugings concider keeping an S3 or local store to copy from
Additional jenkins plugings can be added with the ssh-cli, following this recipe:

> sudo - ssh -p 8022 maintuser@localhost install-plugin  docker-workflow 
> ### or 
> ssh -p 8022 $CN@localhost install-plugin  docker-workflow 

- YTBD move jenkins_admins to a more appropriate place, perhaps ciData/global.json, (now default to Dan and Kevin).
- YTBD, document CIE convensions for setting node.override: in cb, role, or env.
- Share use of a few  community jenkins cookbook attributes, i.e.  __jenkins_args__.
-YTBD: Move the attribute setup to install oracle java 
### Recipe workflow:
- Gotta have rpm-build, subversion, git, and wget packages.
- Install a pgdg repo, as a postgresql package is needed for the sonar plugin data
- YTBD move this pgdg repo setup to a db recipe, and just include_recipe.
- Insure there is a yum.repo.d/jenkins.repo
- Install /etc/system/jenkins configuration from a template
- Install Jenkins init hook scripts into JENKINS_HOME/init.groovy.d
  - 01_ciePlugins.groovy will install missing plugins
  -  02_cieSecurity.groovy: sets the security realm, authz strategy, SSHD port, and disable unsecure protocols.
  - 03_setup-users-groovy: may reset authz strategy, add matrix users/groups/administrators, add the admin ssh-cli authorized keys
- Restart jenkins only if notified of init.groovy updates.
- Create a Jenkins job named AWS_{Project} that runs the ciStack UI.
This job allows users to show, stop, start, launch, and terminate VM instances in AWS.
The AWS_{project} jobs require the Active Choices plugin, a.k.a uno-choice. and a script work space on the master (sws folder).
- Create /var/lib/jenkins/sws folder - for the aws_UI.groovy, used by AWS_{project} jobs.
## Also see:
- The [AWS UI job](https://incubator2.nps.edu/ciedocs/tools/groovy) at this time will populate the sws folder, requires svn credentials, therefore expect Jenkins to do this for it-self.
- [Restore Jenkins](https://incubator2.nps.edu/ciedocs/backups) jobs (if given a backup/restore location) YTBD
- [Add build slaves](https://incubator2.nps.edu/ciedocs/resources/jenkins/nodes), given this instance has credentials for this. YTBD
- [Credentials in the CIE](https://incubator2.nps.edu/ciedocs/credentials)

