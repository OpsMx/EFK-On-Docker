#!/bin/bash

REPORTDIR='/home/xilinx/scripts'
ES_SERVER=https://oeselastic7.opsmx.com
INDEX_PATTERN='opsmx-*'

#Autopilot urls
AUTOPILOT_UI='http://20.69.130.245'
GATE_SERVER='http://20.69.130.234:8084'

#Application Name, Service Name
application='xilinxtest03'
serviceName='svc1'
beginCanaryAnalysisAfterMins=0
minimumCanaryScore=95
canaryResultScore=95
username='admin'
MAX_TRIGGER='20'
JOB_HOURS=7

GATE_URL="$GATE_SERVER/autopilot/registerCanary"

usage="$(basename "$0") [-help]

-- Example to show how to pass relevant arguments.

USAGE:
$(basename "$0") -basejobid=100 -canaryjobid=221  -testcases=20 -basestart=1608196811570 -canarystart=1608198772262;

args:
  -basejobid=<baseline job id>
  -canaryjobid=<New Release job id>
  -basestart=<Baseline job start time in Epoch format>
  -canarystart=<Canary job start time in Epoch format>
  -testcases=<Maximum number of test cases. '0' means all>"


for i in "$@"
do
case $i in
    -basejobid=*)
    BASE_JOB_ID="${i#*=}"
    shift # past argument=value
    ;;
    -canaryjobid=*)
    CANARY_JOB_ID="${i#*=}"
    shift # past argument=value
    ;;
    -basestart=*)
    BASE_JOB_START="${i#*=}"
    shift # past argument=value
    ;;
    -canarystart=*)
    CANARY_JOB_START="${i#*=}"
    shift # past argument=value
    ;;
    -testcases=*)
    TRIGGER_COUNT="${i#*=}"
    shift # past argument=value
    ;;
    *)
     echo "$usage";
     exit 1
     ;;
esac
done


if [[ -z "$BASE_JOB_ID" ]]; then
  echo "Provide Baseline Job Id";
  echo "$usage";
  exit 1;
fi

if [[ -z "$CANARY_JOB_ID" ]]; then
  echo "Provide Canary Job Id";
  echo "$usage";
  exit 1;
fi

if [[ -z "$BASE_JOB_START" ]]; then
  echo "Provide Baseline Start Time in Epoch";
  echo "$usage";
  exit 1;
fi

if [[ -z "$CANARY_JOB_START" ]]; then
  echo "Provide Canary Start Time in Epoch";
  echo "$usage";
  exit 1;
fi

TRIGGER_COUNT=${TRIGGER_COUNT:-0}

BASE_JOB_START=$(echo ${BASE_JOB_START:0:10});
CANARY_JOB_START=$(echo ${CANARY_JOB_START:0:10});

echo "Canary Job Id => $CANARY_JOB_ID Baseline Job Id => $BASE_JOB_ID Canary Job StartTime => $CANARY_JOB_START Baseline Job StartTime => $BASE_JOB_START  No. of Canaries to trigger => $TRIGGER_COUNT";

######## function to list unique testcases, have to pass jobid, CANARY_FILES/BASELINE_FILES and ASC/DESC
function list_files () {

  QUERY="{
      \"size\":1000,
      \"sort\":[{\"@timestamp\":{\"order\":\"$3\"}}],
      \"_source\":false,
      \"query\":{
        \"bool\":{
          \"must\":[
            {
              \"range\":{
                \"@timestamp\":{
                  \"gte\":$4,
                  \"lte\":$5,
                  \"format\":\"epoch_second\"
                }
              }
            },
            {
              \"match_phrase\":{
                \"file_name\":\"\/$1\/integration_testing\/\"
              }
            }
          ]
        }
      },
      \"collapse\":{
        \"field\":\"file_name.keyword\"
      }
    }"

  ES_RESPONSE=$(curl -sS -k -H  "Content-Type:application/json"  -X GET --insecure --user $ES_USER:$ES_PWD  -d "$QUERY" "$ES_SERVER/$INDEX_PATTERN/_search?pretty");
  count=$(jq -r '.hits.total.value' <<< "$ES_RESPONSE");

  if [[  "$count" -gt 0 ]]
  then
      for k in $(jq '.hits.hits | keys | .[]' <<< "$ES_RESPONSE"); do
        value=$(jq -r ".hits.hits[$k]" <<< "$ES_RESPONSE");
        file_name=$(jq -r '.fields."file_name.keyword"[0]' <<< "$value");
        timestamp=$(jq -r '.sort[0]' <<< "$value");
        if [[ "$2" == "CANARY_FILES" ]]
        then
        	read "$3_CANARY_FILES[$file_name]" <<<  "$timestamp";
        else
          read "$3_BASELINE_FILES[$file_name]" <<<  "$timestamp";
        fi	
      done     
  fi
}


###### function to construct payload and triggering canary
function trigger_canary () {

  jsondata="{
      \"application\": \"$application\",
      \"isJsonResponse\": true,
      \"canaryConfig\": {
          \"canaryAnalysisConfig\": {
              \"beginCanaryAnalysisAfterMins\": \"$beginCanaryAnalysisAfterMins\",
              \"canaryAnalysisIntervalMins\": \"$5\",
              \"notificationHours\": []
          },
          \"canaryHealthCheckHandler\": {
              \"minimumCanaryResultScore\": \"$minimumCanaryScore\"
          },
          \"canarySuccessCriteria\": {
              \"canaryResultScore\": \"$canaryResultScore\"
          },
          \"combinedCanaryResultStrategy\": \"AGGREGATE\",
          \"lifetimeHours\": \"$6\",
          \"name\": \"$username\"
      },
      \"canaryDeployments\": [
          {
              \"baseline\": {
                  \"log\": {
                      \"$serviceName\": {
                          \"file_name\": \"$1\"
                      }                    
                  }
              },
              \"baselineStartTimeMs\": $2,
              \"canaryStartTimeMs\": $4,
              \"canary\": {
                  \"log\": {
                      \"$serviceName\": {
                          \"file_name\": \"$3\"
                      }                        
                  }
              }
          }
      ]
  }"

  response=$(curl -sS -k -H  "Content-Type:application/json"  -X POST -d "$jsondata" "$GATE_URL");
  canaryid=$(jq -r '.canaryId' <<< "$response");
  if [ -z "$canaryid" ] && [ "$canaryid"  = "null" ]; then
	echo "canaryid --> $canaryid   RESPONSE --> $response"
  fi
  echo "$canaryid";
}
###### function to convert epoch seconds to HH:mm:ss format
function seconds2time ()
{
   local T=$1
   local H=$((T/60/60%24))
   local M=$((T/60%60))
   local S=$((T%60))

   if [[ ${H} != 0 ]]
   then
      printf '%02d:%02d:%02d' $H $M $S
   else
      printf '%02d:%02d' $M $S
   fi
}

### function to check canary analysis status of canary ids present in array and remove canaryid from array if analysis done.
function check_status () {
  for j in "${!CANARY_IDS[@]}"; do
    CANARY_URL="$GATE_SERVER/autopilot/canaries/getServiceList?canaryId=${CANARY_IDS[$j]}"
    RESPONSE=$(curl -sS -k -H  "Content-Type:application/json"  -X GET "$GATE_SERVER/autopilot/canaries/${CANARY_IDS[$j]}" );
    STATUS=$(jq -r '.services[0].healthStatus' <<< "$RESPONSE");
  
    if [ "$STATUS" != "InProgress" ] && [ "$STATUS" != "null" ] && [ ! -z "$STATUS" ]; then
      echo "CanaryId => ${CANARY_IDS[$j]}  Result => $STATUS";
      ((loopcount=loopcount-1))
      
      local CanaryTime=$(((${DESC_CANARY_FILES[$j]}/1000) - (${ASC_CANARY_FILES[$j]}/1000)));
      local basefile=${j///$CANARY_JOB_ID//$BASE_JOB_ID};
      local basestarttime=${ASC_BASELINE_FILES[$basefile]};
      if [ ! -z "$basestarttime" ]; then
	 BaselineTime=$(((${DESC_BASELINE_FILES[$basefile]}/1000) - (${ASC_BASELINE_FILES[$basefile]}/1000)));
      fi

      UI_URL="$AUTOPILOT_UI/application/deploymentverification/$application/${CANARY_IDS[$j]}"
      TEST_CASE=${j#/$CANARY_JOB_ID};
      if [[ "$TEST_CASE" == *lnx64.OUTPUT ]]; then
	      LIN_HTML_TABLE+="<tr class=\"skippedodd\">
                       <td>$TEST_CASE</td>
                       <td style=\"text-align:center;\">$STATUS</td>
                       <td style=\"text-align:center;\">`seconds2time $CanaryTime`</td>
		       <td style=\"text-align:center;\">`seconds2time $BaselineTime`</td>
		       <td>$(jq -r '.services[0].failureCause' <<< "$RESPONSE")</td>
		       <td>$(jq -r '.services[0].failureCauseComment' <<< "$RESPONSE")</td>
                       <td><a href=$UI_URL>$UI_URL</a></td>
                       </tr>";
      else
	      WIN_HTML_TABLE+="<tr class=\"skippedodd\">
                       <td>$TEST_CASE</td>
                       <td style=\"text-align:center;\">$STATUS</td>
                       <td style=\"text-align:center;\">`seconds2time $CanaryTime`</td>
		       <td style=\"text-align:center;\">`seconds2time $BaselineTime`</td>
		       <td>$(jq -r '.services[0].failureCause' <<< "$RESPONSE")</td>
		       <td>$(jq -r '.services[0].failureCauseComment' <<< "$RESPONSE")</td>
                       <td><a href=$UI_URL>$UI_URL</a></td>
                       </tr>";
      fi

      unset CANARY_IDS[$j];
    fi
  done
}


declare -A ASC_CANARY_FILES;
declare -A ASC_BASELINE_FILES;
declare -A DESC_CANARY_FILES;
declare -A DESC_BASELINE_FILES;


list_files "$CANARY_JOB_ID" "CANARY_FILES" "ASC" "$CANARY_JOB_START" "$((CANARY_JOB_START + (JOB_HOURS * 3600)))";
if [ ${#ASC_CANARY_FILES[@]} -eq 0 ]; then
  echo "No data found in elasticsearch. Please provide valid canary job id";
  exit 1;
fi
echo "Retrieving Canary test cases completed"

list_files "$BASE_JOB_ID" "BASELINE_FILES" "ASC" "$BASE_JOB_START" "$((BASE_JOB_START + (JOB_HOURS * 3600)))";
if [ ${#ASC_BASELINE_FILES[@]} -eq 0 ]; then
  echo "No data found in elasticsearch. Please provide valid baseline job id";
  exit 1;
fi
echo "Retrieving Baseline test cases completed"

list_files "$CANARY_JOB_ID" "CANARY_FILES" "DESC" "$CANARY_JOB_START" "$((CANARY_JOB_START + (JOB_HOURS * 3600)))";
list_files "$BASE_JOB_ID" "BASELINE_FILES" "DESC" "$BASE_JOB_START" "$((BASE_JOB_START + (JOB_HOURS * 3600)))";


filecount=0;
TOTAL_FILES=${#ASC_CANARY_FILES[@]};
loopcount=0
declare -A CANARY_IDS;

echo "Analysis STARTED #########"
date -u +"%Y-%m-%dT%T.%S%:z"
echo "#########"

for i in "${!ASC_CANARY_FILES[@]}"; do
   BASEFILE=${i///$CANARY_JOB_ID//$BASE_JOB_ID};
   BASE_STARTTIME=${ASC_BASELINE_FILES[$BASEFILE]};
   CANARY_STARTTIME=${ASC_CANARY_FILES[$i]};
   btime=0; 

   ######## CALCULATING ANALYSIS INTERVAL 
   cTime=$(((${DESC_CANARY_FILES[$i]}/1000) - ($CANARY_STARTTIME/1000)));
   if [ ! -z "$BASE_STARTTIME" ]; then
     bTime=$(((${DESC_BASELINE_FILES[$BASEFILE]}/1000) - ($BASE_STARTTIME/1000)));
   else 
     BASE_STARTTIME=$CANARY_STARTTIME;
   fi
   
   if [[ $bTime > $cTime ]]; then
      E_TIME=$bTime;
   else
      E_TIME=$cTime;
   fi
   
   E_TIME=$(( (E_TIME + 59) / 60 ))
   if [[ (($E_TIME < 1)) ]]; then
        E_TIME=1
   fi

   lifetimeHours=$(echo "scale=2;$E_TIME/60"|bc)
   if ((  $(echo "$lifetimeHours<0.02"|bc ))); then
         lifetimeHours=0.02
   fi 
   
   #########
   canaryid=`trigger_canary "$BASEFILE" "$BASE_STARTTIME" "$i" "$CANARY_STARTTIME" "$E_TIME" "$lifetimeHours"`;
   echo "canaryId ==> $canaryid  test_case => $i"
   

   if [ ! -z "$canaryid" ] && [ "$canaryid"  != "null" ]; then
    CANARY_IDS[$i]=$canaryid;
    ((loopcount=loopcount+1))
   fi

   ((filecount=filecount+1))
   if [ $TRIGGER_COUNT > 0 ] && [ "$TRIGGER_COUNT" -eq "$filecount" ] ; then
         filecount=$TOTAL_FILES;
   fi

   if [ "$loopcount" -eq "$MAX_TRIGGER" ];  then
      while [ $loopcount -eq "$MAX_TRIGGER" ]
      do
         check_status;
      done
   fi
 
   if [ "$filecount" -eq "$TOTAL_FILES" ];  then
      while [ $loopcount -ne 0 ]
      do
          check_status;
      done
   fi

   if [ "$filecount" -eq "$TOTAL_FILES" ];  then
	   break;
   fi
 done

echo "Analysis COMPLETED #########"
date -u +"%Y-%m-%dT%T.%S%:z"
echo "#########"

resultFile="<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">
	<html xmlns=\"http://www.w3.org/1999/xhtml\">
	<head>
	<meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\"/>
	<title>TestNG Report</title>
	<style type=\"text/css\">
		table {
                 table-layout: fixed; width: 100%;  margin-bottom:10px;border-collapse:collapse;empty-cells:show
                }
                th,td {
                border:1px solid #009;padding:.25em .5em
                }
                th {
                vertical-align:bottom
                }
                td {
                        word-wrap: break-word;
                        vertical-align:top
                }
                table a {
                        font-weight:bold
                }
                .stripe td {
                        background-color: #cec91b
                }
                .review {
                        text-align:right
                }
                .skippedodd td,th {
                        background-color: #DDD
                }
                .skippedeven td {
                        background-color: #CCC
                }
                .failedodd td,.attn {
                        background-color: #F33
                }
                .failedeven td,
                .stripe .attn {
                        background-color: #D00
                }
                .stacktrace {
                        white-space:pre;font-family:monospace
                }
                .totop {
                        font-size:85%;text-align:center;border-bottom:2px solid #000
                }.invisible {display:none}
	</style>
	</head>
	<body>
	<h2 style=\"text-align:center;\">NEW JOB NUMBER: $CANARY_JOB_ID &emsp; BASELINE JOB NUMBER: $BASE_JOB_ID</h2>
	<h3>Environment: Linux</h3>
	<table id='summary'>
		<thead>
			<tr>
				<th>Test Cases</th>
                                <th style=\"width:100px;\">Result</th>
                                <th style=\"width:100px;\">New Execution Time</th>
                                <th style=\"width:100px;\">Baseline Execution Time</th>
                                <th style=\"width:100px;\">Error Tag</th>
				<th style=\"width:200px;\">Error Tag Comments</th>
                                <th>Autopilot Analysis url</th>
			</tr>
		</thead>
		<tbody id=\"t0\">
		   $LIN_HTML_TABLE
		</tbody>
	</table>
	<h3>Environment: Windows</h3>
	<table id='summary'>
                <thead>
                        <tr>
                                <th>Test Cases</th>
                                <th style=\"width:100px;\">Result</th>
                                <th style=\"width:100px;\">New Execution Time</th>
				<th style=\"width:100px;\">Baseline Execution Time</th>
				<th style=\"width:100px;\">Error Tag</th>
				<th style=\"width:200px;\">Error Tag Comment</th>
                                <th>Autopilot Analysis url</th>
                        </tr>
                </thead>
                <tbody id=\"t0\">
                   $WIN_HTML_TABLE
                </tbody>
	</body>
	</html>"

mkdir -p $REPORTDIR
echo "$resultFile" > $(echo "$REPORTDIR/${BASE_JOB_ID}_${CANARY_JOB_ID}_result.html");

echo "Analysis Completed";
