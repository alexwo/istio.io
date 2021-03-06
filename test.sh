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
#version 1.01
RUN_DIR=/var/vcap/sys/run/bpm_fix
PIDFILE=$RUN_DIR/bpm_fix.pid
monit=/var/vcap/bosh/bin/monit
sudo=/usr/bin/sudo
recreate=false
case $1 in

  start)
    mkdir -p $RUN_DIR
    echo $$ > $PIDFILE
    echo "sleeping for 3 mintues to allow vm regular startup"
    sleep 3m
    while true; do
                processes=$(monit summary | egrep "Execution failed|not monitored" | grep "Process" | awk '{print $2}'| tr -d \')
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

                         state_directory="/var/vcap/data/bpm/runc/bpm-${process}*"
                         state_file="${state_directory}/state.json"
                         echo "checking whether state file $state_file exists"
                         if [[ -d "$state_directory" &&  -s "$state_file" ]]
                         then
                           echo "state file is ok, $state_file"
                         else
                            recreate=true
                         fi
                        done
          sleep 1m
             if [ "$recreate" = true ]; then

               echo "We will clean and re-create the bpm state and allow monit to take care of everything else"
                rm -rf /var/vcap/data/bpm/runc
               /var/vcap/jobs/bpm/bin/bpm list | awk '{ print $1 }' |tail -n +2 | xargs -L1  bpm start
               /var/vcap/jobs/bpm/bin/bpm list | awk '{ print $1 }' |tail -n +2 | xargs -L1  bpm stop
               /var/vcap/bosh/bin/monit restart all
             fi
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
    clean_bpm_fix
fi
