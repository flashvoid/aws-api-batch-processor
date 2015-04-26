#!/bin/bash 
# apt-get install -y jq

source config.sh

reset_globals () {
	declare -g RECEIPT=""
	declare -g JENKINS_BUILD=""
	declare -g JENKINS_JOB=""
	declare -g SOURCE=""
	declare -g MESSAGE=""
	declare -g UNPACK=""
	declare -g RUN_CMD=""
	declare -g RUN_SUBCMD=""
	declare -g RUN_ACTION=""
	declare -g RUN_OPTION=""
	declare -g PRERUN_CMD=""
	declare -g PRERUN_OPTION=""
        declare -g AWS_RETURN=""
}

parse_message () {
	MESSAGE=$( echo $RES | jq -r '.Messages[].Body' )
	UNPACK=$(  echo $MESSAGE | base64 -d )
	RUN_CMD=$( echo $UNPACK | jq -r .RunCommand )         ; [[ $RUN_CMD == "null" ]] && RUN_CMD=""
	RUN_SUBCMD=$( echo $UNPACK | jq -r .RunSubCommand )   ; [[ $RUN_SUBCMD == "null" ]] && RUN_SUBCMD=""
	RUN_ACTION=$( echo $UNPACK | jq -r .RunAction )       ; [[ $RUN_ACTION == "null" ]] && RUN_ACTION=""
	RUN_OPTION=$( echo $UNPACK | jq -r .RunOptions )      ; [[ $RUN_OPTION == "null" ]] && RUN_OPTION=""
	PRERUN_CMD=$( echo $UNPACK | jq -r .PreRunCommand )   ; [[ $PRERUN_CMD == "null" ]] && PRERUN_CMD=""
	PRERUN_OPTION=$( echo $UNPACK | jq -r .PreRunOptions ); [[ $PRERUN_OPTION == "null" ]] && PRERUN_OPTION=""
	JENKINS_BUILD=$( echo $UNPACK | jq -r .JenkinsBuild ) ; [[ $JENKINS_BUILD == "null" ]] && JENKINS_BUILD=""
	JENKINS_JOB=$( echo $UNPACK | jq -r .JenkinsJob )     ; [[ $JENKINS_JOB == "null" ]] && JENKINS_JOB=""
}

run_command () {
	if check_permissions; then
		if [[ $PRERUN_CMD ]]; then
			$PRERUN_CMD $PRERUN_OPTION
		fi
                if AWS_RETURN=$($RUN_CMD $RUN_SUBCMD $RUN_ACTION $RUN_OPTION); then
                        return 0
                else
                        return 1
                fi
	fi
}

check_permissions () {
	if [[ $RUN_CMD != "aws" ]]; then
		return 1
	else
		return 0
	fi
}

notify_ci () {
	RESULT=$1
	MESSAGE_PACK=$( echo $AWS_RETURN | base64 -w0 )
	MESSAGE="{\"Name\":{\"S\":\"ci-$JENKINS_JOB\"},\"JenkinsBuild\":{\"N\":\"$JENKINS_BUILD\"},\"Result\":{\"S\":\"$RESULT\"},\"AwsReturn\":{\"S\":\"$MESSAGE_PACK\"}}"

	aws dynamodb put-item --table-name $DY_TABLE --item $MESSAGE
}

while :; do 
	reset_globals

	RES=$(aws sqs receive-message --queue-url $QUEUE --output json)
	if [[ $? == 0 ]]; then
		RECEIPT=$( echo $RES | jq -r '.Messages[].ReceiptHandle' )
		if [[ $RECEIPT ]]; then 
			parse_message
			run_command && notify_ci "success" || notify_ci "fail"
			echo -e "$MESSAGE, $RECEIPT"
			aws sqs delete-message --receipt-handle $RECEIPT --queue-url $QUEUE
		fi
	fi
	sleep 5
done
