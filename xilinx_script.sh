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
MAX_TRIGGER='10'
JOB_HOURS=7
TERMINATE_MINS=20

GATE_URL="$GATE_SERVER/autopilot/registerCanary"

### PLEASE REPLACE DESIRED ARTIFATORY URL
ARTIFACTORY_URL='https://artifactory/artifactory/api/build/sw_integration_test::2021.1.0::linux';

usage="$(basename "$0") [-help]

-- Example to show how to pass relevant arguments.

USAGE:
$(basename "$0") -basejobid=100 -canaryjobid=221  -testcases=20 -basestart=1608196811570 -canarystart=1608198772262 -autopilot_enabled=false;

args:
  -basejobid=<baseline job id>
  -canaryjobid=<New Release job id>
  -basestart=<Baseline job start time in Epoch format>
  -canarystart=<Canary job start time in Epoch format>
  -testcases=<Maximum number of test cases. '0' means all>
  -autopilot_enabled=<Trigger autopilot analysis, by default true>"


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
    -autopilot_enabled=*)
    AUTOPILOT_ENABLED="${i#*=}"
    shift # past argument=value
    ;;
    *)
     echo "$usage";
     exit 1
     ;;
esac
done

AUTOPILOT_ENABLED="${AUTOPILOT_ENABLED:-true}"

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

if [[ $AUTOPILOT_ENABLED = true  ]]; then
   
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
                 \"notificationHours\": []
             },
             \"canaryHealthCheckHandler\": {
                 \"minimumCanaryResultScore\": \"$minimumCanaryScore\"
             },
             \"canarySuccessCriteria\": {
                 \"canaryResultScore\": \"$canaryResultScore\"
             },
             \"combinedCanaryResultStrategy\": \"AGGREGATE\",
             \"lifetimeMinutes\": $5,
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
     response=$(curl -sS -k --retry 3 --retry-connrefused --retry-delay 240 -H  "Content-Type:application/json"  -X POST -d "$jsondata" "$GATE_URL" || true);
     canaryid='';
     if [[ $response == *"canaryId"* ]]; then
       canaryid=$(jq -r '.canaryId' <<< "$response");
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
       sleep 0.1
       CANARYID=${CANARY_IDS[$j]};
       RESPONSE=$(curl -sS -k -H  "Content-Type:application/json"  -X GET "$GATE_SERVER/autopilot/canaries/${CANARYID}" || true);
       STATUS='null';
       if [[ $RESPONSE == *"services"* ]]; then
         STATUS=$(jq -r '.services[0].healthStatus' <<< "$RESPONSE");
       fi
     
       if [ "$STATUS" != "InProgress" ] && [ "$STATUS" != "Running" ] && [ "$STATUS" != "null" ] && [ ! -z "$STATUS" ]; then
         echo "CanaryId => ${CANARY_IDS[$j]}  Result => $STATUS";
         ((loopcount=loopcount-1))
         
         local CanaryTime=$(((${DESC_CANARY_FILES[$j]}/1000) - (${ASC_CANARY_FILES[$j]}/1000)));
         local basefile=${j///$CANARY_JOB_ID//$BASE_JOB_ID};
         local basestarttime=${ASC_BASELINE_FILES[$basefile]};
         if [ ! -z "$basestarttime" ]; then
   	 BaselineTime=$(((${DESC_BASELINE_FILES[$basefile]}/1000) - (${ASC_BASELINE_FILES[$basefile]}/1000)));
         fi
   
         UI_URL="$AUTOPILOT_UI/application/deploymentverification/$application/${CANARYID}"
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
         unset CANARY_TRIGTIME[${CANARYID}];
         unset CANARY_IDS[$j];
       else
         if [[ $(($(date -u +%s) -  ${CANARY_TRIGTIME[${CANARYID}]}))  -gt $((TERMINATE_MINS * 60)) ]]; then
   	 echo "terminating the analysis ${CANARYID}"
   	 curl -sS -k -H  "Content-Type:application/json"  -X GET "$GATE_SERVER/autopilot/canaries/cancelRunningCanary?id=${CANARYID}" > /dev/null;
   	 unset CANARY_TRIGTIME[${CANARYID}];
            unset CANARY_IDS[$j];
   	 ((loopcount=loopcount-1))
          fi
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
   declare -A CANARY_TRIGTIME;
   
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
      
      if [[ $bTime -gt $cTime ]]; then
         E_TIME=$bTime;
      else
         E_TIME=$cTime;
      fi
   
      E_TIME=$(( (E_TIME + 59) / 60 ))
      if [[ (($E_TIME -lt 2)) ]]; then
           E_TIME=2
      fi
      
      #########
      ((filecount=filecount+1))
   
      canaryid=`trigger_canary "$BASEFILE" "$BASE_STARTTIME" "$i" "$CANARY_STARTTIME" "$E_TIME"`;
      echo "canaryId ==> $canaryid  test_case => $i"
      
      if [ ! -z "$canaryid" ] && [ "$canaryid"  != "null" ]; then
       CANARY_IDS[$i]=$canaryid;
       CANARY_TRIGTIME[$canaryid]=$(date -u +%s);
       ((loopcount=loopcount+1))
      fi
   
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

   if [ ${#LIN_HTML_TABLE[@]} -eq 0 ]; then
    LIN_HTML_TABLE+="<tr class=\"skippedodd\" height=\"35px\">
                          <td></td>
                          <td style=\"text-align:center;\"></td>
                          <td style=\"text-align:center;\"></td>
                       <td style=\"text-align:center;\"></td>
                       <td></td>
                       <td></td>
                          <td></td>
                          </tr>";
   fi

   if [ ${#WIN_HTML_TABLE[@]} -eq 0 ]; then
      WIN_HTML_TABLE+="<tr class=\"skippedodd\" height=\"35px\">
                          <td></td>
                          <td style=\"text-align:center;\"></td>
                          <td style=\"text-align:center;\"></td>
                       <td style=\"text-align:center;\"></td>
                       <td></td>
                       <td></td>
                          <td></td>
                          </tr>";
   fi

   AUTOPILOT_ANALYSIS="<h3>Environment: Linux</h3>
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
                </tbody>";

else
   AUTOPILOT_ANALYSIS='';
fi
#---------------------------------------------------------------------------------------------------------------

declare -A CANARYDEPENDENCY;
declare -A BASEDEPENDENCY;

IFS="," read -a components_list <<< $COMPONENTS

curl -k $ARTIFACTORY_URL/$CANARY_JOB_ID > /tmp/newrelease_info.json
curl -k $ARTIFACTORY_URL/$BASE_JOB_ID > /tmp/baseline_info.json


for k in $(jq '.buildInfo.properties | keys | .[]' /tmp/newrelease_info.json); do
     value=$(jq -r ".buildInfo.properties.$k" /tmp/newrelease_info.json );
     CANARYDEPENDENCY[$k]=$value
done


for k in $(jq '.buildInfo.properties | keys | .[]' /tmp/baseline_info.json ); do
    value=$(jq -r ".buildInfo.properties.$k" /tmp/baseline_info.json );
    BASEDEPENDENCY[$k]=$value
done

TOTAL_COMPONENTS=${#components_list[@]};
for k in "${!components_list[@]}"; do
	components_regex+=$(echo "*${components_list[$k]}\"");
	if [[ $k -lt $TOTAL_COMPONENTS-1 ]] ; then
		components_regex+='|'
	fi
done

echo $components_regex

for j in "${!CANARYDEPENDENCY[@]}"; do
    BASE_VALUE=${BASEDEPENDENCY[$j]};
    if [[ $j == *'Version"' ]]; then
       if [ ! -z "${CANARYDEPENDENCY[$j]}" ] && [ ! -z "$BASE_VALUE" ]; then
          if [ ${CANARYDEPENDENCY[$j]} != $BASE_VALUE ]; then
             CANARY_VERSION_COMPARE+=$j="<p style=\"background-color:yellow;display:inline\">${CANARYDEPENDENCY[$j]} </p>, <br>";
             BASE_VERSION_COMPARE+=$j="<p style=\"display:inline\">$BASE_VALUE </p>, <br>";
          else
             CANARY_VERSION_COMPARE+="<p style=\"display:inline\">$j=${CANARYDEPENDENCY[$j]} </p>, <br>";
             BASE_VERSION_COMPARE+="<p style=\"display:inline\">$j=$BASE_VALUE </p>, <br>";
          fi      
       elif [ ! -z "${CANARYDEPENDENCY[$j]}" ] && [ -z "$BASE_VALUE" ]; then
           CANARY_VERSION_COMPARE+="<p style=\"background-color:yellow;display:inline\">$j=${CANARYDEPENDENCY[$j]} </p>, <br>";
       fi
    fi
    
    if [[ ${CANARYDEPENDENCY[$j]} == "com.xilinx"* ]] && [[ ! $j == *'Deparray"' ]] && [[ ! $j == +($components_regex)  ]] ; then

        IFS="," read -a canaryMultiComponents <<< ${CANARYDEPENDENCY[$j]}
        IFS="," read -a baseMultiComponents <<< $BASE_VALUE

        COMMON_ALL=$(comm -12 <(printf '%s\n' "${canaryMultiComponents[@]}" | sort -u) <(printf '%s\n' "${baseMultiComponents[@]}" | sort -u) | tr '\n' ' ')
        DIFF_ALL=$(echo ${canaryMultiComponents[@]} ${baseMultiComponents[@]} | tr ' ' '\n' | sort | uniq -u | tr '\n' ' ');
        canary_diff=$(echo ${canaryMultiComponents[@]} ${DIFF_ALL[@]} | tr ' ' '\n' | sort | uniq -D | uniq | tr '\n' ' ');
        baseline_diff=$(echo ${baseMultiComponents[@]} ${DIFF_ALL[@]} | tr ' ' '\n' | sort | uniq -D | uniq | tr '\n' ' ');
        
        for i in "${!COMMON_ALL[@]}"; do
           canary_modules_diff+=${COMMON_ALL[$i]}
           baseline_modules_diff+=${COMMON_ALL[$i]}
        done

        
	for l in "${!canaryMultiComponents[@]}"; do
          IFS=':' read -r key1 value1 <<< "${canaryMultiComponents[$l]}"
          mulitiplemodule[$l]=$key1
        done
        
        declare -A seen;
	HASDUPMODULE=false;
        
        for i in "${mulitiplemodule[@]}"; do
            # If element of arr is not in seen, add it as a key to seen
            if [ -z "${seen[$i]}" ]; then
                seen[$i]=1
            else
                HASDUPMODULE=true;
                break
            fi
        done

        mulitiplemodule=();
	unset seen;

        if [ ${#canary_diff[@]} -gt 0 ] || [ ${#baseline_diff[@]} -gt 0 ]; then
           for i in "${!canary_diff[@]}"; do
               canary_modules_diff+="<p style=\"background-color:yellow;display:inline\">${canary_diff[$i]}</p>,"
           done
           for i in "${!baseline_diff[@]}"; do
               baseline_modules_diff+="<p style=\"display:inline\">${baseline_diff[$i]}</p>,"
           done
           
           if [ "$HASDUPMODULE" = true ] ; then
               CANARY_CHNAGED_MODULES+="<p style=\"background-color:#eca7a7;display:inline\">$j</p>= $canary_modules_diff <br>"
           else
	       CANARY_CHNAGED_MODULES+="$j= $canary_modules_diff <br>"
           fi
           BASE_CHANGED_MODULES+="$j= $baseline_modules_diff <br>"

        fi

        canary_modules_diff='';
        baseline_modules_diff='';
    fi
done

for j in "${!BASEDEPENDENCY[@]}"; do
    CANARY_VALUE=${CANARYDEPENDENCY[$j]};
    if [[ $j == *'Version"' ]]; then      
       if [ ! -z "${BASEDEPENDENCY[$j]}" ] && [ -z "$CANARY_VALUE" ]; then
           BASE_VERSION_COMPARE+="<p style=\"background-color:yellow;display:inline\">$j=${BASEDEPENDENCY[$j]} </p>, <br>";
       fi
    fi

    if [[ ${BASEDEPENDENCY[$j]} == "com.xilinx"* ]] && [[ ! $j == *'Deparray"' ]] && [[ -z "$CANARY_VALUE" ]] && [[ ! $j == +($components_regex)  ]]; then


        IFS="," read -a baseMultiComponents <<< ${BASEDEPENDENCY[$j]}
        IFS="," read -a canaryMultiComponents <<< $CANARY_VALUE

        DIFF_ALL=$(echo ${canaryMultiComponents[@]} ${baseMultiComponents[@]} | tr ' ' '\n' | sort | uniq -u | tr '\n' ' ');
        baseline_diff=$(echo ${baseMultiComponents[@]} ${DIFF_ALL[@]} | tr ' ' '\n' | sort | uniq -D | uniq | tr '\n' ' ');

        if [ ${#baseline_diff[@]} -gt 0 ]; then
           for i in "${!baseline_diff[@]}"; do
               baseline_modules_diff+="<p style=\"background-color:yellow;display:inline\">${baseline_diff[$i]}</p>,"
           done

           BASE_CHANGED_MODULES+="$j= $baseline_modules_diff <br>"
        fi
        baseline_modules_diff='';
    fi
done

  BASE_CHANGED_MODULES=${BASE_CHANGED_MODULES:0:-7};
  CANARY_CHNAGED_MODULES=${CANARY_CHNAGED_MODULES:0:-7};
  BASE_VERSION_COMPARE=${BASE_VERSION_COMPARE:0:-7};
  CANARY_VERSION_COMPARE=${CANARY_VERSION_COMPARE:0:-7};

COMPONENT_CHANGED+="<tr class=\"skippedodd\">
                      <td>$BASE_VERSION_COMPARE</td>
                      <td>$CANARY_VERSION_COMPARE</td>
                    </tr>";

MODULE_CHANGED+="<tr class=\"skippedodd\">
                      <td>$BASE_CHANGED_MODULES</td>
                      <td>$CANARY_CHNAGED_MODULES</td>
                    </tr>";



#---------------------------------------------------------------------------

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
        <h3>Component Dependencies</h3>
	<table id='summary'>
                <thead>
                        <tr>
                                <th>Baseline</th>
                                <th>New Build</th>
                        </tr>
                </thead>
                <tbody id=\"t0\">
                   $COMPONENT_CHANGED
                </tbody>
        </table>

	<h3>Transitive Dependencies</h3>
        <table id='summary'>
                <thead>
                        <tr>
                                <th>Baseline</th>
                                <th>New Build</th>
                        </tr>
                </thead>
                <tbody id=\"t0\">
                   $MODULE_CHANGED
                </tbody>
        </table>
	$AUTOPILOT_ANALYSIS
	</body>
	</html>"

mkdir -p $REPORTDIR
echo "$resultFile" > $(echo "$REPORTDIR/${BASE_JOB_ID}_${CANARY_JOB_ID}_result.html");

echo "Analysis Completed";
