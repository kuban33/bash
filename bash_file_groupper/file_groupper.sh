#!/bin/bash
## =================================================================================================================
##                                 ____   _____   _   _   _____   ____    ___    ____ 
##                                / ___| | ____| | \ | | | ____| |  _ \  |_ _|  / ___|
##                               | |  _  |  _|   |  \| | |  _|   | |_) |  | |  | |    
##                               | |_| | | |___  | |\  | | |___  |  _ <   | |  | |___ 
##                                \____| |_____| |_| \_| |_____| |_| \_\ |___|  \____|
##                                                                                    
## =================================================================================================================
# file groupper
# ==================================================================================================================
# 1.4 - 2018-09-18 SARA
# - bug repaired with header number
# 1.3 - 2018-09-10 SARA
# - array of processed files sorted by filename
# 1.2 - 2018-09-04 SARA
# - log to parent DpLoad if exists returned
# - even more generic inputs changed to inputdir zipsuffix [outputdir [kodir [okdir]]]
# 1.1 - 2018-08-29 SARA
# - generic purpose file groupper
# - refactored, changed wtf namings to generic e.g Processed to ok, NotProcessed to ko, etc.
# 1.0 - 2018-07-25 SARA
# - generic file groupper (improves performance e.g. for LEH, WIP data loading)
# ------------------------------------------------------------------------------------------------------------------
# config
#get log file from grandmother process which should be DpLoad
CFG_LOG=$(ps -o cmd= -p $(ps -o ppid= -p $$) | awk -F'-log ' '/-log / { print($NF); }' | awk '{ print($1); }')
#commands
CMD_01_dos2unix="dos2unix -q"

# ------------------------------------------------------------------------------------------------------------------
# trap function to handle SIGINT SIGTERM signals + clean up
function trap_finish {
  echo ">>>>>>> $0 terminating $$ <<<<<<<"
  if [[ ( -n "${VAR_DIR_input}${VAR_REFERENCE_file}" ) && ( -f "${VAR_DIR_input}${VAR_REFERENCE_file}" ) ]]
  then rm "${VAR_DIR_input}${VAR_REFERENCE_file}"
  fi
  if [[ ( -n "${VAR_FILE_work_in}" ) && ( -f "${VAR_FILE_work_in}" ) ]]
  then mv "${VAR_FILE_work_in}" "${VAR_DIR_input}${VAR_FILE_base}"
  fi
  if [[ ( -n "${VAR_DIR_work}" ) && ( -d "${VAR_DIR_work}" ) ]]
  then rm -r "${VAR_DIR_work}"
  fi
  wait
  exit 255
}
trap trap_finish SIGINT SIGTERM

# ------------------------------------------------------------------------------------------------------------------
# Check args[]
if (( ( $# < 3 ) || ( $# > 6 ) ))
then
  echo "$0: What's up man!"
  echo "USAGE: $0 inputdir filesuffix nheader [outputdir [kodir [okdir]]]"
  echo "PARAMETERS:"
  echo "  inputdir = path to input dir containing files"
  echo "  filesuffix = expected file suffix for which will be searched"
  echo "  nheader = number of header lines in files, header lines will be kept only once in grouped file"
  echo "  outputdir = [optional] if specified grouped output files moved here, otherwise moved to inputdir"
  echo "  kodir = [optional] if specified unsuccessful innput files moved here, otherwise kept in inputdir"
  echo "  okdir = [optional] if specified successful innput files moved here, otherwise deleted"
  echo ""
  echo "EXAMPLES:"
  echo "  $0 in/ .txt 0"
  echo "  $0 in/ .txt 0 out/"
  echo "  $0 in/ .txt 0 out/ ko/"
  echo "  $0 in/ .txt 0 out/ ko/ ok/"
  exit 1
# save paths from args[]
else
  if (( $# >= 3 ))
  then
    VAR_DIR_input="$1"
    VAR_DIR_output="$1"
    VAR_FILE_SUFFIX_input="$2"
    VAR_NHEADER="$3"
  fi
  if (( $# >= 4 ))
  then
    VAR_DIR_output="$4"
  fi
  if (( $# >= 5 ))
  then
    VAR_DIR_ko="$5"
  fi
  if (( $# == 6 ))
  then
    VAR_DIR_ok="$6"
  fi
fi
# redirect all 1 output to log file if CFG_LOG is nonzero length
if [[ -n "${CFG_LOG}" ]]
then
  exec 3<&1
  exec >> "${CFG_LOG}" 2>&1
fi
# Check folders
# full dir path and correct ending /
if [[ ( -d "${VAR_DIR_input}" ) && ( -d "${VAR_DIR_output}" ) ]]
then
  VAR_DIR_input=`( cd "${VAR_DIR_input}"; pwd; ) | sed '/[^\/]$/s/$/\//'`
  VAR_DIR_output=`( cd "${VAR_DIR_output}"; pwd; ) | sed '/[^\/]$/s/$/\//'`
else
  echo "Check passed dirs, some not exists:"
  echo "Input dir: ${VAR_DIR_input}"
  echo "Output dir: ${VAR_DIR_output}"
  exit 2
fi
if [[ -n "${VAR_DIR_ko}" ]]
then
  if [[ -d "${VAR_DIR_ko}" ]]
  then
    VAR_DIR_ko=`( cd "${VAR_DIR_ko}"; pwd; ) | sed '/[^\/]$/s/$/\//'`
  else
    echo "Check passed dirs, some not exists:"
    echo "KO dir: ${VAR_DIR_ko}"
    exit 2
  fi
fi
if [[ -n "${VAR_DIR_ok}" ]]
then
  if [[ -d "${VAR_DIR_ok}" ]]
  then
    VAR_DIR_ok=`( cd "${VAR_DIR_ok}"; pwd; ) | sed '/[^\/]$/s/$/\//'`
  else
    echo "Check passed dirs, some not exists:"
    echo "KO dir: ${VAR_DIR_ok}"
    exit 2
  fi
fi
#Check header number
if [[ ! "${VAR_NHEADER}" =~ "^[0-9]+$" ]]
then
  echo "Check nheader argument, must be non negative number:"
  echo "nheader: ${VAR_NHEADER}"
  exit 8;
fi
# ------------------------------------------------------------------------------------------------------------------
# reference file for comparison not to include files under write progress (ftp) - ftp is not included in lsof
VAR_REFERENCE_time=$((`date +"%s"`-1))
VAR_REFERENCE_file=".$$_${VAR_REFERENCE_time}.reference"
touch -d @${VAR_REFERENCE_time} "${VAR_DIR_input}${VAR_REFERENCE_file}" || \
  ( echo "FAILED: touch -d @${VAR_REFERENCE_time} ${VAR_DIR_input}${VAR_REFERENCE_file}"; exit 5; )
# finds files in inbox for specified suffix, changed after this run, special characters handled
ARR_FILES_input=()
while IFS=  read -r -d $'\0'
do
  ARR_FILES_input+=("$REPLY")
done < <(find "${VAR_DIR_input}" -maxdepth 1 -type f -regex "^.+\/.+${VAR_FILE_SUFFIX_input//./\\.}$" \
  ! -cnewer "${VAR_DIR_input}${VAR_REFERENCE_file}" -print0 | sort -z)
rm "${VAR_DIR_input}${VAR_REFERENCE_file}"

#greater than one because otherwise no reason for grouping
if (( ${#ARR_FILES_input[@]} > 1 ))
then
  VAR_DIR_work="${VAR_DIR_input}.$(basename $0)_$$/"
  mkdir "${VAR_DIR_work}" || ( echo "  Error not able to create working dir ${VAR_DIR_work})"; exit 6; )
else
  exit 0
fi
# grouped filename + add header to it
VAR_FILE_groupped="${VAR_DIR_work}$(basename ${ARR_FILES_input[0]%${VAR_FILE_SUFFIX_input}})"
VAR_FILE_groupped="${VAR_FILE_groupped}_$(basename ${ARR_FILES_input[${#ARR_FILES_input[@]}-1]})"
touch "${VAR_FILE_groupped}" || ( echo "FAILED: touch ${VAR_FILE_groupped}"; exit 7; )
for (( i=0; i!=${#ARR_FILES_input[@]}; i++ ))
do
  VAR_FILE_base=$(basename "${ARR_FILES_input[$i]}")
  VAR_FILE_work_in="${VAR_DIR_work}${VAR_FILE_base}.in"
  VAR_FILE_work="${VAR_DIR_work}${VAR_FILE_base}"
  mv "${ARR_FILES_input[$i]}" "${VAR_FILE_work_in}"
  cp -p "${VAR_FILE_work_in}" "${VAR_FILE_work}"

  # --- COMMAND 01 ---
  ${CMD_01_dos2unix} "${VAR_FILE_work}"

  if (( i == 0 ))
  then
    if (( ${VAR_NHEADER} > 0 ))
    then
      sed -n '1,'${VAR_NHEADER}'p' "${VAR_FILE_work}" > "${VAR_FILE_groupped}"
    else
      > "${VAR_FILE_groupped}"
    fi
  fi
  echo " ... grouping: ${VAR_FILE_work} >> ${VAR_FILE_groupped}"
  if (( ${VAR_NHEADER} > 0 ))
  then
    sed -n ''$((${VAR_NHEADER}+1))',$p' "${VAR_FILE_work}" >> "${VAR_FILE_groupped}"
  else
    cat "${VAR_FILE_work}" >> "${VAR_FILE_groupped}"
  fi
  rm "${VAR_FILE_work}"
  if [[ -n "${VAR_DIR_ok}" ]]
  then
    mv -v "${VAR_FILE_work_in}" "${VAR_DIR_ok}${VAR_FILE_base}"
  else
    rm -v "${VAR_FILE_work_in}"
  fi
  unset VAR_FILE_work VAR_FILE_work_in VAR_FILE_base
done
mv -v "${VAR_FILE_groupped}" "${VAR_DIR_output}"
rmdir "${VAR_DIR_work}"

exit 0