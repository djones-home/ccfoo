% cacRestart shell function

# Code for cacRestart shell function

The following bash code segment is meant be placed (merged) into the  __$HOME/.bashrc__  file of a Linux user, as a
convience for managing SSH-agent authentication operations using CACs. 
Normally the $HOME/.profile will conditionally sources .bashrc, only if the login shell supports Bash features.


````bash
pk11libs="/usr/lib/pkcs11/libcoolkeypk11.so /usr/lib64/pkcs11/libcoolkeypk11.so /usr/local/opt/opensc/lib/opensc-pkcs11.so"
export PKCS11; for PKCS11 in $pk11libs;  do [ -r ${PKCS11} ] && break; done
# 

###
# Start (or restart) using CAC key operations via SSH Agent.
# 
cacRestart() { 
# - Caches an rc to help setup ssh-agent environment variables, i.e. SSH_AGENT_PID, SSH
    local file=$HOME/.cache/cacRestart/rc.$(hostname) 
    local dir=${file%/*} now=$(date +%s) id=X$SSH_AGENT_PID
    [ -d $dir ]  || { mkdir -p  $dir && chmod 700 $dir; }
    [ -e $file ]  || ssh-agent -s > $file 
# - Uses the cache-rc to find the last OpenSSH-agent
    [ X$SSH_AGENT_PID != X$(. $file>/dev/null; echo $SSH_AGENT_PID) ] && . $file; 
# - start a new agent if the last agent proc is missing
    [ -e /proc/$SSH_AGENT_PID -a -n "$SSH_AGENT_PID" ] || { ssh-agent -s > $file && . $file; }
    [ $(stat -c %Y $file) -lt $now ] && {
# - or switch to the last-started existing agent, just return -not touching the agent or reloading keys
        [ $id != X$SSH_AGENT_PID ] && return 1
# - if not-switched, purge (if any) PKCS11 provided keys from the existing agent
        ssh-add -e $PKCS11
    }
# - connecting (new or pruged) ssh-agent to the CAC smartcard a (PIN will be required)
    ssh-add -s $PKCS11
}
````

# Also See:

- Source from [aws.func]
- Use partterns from [Tools document from aws.func](aws.func.html)

[aws.func]: https://svn.nps.edu/repos/metocgis/infrastructure/trunk/tools/aws.func

