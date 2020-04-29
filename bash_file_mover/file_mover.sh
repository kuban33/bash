#!/bin/bash
## =================================================================================================================
## =================================================================================================================
# file mover
# ==================================================================================================================
# 1.0 - 2019-03-03 SARA
# - including dos2unix command
# ------------------------------------------------------------------------------------------------------------------
# config
#get log file from grandmother process which should be DpLoad
CFG_LOG=$(ps -o cmd= -p $(ps -o ppid= -p $$) | awk -F'-log ' '/-log / { print($NF); }' | awk '{ print($1); }')
#commands
CMD_01_dos2unix="dos2unix"

# ------------------------------------------------------------------------------------------------------------------
# trap function to handle SIGINT SIGTERM signals + clean up
function trap_finish {
  echo ">>>>>>> $0 terminating $$ <<<<<<<"
  if [[ -f "${VAR_DIR_input}${VAR_REFERENCE_file}" ]]
  then rm "${VAR_DIR_input}${VAR_REFERENCE_file}"
  fi
  if [[ ( -d "${VAR_DIR_input}" ) && ( -f "${VAR_FILE_work_in}" ) ]]
  then mv "${VAR_FILE_work_in}" "${VAR_DIR_input}${VAR_FILE_base}"
  fi
  if [[ -d "${VAR_DIR_work}" ]]
  then rm -r "${VAR_DIR_work}"
  fi
  wait
  exit 255
}
trap trap_finish SIGINT SIGTERM

# ------------------------------------------------------------------------------------------------------------------
# Check args[]
if [[ $# -ne 3 ]]
then
  echo "$0: What's up man!"
  echo "USAGE: $0 inputdir outputdir regex"
  echo "PARAMETERS:"
  echo "  inputdir = path to input dir containing input files"
  echo "             keeps original files in inputdir/Processed inputdir/NotProcessed folders (created if needed)"
  echo "  outputdir = path to output dir where processed files will be moved"
  echo "  regex = regular expression of filepath which will be searched for"
  echo ""
  echo "EXAMPLE: $0 inbox/ outbox/ '^.+\/.+\.file$'"
  exit 1
# save paths from args[]
else
  VAR_DIR_input="$1"
  VAR_DIR_output="$2"
  VAR_REGEX="$3"
fi

# redirect all 1 output to log file if CFG_LOG is nonzero length
if [[ -n "${CFG_LOG}" ]]
then
  exec 3<&1
  exec >> "${CFG_LOG}" 2>&1
fi

# Check folders
if [[( -d "${VAR_DIR_input}" ) && ( -d "${VAR_DIR_output}" )]]
then
  #sed ensures that directory ends with /
  VAR_DIR_input=`( cd "${VAR_DIR_input}"; pwd; ) | sed '/[^\/]$/s/$/\//'`
  VAR_DIR_output=`( cd "${VAR_DIR_output}"; pwd; ) | sed '/[^\/]$/s/$/\//'`
else
  echo "Check passed dirs, some not exists:"
  echo "Input dir: ${VAR_DIR_input}"
  echo "Output dir: ${VAR_DIR_output}"
  exit 2
fi

VAR_DIR_processed="${VAR_DIR_input}Processed/"
if [[ ! -d "${VAR_DIR_processed}" ]]
then
  mkdir -p "${VAR_DIR_processed}"
fi

# reference file for comparison not to include files under write progress (ftp) - ftp is not included in lsof
VAR_REFERENCE_time=$((`date +"%s"`-1))
VAR_REFERENCE_file=".$$_${VAR_REFERENCE_time}.reference"
touch -d @${VAR_REFERENCE_time} "${VAR_DIR_input}${VAR_REFERENCE_file}" || \
  ( echo "FAILED: touch -d @${VAR_REFERENCE_time} ${VAR_DIR_input}${VAR_REFERENCE_file}"; exit 3; )
# finds files in inbox for specified suffix, changed after this run, special characters handled
ARR_FILES_input=()
while IFS=  read -r -d $'\0'
do
  ARR_FILES_input+=("$REPLY")
done < <(find "${VAR_DIR_input}" -maxdepth 1 -type f -regex "${VAR_REGEX}" \
           ! -cnewer "${VAR_DIR_input}${VAR_REFERENCE_file}" -print0)
rm "${VAR_DIR_input}${VAR_REFERENCE_file}"

if (( ${#ARR_FILES_input[@]} > 0 ))
then
  VAR_DIR_work="${VAR_DIR_input}.$(basename $0)_$$/"
  mkdir "${VAR_DIR_work}" || ( echo "  Error not able to create working dir ${VAR_DIR_work})"; exit 6; )
else
  exit 0
fi
for (( i=0; i!=${#ARR_FILES_input[@]}; i++ ))
do
  VAR_FILE_base=$(basename "${ARR_FILES_input[$i]}")
  VAR_FILE_work_in="${VAR_DIR_work}${VAR_FILE_base}.in"
  VAR_FILE_work="${VAR_DIR_work}${VAR_FILE_base}"
  mv "${ARR_FILES_input[$i]}" "${VAR_FILE_work_in}"
  cp -p "${VAR_FILE_work_in}" "${VAR_FILE_work}"
  
  # --- COMMAND 01 ---
  ${CMD_01_dos2unix} "${VAR_FILE_work}" 
  
  mv -v "${VAR_FILE_work}" "${VAR_DIR_output}"  
  mv -v "${VAR_FILE_work_in}" "${VAR_DIR_processed}${VAR_FILE_base}"
done

rmdir "${VAR_DIR_work}"

exit 0