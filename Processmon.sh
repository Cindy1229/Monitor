#!/bin/bash


# cycles per second
hertz=$(getconf CLK_TCK)

# Flag for sort, 1 for cpu usage, 2 for virtual mem
FLAG=0

# Process number displayed, initial 20
NUM=20

# Time interval initial 10
TIME_INTERVAL=10

# Process flag, 0->user, 1->all
P_FLAG=0

# Regular expression to check for number
re='^[0-9]+$'

function check_arguments () {

	#Extract arguments
    echo "Extract arguments..."

  	#Check for invalid arguments, the user has to specify at least -c/-m flag, process number and time interval are optional
  	if [ $1 -lt 1 ]
  	then
    	echo "Invalid argument number, please specify flags!"
    	exit
	fi

	# Shift from $# to $@
	shift
	# Set and check flags
	while [ -n "$1" ]; do
		case "$1" in
		-c) 
			if [ $FLAG -eq 2 ]
			then
				echo "You can't have -m and -c in one command!"
				exit
			fi
			FLAG=1 ;;
		-m) 
			if [ $FLAG -eq 1 ]
			then
				echo "You can't have -m and -c in one command!!"
				exit
			fi
			FLAG=2 ;;
		-p) 
			if [[ "$2" =~ $re ]]
			then
				NUM=$2 
				shift 
			else
				echo "Please specify process displayed number!"
				exit
			fi
			;;
		-t) 
			if [[ "$2" =~ $re ]]
			then
				TIME_INTERVAL=$2 
				shift 
			else
				echo "Please specify time interval number!"
				exit
			fi
			;;
		-a) 
			P_FLAG=1
			;;
		*)
			echo "Invalid flags!"
			exit
		esac
		shift
	done

	# Sort by cpu by default
	if [ $FLAG -eq 0 ]
	then
		FLAG=1
	fi

}

function init () {

    echo "Init..."

	echo "flag: $FLAG"
	echo "Top Process Number: $NUM"
	echo "Time interval: $TIME_INTERVAL"
	echo "p_flag: $P_FLAG"

}

# This function prints the dashboard of top
function dashboard
{
	rm -f cpu_state
	touch cpu_state

	

	# Get CPU state
	mpstat 5 1 > cpu_state
	us=$( awk 'NR==4 {print $4}' cpu_state )
	n=$( awk 'NR==4 {print $5}' cpu_state )
	sy=$( awk 'NR==4 {print $6}' cpu_state )
	wa=$( awk 'NR==4 {print $7}' cpu_state )
	hi=$( awk 'NR==4 {print $8}' cpu_state )
	si=$( awk 'NR==4 {print $9}' cpu_state )
	st=$( awk 'NR==4 {print $10}' cpu_state )
	idle=$( awk 'NR==4 {print $13}' cpu_state )

	# Get meminfo
	mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
	mem_free=$(awk '/MemFree/ {print $2}' /proc/meminfo)
	buff=$(awk '/Buffers/ {print $2}' /proc/meminfo)
	cache=$(awk '/^Cached/ {print $2}' /proc/meminfo)
	buff_cache=$(($buff + $cache))
	mem_used=$(($mem_total - $mem_free - $buff_cache))

	swap_total=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
	swap_free=$(awk '/SwapFree/ {print $2}' /proc/meminfo)
	swap_used=$(($swap_total - $swap_free))
	mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)

	#Print first line
	printf "top -"
	uptime
	
	# Print Task line
	printf "Tasks:	%d total,	%d running, 	%d sleeping, 	%d stopped, 	%d zombie\n" $task $run $sleeping $stop $zombie

	# Print CPU state line
	printf "%%Cpu(s):  %.1f us,  %.1f sy,  %.1f ni,  %.1f id,  %.1f wa, %.1f hi,  %.1f si,  %.1f st\n" $us $sy $n $idle $wa $hi $si $st

	#Print memory line
	printf "KiB Mem :  %d total,  %d free, 	%d used, %d buff/cache\n" $mem_total $mem_free $mem_used $buff_cache

	#Print Swap Line
	printf "KiB Swap :  %d total, %d free, 	%d used. %d avail Mem\n" $swap_total $swap_free $swap_used $mem_avail

	#Print a empty line
	printf "\n"
}

# This function calculates number of tasks and their state
function calculate_task
{
	# Variables that keep track of tasks
	task=0
	run=0
	sleeping=0
	stop=0
	zombie=0

	# Get all the processes
	process=$(ls /proc 2>/dev/null | egrep $re)

	# Iterate all processes
	for each in $process
	do
		if [ -d /proc/$each ]
		then
			let "task+=1"
			# State 
			state=$(cat /proc/$each/status | awk '/State/ {print $2}')
			# Update task states
			case $state in
			S)
				let "sleeping+=1"
				;;
			D)
				let "sleeping+=1"
				;;
			R)
				let "run+=1"
				;;
			T)
				let "stop+=1"
				;;
			Z)
				let "zombie+=1"
				;;
			*)	
				;;
			esac
		fi
	done
} 

#This function calculates the CPU usage percentage given the clock ticks in the last $TIME_INTERVAL seconds
function jiffies_to_percentage () {
	
	#Get the function arguments (oldstime, oldutime, newstime, newutime)
	oldstime=$1
	oldutime=$2
	newstime=$3
	newutime=$4

	#Calculate the elpased ticks between newstime and oldstime (diff_stime), and newutime and oldutime (diff_stime)
	diff_stime=$(($newstime - $oldstime))
	diff_utime=$(($newutime - $oldutime))

	#You will use the following command to calculate the CPU usage percentage. $TIME_INTERVAL is the user-provided time_interval
	#Note how we are using the "bc" command to perform floating point division

	echo "100 * ( ($diff_stime + $diff_utime) / $hertz) / $TIME_INTERVAL" | bc -l
}


#This function takes as arguments the cpu usage and the memory usage that were last computed
function generate_top_report () {
    echo "Top report..."

	# Remove and create data file and sort file
	rm -f result
	rm -f s_report
	touch result
	touch s_report

	# Variables that keep track of tasks
	task=0
	run=0
	sleeping=0
	stop=0
	zombie=0


	# If p_flag is 0, we need to traverse all tasks to get the task number
	if [ $P_FLAG -eq 0 ]
	then
		calculate_task
	fi

	# Iterate through the pid that and calculate data
	while IFS= read -r line
	do
		# Get pid and cpu usage from cpu_data
		pid=$(echo $line | awk '{print $1}')
		cpu_usage=$(echo $line | awk '{print $2}')

		if [ -d /proc/$pid ]
		then
			#Get username
			uid=$(cat /proc/$pid/status | awk '/Uid/ {print $2}')
			name=$(id -nu $uid)
			# PR and NI
			pr=$(cat /proc/$pid/stat | awk '{print $18}')
			ni=$(cat /proc/$pid/stat | awk '{print $19}')
			# VIRT and RES
			virt=$(cat /proc/$pid/status | awk '/VmSize/ {print $2}')
			res=$(cat /proc/$pid/status | awk '/VmRSS/ {print $2}')
			# calculate shr by adding rssfile and rssShmem
			rssfile=$(cat /proc/$pid/status | awk '/RssFile/ {print $2}')
			rssShemem=$(cat /proc/$pid/status | awk '/RssShmem/ {print $2}')
			let "shr=rssfile + rssShemem"
			# State 
			state=$(cat /proc/$pid/status | awk '/State/ {print $2}')
			
			# If p_flag is 1 we need to update task number and state
			if [ $P_FLAG -eq 1 ]
			then
				let "task+=1"
				# State state
				state=$(cat /proc/$pid/status | awk '/State/ {print $2}')
				# Update task states
				case $state in
				S)
					let "sleeping+=1"
					;;
				D)
					let "sleeping+=1"
					;;
				R)
					let "run+=1"
					;;
				T)
					let "stop+=1"
					;;
				Z)
					let "zombie+=1"
					;;
				*)	
					;;
				esac

			fi

			# %MEM= RES/MemTotal
			total=$(cat /proc/meminfo | awk '/MemTotal/ {print $2}')
			if [ ! -z $res ]
			then
				mem_usage=$( echo "($res/$total)*100" | bc -l )
				#echo res/mem: $res/$total mem: $mem_usage
			else
				res=0
				shr=0
				virt=0
				mem_usage=0
			fi
			# Get Time
			utime=$(awk '{print $14}' /proc/$pid/stat)
			stime=$(awk '{print $15}' /proc/$pid/stat)
			jtime=$(($utime + $stime))
			second1=$( echo "($jtime/100)" | bc -l )
			int_second=$( echo "$second1/1" | bc )
			milisecond=$( echo "$second1%1" | bc )
			milisecond=$( echo "($milisecond * 100)/1" | bc )
			minute=$(($int_second / 60))
			second2=$(($int_second % 60))
			# Command line
			comm=$(cat /proc/$pid/status 2>/dev/null | awk '/Name/ {$1=""; print $0}')
			#echo comm: $comm

			# Output the data to result
			printf "%6s %-10s %4s %4s %10s %10s %10s %s  %4.1f       %4.1f     %2s:%02d.%02d   $comm\n" $pid $name $pr $ni $virt $res $shr $state $cpu_usage $mem_usage $minute $second2 $milisecond >> result
			
		fi
	done < cpu_data

	# Sort the result and output the result to s_report according to flag
	if [ $FLAG -eq 1 ]
	then
		sort -r -n -k 9,9 result > s_report
	fi
	if [ $FLAG -eq 2 ]
	then
		sort -r -n -k 5,5 result > s_report
	fi

	clear
	# Prints the dashboard
	dashboard

	# Print the sorted info on terminal
	echo -e "   PID USER         PR   NI       VIRT        RES        SHR S  %CPU       %MEM      TIME+      COMMAND"

	# Select the first NUM lines into report
	l_num=0
	while IFS= read -r line
	do
		printf "$line\n"
		let "l_num += 1"
		if [ $l_num -eq $NUM ]
		then
			break
		fi
	done < s_report

}

#Returns a percentage representing the CPU usage
function calculate_cpu_usage () {

	#CPU usage is measured over a periode of time. We will use the user-provided interval_time value to calculate 
	#the CPU usage for the last interval_time seconds. For example, if interval_time is 5 seconds, then, CPU usage
	#is measured over the last 5 seconds


	#First, get the current utime and stime (oldutime and oldstime) from /proc/{pid}/stat
	oldutime=$(awk '{print $14}' /proc/$1/stat)
	oldstime=$(awk '{print $15}' /proc/$1/stat)

	#Sleep for time_interval
	sleep $TIME_INTERVAL

	#Now, get the current utime and stime (newutime and newstime) /proc/{pid}/stat
	newutime=$(awk '{print $14}' /proc/$1/stat)
	newstime=$(awk '{print $15}' /proc/$1/stat)

	#The values we got so far are all in jiffier (not Hertz), we need to convert them to percentages, we will use the function
	#jiffies_to_percentage

	percentage=$(jiffies_to_percentage $oldutime $oldstime $newutime $newstime)


	#Return the usage percentage
	echo "$percentage" #return the CPU usage percentage
}

#Calculate the cpu usage of all preocesses
function calculate
{
	rm -f cpu_data
	touch cpu_data
	unset files
	unset oldstime
	unset oldutime
	unset newstime
	unset newutime


	#Iterate and get the process dirs
	if [ $P_FLAG -eq 0 ]
	then
		#echo "p-flag is zero"
		dir=$(ls -al /proc 2>/dev/null | grep $USER | awk '{print $9}')
	else
		#echo "p-flag is 1"
		dir=$(ls /proc 2>/dev/null | egrep $re)
	fi

	#Flag is the one for valid processes
	for each in $dir
	do
		if [ -d /proc/$each ]
		then
			files+=("$each")
		fi
	done
	

	# Get old/new utime/stime and calculate the cpu usage
	for i in "${files[@]}"
	do
		if [ -d /proc/$i ]
		then
			utime=$(awk '{print $14}' /proc/$i/stat)
			stime=$(awk '{print $15}' /proc/$i/stat)
			oldutime+=($utime)
			oldstime+=($stime)
		else
			oldutime+=(-1)
			oldstime+=(-1)
		fi
	done

	sleep $TIME_INTERVAL

	for i in "${files[@]}"
	do
		if [ -d /proc/$i ]
		then
			utime=$(awk '{print $14}' /proc/$i/stat)
			stime=$(awk '{print $15}' /proc/$i/stat)
			newutime+=($utime)
			newstime+=($stime)
		else
			newutime+=(-1)
			newstime+=(-1)
		fi
	done

	# Get diff time and use it to calculate %cpu
	count=${#files[@]}
	#count1=${#newstime[@]}
	#count2=${#oldstime[@]}
	#echo count: $count
	#echo "$count new: $count1 old: $count2"
	#exit
	for ((i=0;i<$count;i++))
	do
		if [[ -d "/proc/${files[i]}" ]] && [[ ${newstime[i]} != -1 ]]
		then
			diff_stime=$((${newstime[i]} - ${oldstime[i]}))
			diff_utime=$((${newutime[i]} - ${oldutime[i]}))
			percentage=$(echo "100 * ( ($diff_stime + $diff_utime) / $hertz) / $TIME_INTERVAL" | bc -l)
			echo "${files[i]} $percentage" >> cpu_data
		fi
	done	

}






check_arguments $# $@

init $1 $@

#procmon runs forever or until ctrl-c is pressed.
#while [ -n "$(ls /proc/$PID)" ] #While this process is alive
while true
do
	# When time interval is 0, only prints the report once and exit
	if [ $TIME_INTERVAL -eq 0 ]
	then
		TIME_INTERVAL=1
		calculate
		generate_top_report
		exit
	fi
	calculate
	generate_top_report 
	sleep 2
done
