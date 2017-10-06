#!/bin/bash

SCHEDULE_NAME="Daily scan schedule"
TARGET_ADM_NAME="ADM servers"
TARGET_PROJ_NAME="PROJ servers"
TARGET_OTHER_NAME="OTHER servers"
STASK_ADM_NAME="Scheduled scan adm servers"
STASK_PROJ_NAME="Scheduled scan proj servers"
STASK_OTHER_NAME="Scheduled scan other servers"
TASK_ADM_NAME="Scan adm servers"
TASK_PROJ_NAME="Scan proj servers"
TASK_OTHER_NAME="Scan other servers"
ALERT_ADMIN_NAME="Mail admin"
MAILTO="mail@nodomain.com"
PORT_LIST_NAME="All TCP and Nmap 5.51 top 1000 UDP"
CONFIG_NAME="Full and fast"
CREDENTIAL_ACCOUNT_NAME="tech_openvas"

RECIPIENT="mail@nodomain.com"
SENDER="mail@nodomain.com"

function echoerr { echo "$@" >&2; }

function fatalerror()
{
  echoerr $@
  exit 1
}


### $1 : TASK_NAME
### $2 : ALERT_ID
### $3 : TARGET_ADM_ID
### $4 : CONFIG_ID
### $5 : SCHEDULE_ID
function create_task()
{
  TASK_NAME=$1
  ALERT_ID=$2
  TARGET_ID=$3
  CONFIG_ID=$4
  SCHEDULE_ID=$5

  TASK_EXISTS=$(omp -i -X "<GET_TASKS/>" | \
    xmlstarlet sel -t -v "/get_tasks_response/task/name=\"$TASK_NAME\"")

  if [ $TASK_EXISTS = "true" ]; then
    echo "Task $TASK_NAME already exists"
  else
    echo "Creating task $TASK_NAME"
    RET=""
    if [ -z $SCHEDULE_ID ]; then
      RET=$(omp -i --xml "<create_task>
        <name>$TASK_NAME</name>
        <alert id=\"$ALERT_ID\"/>
        <target id=\"$TARGET_ID\"/>
        <config id=\"$CONFIG_ID\"/>
        <alterable>true</alterable>
        </create_task>")
    else
      RET=$(omp -i --xml "<create_task>
        <name>$TASK_NAME</name>
        <alert id=\"$ALERT_ID\"/>
        <target id=\"$TARGET_ID\"/>
        <config id=\"$CONFIG_ID\"/>
        <schedule id=\"$SCHEDULE_ID\"/>
        <alterable>true</alterable>
        </create_task>")
    fi
    echo $RET | xmlstarlet sel -t -v "/create_task_response/@status_text" -n
  fi
}


### $1: TARGET_NAME
### $2: HOSTS
### result stored in $TARGET_ID
function create_target() {
  TARGET_NAME=$1
  HOSTS=$2

  TARGET_ID=$(omp -i --xml "<GET_TARGETS/>" | xmlstarlet sel -t -v "/get_targets_response/target[name='$TARGET_NAME']/@id")
  if [ -z "$TARGET_ID" ]; then
    echo "Creating target: $TARGET_NAME..."
    TARGET_ID=$(omp -i --xml "<create_target><name>$TARGET_NAME</name> 
     <comment></comment> 
     <hosts>$HOSTS</hosts> 
     <port_list id=\"$PORT_LIST_TCP_ID\"/> 
     <ssh_credential id=\"$CREDENTIAL_ID\"/></create_target>" \
     | xmlstarlet sel -t -v "/create_target_response/@id") \
     && echo "TARGET_ID=$TARGET_ID" \
     || fatalerror "Error creating target $TARGET_NAME"

  else
    echo "Target $TARGET_NAME already exists. Checking if it is up to date..."
    TARGET_INSYS=$(omp -i --xml "<GET_TARGETS/>" \
      | xmlstarlet sel -t -v "/get_targets_response/target[name='$TARGET_NAME']/hosts")
    DIFF_HOSTS=$(diff -w -i -u <(echo "$HOSTS") <(echo "$TARGET_INSYS,"))
    ret=$?
    if [ $ret -ne 0 ]; then
      #http://www.greenbone.nl/learningcenter/remote_controlled.html 
      echo "Target $TARGET_NAME is not up to date."
      OLD_TARGET_ID=$TARGET_ID
      # MODIFY TARGET NAME
      echo "	Modifying target name of $TARGET_NAME"
      omp --xml "<modify_target target_id=\"$OLD_TARGET_ID\"><name>$TARGET_NAME old</name></modify_target>" \
        | xmlstarlet sel -t -v /modify_target_response/@status_text -n \
        || fatalerror "Error while modifying target $TARGET_NAME"

      # CLONE TARGET
      echo "	Cloning $TARGET_NAME"
      TARGET_ID=$(omp --xml "<create_target><copy>$OLD_TARGET_ID</copy> 
        <name>$TARGET_NAME</name></create_target>" \
          | xmlstarlet sel -t -v "/create_target_response/@id") \
          || fatalerror "Error while cloning target $TARGET_NAME"

      # MODIFY HOSTS LIST
      echo "	Modifying hosts list..."
      omp --xml "<modify_target target_id=\"$TARGET_ID\"><hosts>$HOSTS</hosts><exclude_hosts/></modify_target>" \
        | xmlstarlet sel -t -v "/modify_target_response/@status_text" -n \
        || fatalerror "Error while modifying hosts list in target $TARGET_NAME"


      # GET TASKS USING THIS TARGET
      echo "	Get tasks using target $TARGET_NAME"
      TASK_IDS=$(omp -i --xml "<GET_TASKS/>" | xmlstarlet sel -t -v \
        "/get_tasks_response/task/@id[../target/@id=\"$OLD_TARGET_ID\"]")
      for id in $TASK_IDS; do
        echo "		Updating task: $id"
        omp --xml "<modify_task task_id=\"$id\"> \
          <target id=\"$TARGET_ID\"/></modify_task>" \
          | xmlstarlet sel -t -v "/modify_task_response/@status_text" -n \
          || fatalerror "Error while updating task"
      done

      # DELETE OLD TARGET
      echo "Deleting old target..."
      omp --xml "<delete_target target_id=\"$OLD_TARGET_ID\"/>" | \
        xmlstarlet sel -t -v "/delete_target_response/@status_text" -n \
        || fatalerror "Error while deleting target $OLD_TARGET_ID"
    else
      echo "$TARGET_NAME hosts list is up to date"
    fi
  fi
}


### $1: SCHEDULE_NAME
### $2: PERIOD (default : 86400 = daily)
### return stored in $SCHEDULE_ID
function create_schedule()
{
  SCHEDULE_NAME=$1
  PERIOD=$2
  SCHEDULE_ID=$(omp -i --xml "<GET_SCHEDULES/>" | xmlstarlet sel -t -v "/get_schedules_response/schedule[name='$SCHEDULE_NAME']/@id")
  
  if [ -z "$SCHEDULE_ID" ]; then
    echo "Creating schedule: $SCHEDULE_NAME..."
    SCHEDULE_ID=$(omp -i --xml "<create_schedule > \
          <name>$SCHEDULE_NAME</name> \
          <comment></comment> \
	  	<first_time><minute>00</minute><hour>20</hour><day_of_month>7</day_of_month><month>7</month><year>2017</year></first_time> \
          <period>$PERIOD</period> \
          <duration>0</duration> \
        </create_schedule>"  \
        | xmlstarlet sel -t -v "/create_schedule_response/@id") \
        && echo "SCHEDULE_ID: " $SCHEDULE_ID \
        || fatalerror "Error while creating schedule $SCHEDULE_NAME"
  else
    echo "SCHEDULE_ID already exists"   
  fi
}

### $1: ALERT_ADMIN_NAME
### $2: RECIPIENT (mail@nodomain.com)
### $3: SENDER (mail@nodomain.com)
### return stored in $ALERT_ID
function create_alert()
{
  ALERT_ADMIN_NAME=$1
  RECIPIENT=$2
  SENDER=$3

  ALERT_ID=$(omp -i --xml "<GET_ALERTS/>" | xmlstarlet sel -t -v "/get_alerts_response/alert[name='$ALERT_ADMIN_NAME']/@id")

  if [ -z "$ALERT_ID" ]; then
    #echo "Creating alert: $ALERT_ADMIN_NAME..."
    ALERT_ID=$(omp --xml "<create_alert><name>$ALERT_ADMIN_NAME</name><condition>Always</condition> \
      <event>Task run status changed<data>Done<name>status</name></data></event> \
      <method>Email<data>1<name>notice</name></data><data>$SENDER<name>from_address</name></data><data>$MAILTO<name>to_address</name></data></method></create_alert>" \
      | xmlstarlet sel -t -v "/create_alert_response/@id") \
      && echo "ALERT_ID: " $ALERT_ID \
      || fatalerror "Error while creating alert"
  else
    echo "ALERT_ID already exists"   
  fi
}

############ REGEXP à changer pour récupérer vos liste de machine #############
############ Exemple de liste : 
## host1.novalocal
## host2.novalocal

ADM_HOSTS=$(cat /etc/hosts | grep datalab | tr -s " " | cut -d " " -f2 | grep adm | sort)
ADM_HOSTS=$(printf "%s, " $ADM_HOSTS)
PROJ_HOSTS=$(cat /etc/hosts | grep datalab | tr -s " " | cut -d " " -f2 | grep -v adm | sort)
PROJ_HOSTS=$(printf "%s," $PROJ_HOSTS)
OTHER_HOSTS=$(cat /etc/hosts | grep 172.30.2 | grep -v datalab | tr -s " " | cut -d " " -f2 | sort)
OTHER_HOSTS=$(printf "%s," $OTHER_HOSTS)

echo "================= ADM_HOSTS  ================"
echo $ADM_HOSTS
echo "================= PROJ_HOSTS ================"
echo $PROJ_HOSTS
echo "================= OTHER_HOSTS ==============="
echo $OTHER_HOSTS
echo "================ CONFIGURATION =============="

echo "SCHEDULE_NAME=$SCHEDULE_NAME"
echo "TARGET_ADM_NAME=$TARGET_ADM_NAME"
echo "TARGET_PROJ_NAME=$TARGET_PROJ_NAME"
echo "TARGET_OTHER_NAME=$TARGET_OTHER_NAME"
echo "STASK_ADM_NAME=$STASK_ADM_NAME"
echo "STASK_PROJ_NAME=$STASK_PROJ_NAME"
echo "STASK_OTHER_NAME=$STASK_OTHER_NAME"
echo "TASK_ADM_NAME=$TASK_ADM_NAME"
echo "TASK_PROJ_NAME=$TASK_PROJ_NAME"
echo "TASK_OTHER_NAME=$TASK_OTHER_NAME"
echo "ALERT_ADMIN_NAME=$ALERT_ADMIN_NAME"
echo "PORT_LIST_NAME=$PORT_LIST_NAME"
echo "CONFIG_NAME=$CONFIG_NAME"
echo "CREDENTIAL_ACCOUNT_NAME=$CREDENTIAL_ACCOUNT_NAME"

echo "RECIPIENT=$RECIPIENT"
echo "SENDER=$SENDER"
echo "============================================="

echo "Getting port list id..."
PORT_LIST_TCP_ID=$(omp -i --xml "<GET_PORT_LISTS/>" \
  | xmlstarlet sel -t -v "/get_port_lists_response/port_list[name='$PORT_LIST_NAME']/@id") \
  && echo "PORT_LIST_TCP_ID=$PORT_LIST_TCP_ID" \
  || fatalerror "Error getting port list"

CREDENTIAL_ID=$(omp -i -X "<GET_CREDENTIALS/>" \
  | xmlstarlet sel -t -v "/get_credentials_response/credential[name='$CREDENTIAL_ACCOUNT_NAME']/@id") \
  && echo "CREDENTIAL_ID=$CREDENTIAL_ID" \
  || fatalerror "Error getting credential id of $CREDENTIAL_ACCOUNT_NAME. Verify that account exists in openvas"

if [ -z "$CREDENTIAL_ID" ]; then
  fatalerror "Credential missing. before launch this script, create credential $CREDENTIAL_ACCOUNT_NAME";
fi

CONFIG_ID=$(omp -i --xml "<GET_CONFIGS/>" \
  | xmlstarlet sel -t -v "/get_configs_response/config[name='$CONFIG_NAME']/@id") \
  && echo "CONFIG_ID=$CONFIG_ID" \
  || fatalerror "Error getting config id of $CONFIG_NAME"

TARGET_ID=""
create_target "$TARGET_ADM_NAME" "$ADM_HOSTS"
TARGET_ADM_ID=$TARGET_ID

create_target "$TARGET_PROJ_NAME" "$PROJ_HOSTS"
TARGET_PROJ_ID=$TARGET_ID

create_target "$TARGET_OTHER_NAME" "$OTHER_HOSTS"
TARGET_OTHER_ID=$TARGET_ID

SCHEDULE_ID=""
create_schedule "$SCHEDULE_NAME" 86400
echo "SCHEDULE_ID=$SCHEDULE_ID"

ALERT_ID=""
create_alert "$ALERT_ADMIN_NAME" "$RECIPIENT" "$SENDER"
echo "ALERT_ID=$ALERT_ID"

echo "Params for creating tasks: "
echo "TARGET_ADM_ID="$TARGET_ADM_ID
echo "TARGET_PROJ_ID="$TARGET_PROJ_ID
echo "TARGET_OTHER_ID="$TARGET_OTHER_ID
echo "CONFIG_ID="$CONFIG_ID
echo "SCHEDULE_ID="$SCHEDULE_ID

create_task "$STASK_ADM_NAME" "$ALERT_ID" "$TARGET_ADM_ID" "$CONFIG_ID" "$SCHEDULE_ID" 

create_task "$STASK_PROJ_NAME" "$ALERT_ID" "$TARGET_PROJ_ID" "$CONFIG_ID" "$SCHEDULE_ID" 

create_task "$STASK_OTHER_NAME" "$ALERT_ID" "$TARGET_OTHER_ID" "$CONFIG_ID" "$SCHEDULE_ID"

create_task "$TASK_ADM_NAME" "$ALERT_ID" "$TARGET_ADM_ID" "$CONFIG_ID"

create_task "$TASK_PROJ_NAME" "$ALERT_ID" "$TARGET_PROJ_ID" "$CONFIG_ID"

create_task "$TASK_OTHER_NAME" "$ALERT_ID" "$TARGET_OTHER_ID" "$CONFIG_ID"
