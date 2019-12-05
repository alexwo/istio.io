#!/usr/bin/env bash

function add_bpm(){

    if test -d /var/vcap/sys/run/bpm_fix; then
     rm -rf /var/vcap/sys/run/bpm_fix
    fi
    
    mkdir -p /var/vcap/jobs/bpm_fix/bin
    monit=/var/vcap/bosh/bin/monit
    sudo=/usr/bin/sudo
    
cat > /var/vcap/jobs/bpm_fix/bin/bpm_fix <<'EOF'
#!/bin/bash
set -e
#version 1.02
mkdir -p /var/vcap/sys/log/bpm_monitor
exec 3>&1 1>>/var/vcap/sys/log/bpm_monitor/bpm_monitor 2>&1
RUN_DIR=/var/vcap/sys/run/bpm_fix
PIDFILE=$RUN_DIR/bpm_fix.pid
monit=/var/vcap/bosh/bin/monit
sudo=/usr/bin/sudo

case $1 in

  start)
    mkdir -p $RUN_DIR
    echo $$ > $PIDFILE
        while true; do
                processes=$(/var/vcap/bosh/bin/monit summary | egrep "Execution failed|not monitored" | grep "Process" | awk '{print $2}'| tr -d \')
                   if [ -z "$processes" ]; then
                           echo "no failed processes"
                           continue
                   fi
                   echo "failed processes: $processes"
                   for process in $processes
                   do
                       if [ $process == "bpm_fix" ]; then
                           echo "it's me"
                           continue
                      fi

                         state_directory="/var/vcap/data/bpm/runc/bpm-${process}"
                         state_file="${state_directory}/state.json"
                         echo "checking whether state file $state_file exists"
                         if [[ -d "$state_directory" &&  -s "$state_file" ]]
                         then
                           echo "state file is ok, $state_file"
                         else
                           echo "state file is corrupted, removing state directory: $state_directory"
                           sudo rm -rf $state_directory
                           /var/vcap/jobs/bpm/bin/bpm start $process
                           monit restart $process
                         fi
                        done
          sleep 1m
         done
 ;;

  stop)
    if [ -f $PIDFILE ]; then
      kill -9 `cat $PIDFILE` || true
      rm -f $PIDFILE
    fi
    ;;

  *)
    echo "Usage: $0 {start|stop}"

    ;;
esac
EOF

cat > /var/vcap/monit/job/8888_bpm-fix-job.monitrc <<EOF
check process bpm_fix
  with pidfile /var/vcap/sys/run/bpm_fix/bpm_fix.pid
  start program "/usr/bin/sudo /var/vcap/jobs/bpm_fix/bin/bpm_fix start"
  stop program "/var/vcap/jobs/bpm_fix/bin/bpm_fix stop"
  group vcap
EOF

    chmod 755 /var/vcap/jobs/bpm_fix/bin/bpm_fix
    monit reload && sudo monit restart bpm_fix

}

function clean_bpm_fix(){
    rm -rf /var/vcap/jobs/bpm_fix/bin
    rm /var/vcap/monit/job/8888_bpm-fix-job.monitrc
    monit reload && sudo monit restart bpm_fix
}

if test -f "/var/vcap/jobs/bpm/bin/bpm"; then
    add_bpm
else
    echo "nothing to do"
fi
