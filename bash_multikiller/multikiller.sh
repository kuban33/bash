#!/bin/env bash
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
## multi killer processor
# mock1 2016-DEC-09 SARA
# - default log to stdout
# - changed metadata file 
# devl1 2016-SEP-07 SARA
# - derived from wtf
#------------------------------------------------------------------------------
# config
CFG_JAVA=${JAVA_HOME}
CFG_JAVA_XMS="-Xms128M"
CFG_JAVA_XMX="-Xmx1024M"
CFG_TRAN="${DP_BIN}/STDFToSXMLConsole/STDFToSXMLConsole.jar"
#get log file from grandmother process which should be DpLoad
CFG_LOG=$(ps -o cmd= -p $(ps -o ppid= -p $$) | awk -F'-log ' '/-log / { print($NF); }' | awk '{ print($1); }') 
MAX_JOBS=2
MAX_JOB_SEC=7200 #2 hours
MAIL_RECIPIENTS=("wtf@wtf.com")

#------------------------------------------------------------------------------
# trap function to handle SIGINT SIGTERM signals
function trap_finish { echo ">>>>>>> waiting for children processes ${JOBS_ARRAY[@]} to finish <<<<<<<"; echo "USE kill -9 $$ to KILL anyway"; wait; exit 255; }
trap trap_finish SIGINT SIGTERM

processfile () {
  THREAD=$1
  VAR_FILE_input=$2
  
  #TRANSLATE STDF to XML
  VAR_FILE_STDFXML_LOG="${VAR_FILE_input}.stdf2xml.log"
  VAR_DIR_WORK="${VAR_DIR_output}.tranwork_$(basename ${VAR_FILE_input})_$$/"
  mkdir ${VAR_DIR_WORK} || ( echo "[${THREAD}] Error not able to create working dir ${VAR_DIR_WORK})"; return 1; ) 
  echo "[${THREAD}]  ... translating datalog: ${VAR_FILE_input} -> ${VAR_DIR_WORK}"
  ( cd $(dirname ${CFG_TRAN}) && ${CFG_JAVA} ${CFG_JAVA_XMS} ${CFG_JAVA_XMX} -jar ${CFG_TRAN} ${VAR_FILE_input} ${VAR_DIR_WORK} ) 2>&1 | tee ${VAR_FILE_STDFXML_LOG}
  KUBANPIPESTATUS=(${PIPESTATUS[@]})
  if (( ${KUBANPIPESTATUS[0]} == 0 ))
  then
    echo "[${THREAD}]  translate datalog successful: ${KUBANPIPESTATUS[0]}"
    find ${VAR_DIR_WORK} -type f | xargs -I {} mv -v {} ${VAR_DIR_output}
    mv ${VAR_FILE_input} ${VAR_DIR_processed}
    rm ${VAR_FILE_STDFXML_LOG}
  else
    echo "[${THREAD}]  translate datalog failed: ${KUBANPIPESTATUS[0]}"
    mv ${VAR_FILE_input} ${VAR_DIR_notprocessed}
    mv ${VAR_FILE_STDFXML_LOG} ${VAR_DIR_notprocessed}
  fi
  rm -r ${VAR_DIR_WORK}
}

notifykillmail () {
UNAME=`uname -n`
WHOAMI=`whoami`
mail -s "${WHOAMI}@${UNAME} ${SITENAME}: $0 killed process" ${MAIL_RECIPIENTS[@]} << EOF
What's up Buddy,
I've just killed process listed below, it was running too long. Go, get there and check me. Thanks.

Process info:
-------------
THREAD_PID: $1
THREAD_NAME: $2
THREAD_START: $3
INPUT_FILE: $4
PROGRAM: ${CFG_JAVA} -jar ${CFG_TRAN} <VAR_FILE_input> <VAR_FILE_STDFXML> ${CFG_BININFO}

EOF
}

#------------------------------------------------------------------------------
# Check args[]
if [[ $# -ne 6 ]]
# not 7
then
  echo "kuban's ungzip: What's up man!"
  echo "USAGE: `basename $0` inputdir outputdir watchdir inputfilemask watchfilemask limit"
  echo "EXAMPLE: `basename $0` inbox/ outbox/ outbox/ .stdf .xml 100"
  exit 1
# save paths from args[]
else
  VAR_DIR_input=$1
  VAR_DIR_output=$2
  VAR_DIR_watch=$3
  VAR_FILESUF_input=$4
  VAR_FILESUF_watch=$5
  VAR_NUMBER_limit=$6
fi

# redirect all 1 output to log file if CFG_LOG set
if [[ ! -z ${CFG_LOG+x} ]]
then
  exec 3<&1
  exec >> ${CFG_LOG} 2>&1
fi

# Check folders
if [[( -d ${VAR_DIR_input}) && ( -d ${VAR_DIR_output}) && ( -d ${VAR_DIR_watch})]]
then
  #sed ensures that directory ends with /
  VAR_DIR_input=`( cd ${VAR_DIR_input}; pwd; ) | sed '/[^\/]$/s/$/\//'`
  VAR_DIR_output=`( cd ${VAR_DIR_output}; pwd; ) | sed '/[^\/]$/s/$/\//'`
  VAR_DIR_watch=`( cd ${VAR_DIR_watch}; pwd; ) | sed '/[^\/]$/s/$/\//'`
else
  echo "Check passed dirs, some not exists:"
  echo "Input dir: ${VAR_DIR_input}"
  echo "Output dir: ${VAR_DIR_output}"
  echo "Watch dir: ${VAR_DIR_watch}"
  exit 2
fi

VAR_DIR_processed="${VAR_DIR_input}Processed/"
if [[ ! -d ${VAR_DIR_processed} ]]
then
  mkdir -p ${VAR_DIR_processed}
fi
VAR_DIR_notprocessed="${VAR_DIR_input}NotProcessed/"
if [[ ! -d ${VAR_DIR_notprocessed} ]]
then
  mkdir -p ${VAR_DIR_notprocessed}
fi

# reference file for comparison not to include files under write progress (ftp) - ftp is not included in lsof
VAR_REFERENCE_time=$((`date +"%s"`-1))
VAR_REFERENCE_file=".$$_${VAR_REFERENCE_time}.reference"
touch -d @${VAR_REFERENCE_time} ${VAR_DIR_input}${VAR_REFERENCE_file} || ( echo "FAILED: touch -d @${VAR_REFERENCE_time} ${VAR_DIR_input}${VAR_REFERENCE_file}"; exit 3; )
# finds files in inbox for specified suffix, changed after this run, sorted by epoch timestamp in filename (if available)
ARR_FILES_input=(`find ${VAR_DIR_input} -maxdepth 1 -type f -name "*${VAR_FILESUF_input}" ! -cnewer ${VAR_DIR_input}${VAR_REFERENCE_file}`)
rm ${VAR_DIR_input}${VAR_REFERENCE_file}
# get number of files in watch dir and calc how many to ungzip from input dir
VAR_NUMBER_watch=`find ${VAR_DIR_watch} -maxdepth 1 -type f -name "*${VAR_FILESUF_watch}" | wc -l`
VAR_NUMBER_toprocess=$((VAR_NUMBER_limit-VAR_NUMBER_watch))
if (( ${#ARR_FILES_input[@]} < ${VAR_NUMBER_toprocess} ))
then
  VAR_NUMBER_toprocess=${#ARR_FILES_input[@]}
fi
# ungzip of every packages
if (( $VAR_NUMBER_toprocess >= 0 ))
then
  for (( j=0; j!=MAX_JOBS; j++ ))
  do
    THREADS_PID[j]=0
  done
  i=0
  JOBS_REMAINING=${VAR_NUMBER_toprocess}
  while (( ${JOBS_REMAINING} > 0 ))
  do
    for (( j=0; j!=MAX_JOBS; j++ ))
    do
      if (( ( ${THREADS_PID[j]} == 0 ) && (${i} < ${VAR_NUMBER_toprocess}) ))
      then
        processfile ${j} ${ARR_FILES_input[i]} &
        THREADS_PID[j]=$!
        THREADS_NAME[j]=${i}
        THREADS_START[j]=$(date +"%s")
        echo "[${j}] ... job ${i} STARTED processid $!"
        i=$((i+1))
      else
        if (( THREADS_PID[j] > 0 ))
        then
          if kill -0 ${THREADS_PID[j]} 2>/dev/null #kill -0 returns true if process still running
          then
            CURRENT_TIME=$(date +"%s")
            if (( (${CURRENT_TIME}-${THREADS_START[j]}) > ${MAX_JOB_SEC} )) #check time how long process is running
            then
              echo "[${j}] job ${THREADS_NAME[j]} is running too long - KILLING ${THREADS_PID[j]}"
              kill ${THREADS_PID[j]}
              notifykillmail ${THREADS_PID[j]} ${THREADS_NAME[j]} ${THREADS_START[j]} ${ARR_FILES_input[${THREADS_NAME[j]}]}
            fi
          else
            #if wait ${THREADS_PID[j]} #wait returns true if process ended successfully (0)
            #then
            #  echo "[${j}] job ${THREADS_NAME[j]} finished with SUCCESS status"
            #else
            #  echo "[${j}] job ${THREADS_NAME[j]} finished with FAIL status"
            #fi
            JOBS_REMAINING=$((JOBS_REMAINING-1))
            THREADS_PID[j]=0
            CURRENT_TIME=$(date +"%s")
            echo "[${j}] job ${THREADS_NAME[j]} completed in $((CURRENT_TIME-THREADS_START[j])) seconds"
          fi
        fi
      fi
    done
    sleep 1 #optional/recommended to lower cpu usage
  done
else
  echo "WARNING: more files in watch dir ($VAR_NUMBER_watch) than limit ($VAR_NUMBER_limit)"
fi

exit 0
