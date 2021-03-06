#!/bin/bash
## =================================================================================================================
##                                 ____   _____   _   _   _____   ____    ___    ____ 
##                                / ___| | ____| | \ | | | ____| |  _ \  |_ _|  / ___|
##                               | |  _  |  _|   |  \| | |  _|   | |_) |  | |  | |    
##                               | |_| | | |___  | |\  | | |___  |  _ <   | |  | |___ 
##                                \____| |_____| |_| \_| |_____| |_| \_\ |___|  \____|
##                                                                                    
## =================================================================================================================
# ungpger
# ==================================================================================================================
# 1.2 - 2018-09-03 SARA
# - log to parent DpLoad if exists returned
# - even more generic inputs changed to inputdir gpgsuffix [outputdir [kodir [okdir]]]
# 1.1 - 2018-08-29 SARA
# - generic purpose ungpger
# - refactored, changed wtfPOWER namings to generic e.g Processed to ok, NotProcessed to ko, etc.
# 1.0 - 2018-06-22 SARA
# - decodes gpg files in provided folder, puts the to outdir, optionally keep original files and failed in sep dir
# - decodes to original file names encrypted inside gpg
# ------------------------------------------------------------------------------------------------------------------
# config
CFG_GPG_passphrase='P@ssw0rd'
#get log file from grandmother process which should be DpLoad
CFG_LOG=$(ps -o cmd= -p $(ps -o ppid= -p $$) | awk -F'-log ' '/-log / { print($NF); }' | awk '{ print($1); }')

# ------------------------------------------------------------------------------------------------------------------
# trap function to handle SIGINT SIGTERM signals + clean up
function trap_finish {
  echo ">>>>>>> $0 terminating $$ <<<<<<<"
  if [[ ( -n "${VAR_DIR_input}${VAR_REFERENCE_file}" ) && ( -f "${VAR_DIR_input}${VAR_REFERENCE_file}" ) ]]
  then rm "${VAR_DIR_input}${VAR_REFERENCE_file}"
  fi
  if [[ ( -n "${VAR_FILE_work_in}" ) && ( -f "${VAR_FILE_work_in}" ) ]]
  then mv "${VAR_FILE_work_in}" "${VAR_DIR_input}"
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
if (( ( $# < 2 ) || ( $# > 5 ) ))
then
  echo "$0: What's up man!"
  echo "USAGE: $0 inputdir gpgsuffix [outputdir [kodir [okdir]]]"
  echo "PARAMETERS:"
  echo "  inputdir = path to input dir containing gpg files"
  echo "  gpgsuffix = expected gpg file suffix for which will be searched"
  echo "  outputdir = [optional] if specified decrypted output files moved here, otherwise moved to inputdir"
  echo "  kodir = [optional] if specified unsuccessful innput files moved here, otherwise kept in inputdir"
  echo "  okdir = [optional] if specified successful innput files moved here, otherwise deleted"
  echo ""
  echo "EXAMPLES:"
  echo "  $0 in/ .gpg"
  echo "  $0 in/ .gpg out/"
  echo "  $0 in/ .gpg out/ ko/"
  echo "  $0 in/ .gpg out/ ko/ ok/"
  exit 1
# save paths from args[]
else
  if (( $# >= 2 ))
  then
    VAR_DIR_input="$1"
    VAR_DIR_output="$1"
    VAR_FILE_SUFFIX_input="$2"
  fi
  if (( $# >= 3 ))
  then
    VAR_DIR_output="$3"
  fi
  if (( $# >= 4 ))
  then
    VAR_DIR_ko="$4"
  fi
  if (( $# == 5 ))
  then
    VAR_DIR_ok="$5"
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
  VAR_FILE_work_in="${VAR_DIR_work}${VAR_FILE_base}"
  mv "${ARR_FILES_input[$i]}" "${VAR_FILE_work_in}"
  # gpg decode
  echo " ... GPG decoding file: ${VAR_FILE_work_in}"
  ( cd "${VAR_DIR_work}" && \
    gpg -v --batch --use-embedded-filename --passphrase "${CFG_GPG_passphrase}" "${VAR_FILE_work_in}"; ) 
  if (( $? == 0 ))
  then
    if [[ -n "${VAR_DIR_ok}" ]]
    then
      mv -v "${VAR_FILE_work_in}" "${VAR_DIR_ok}"
    else
      rm -v "${VAR_FILE_work_in}"
    fi
    find "${VAR_DIR_work}" -type f -print0 | xargs -0 -I{} mv -v {} "${VAR_DIR_output}"
  else
    if [[ -n "${VAR_DIR_ko}" ]]
    then
      mv -v "${VAR_FILE_work_in}" "${VAR_DIR_ko}"
    else
      mv -v "${VAR_FILE_work_in}" "${ARR_FILES_input[$i]}"
    fi
  fi
  unset VAR_FILE_base VAR_FILE_work_in 
done
rm -r "${VAR_DIR_work}"

exit 0