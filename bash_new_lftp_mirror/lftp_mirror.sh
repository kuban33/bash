#!/bin/bash
## =================================================================================================================
## =================================================================================================================
# MIRROR WTF Data FTP (SARA)
# 2019-03-21 SARA
# - RANDOM used in ltfp file
# 2019-03-05 SARA
# 2018-10-23 SARA
# - choosable dirs to mirror
# 2018-08-07 SARA
# - revised
# 2018-06-13 SARA
# - general revision
# - changed to lftp
# - now supports submission of different files with same filename (date+size comparison)
# 2015-06-09 SARA
# - just for devl purposes, script in construction
# ==================================================================================================================
# config
LD_LIBRARY_PATH=""
CFG_FTP_HOST="host.com"
CFG_FTP_USER="user"
CFG_FTP_PASS="pass"
CFG_FTP_DIR="/data/"
CFG_LOCAL_DIR="${SOURCEDATAHOME}/data/"

#-------------------------------------------------------------------------------------------------------------------
# trap function to handle SIGINT SIGTERM signals + clean up
function trap_finish { echo ">>>>>>> terminating $$ <<<<<<<"; \
                       wait; exit 255; \
                     }
trap trap_finish SIGINT SIGTERM
#-------------------------------------------------------------------------------------------------------------------

# Check folders
if [[ ! -d "${CFG_LOCAL_DIR}" ]]
then
  echo "Check passed dirs, some not exists:"
  echo "Local dir: ${CFG_LOCAL_DIR}"
  exit 1
fi

echo "WTF MIRROR DISTRIBUTION          Date: `date +"%Y%m%d%H%M%S"`"
echo " ..... mirroring WTF data"
VAR_FILE_lftpout="./.$(basename $0)_$$_${RANDOM}_lftp.out"
touch "${VAR_FILE_lftpout}" || ( echo "  Error not able to touch working file ${VAR_FILE_lftpout})"; exit 1; )
test -r "${VAR_FILE_lftpout}" -a -w "${VAR_FILE_lftpout}" || ( echo "  Error not able to read/write working file ${VAR_FILE_lftpout})"; exit 1; )
(
lftp "${CFG_FTP_USER}:${CFG_FTP_PASS}@${CFG_FTP_HOST}" <<EOF
cd ${CFG_FTP_DIR};
echo " ... mirroring DIR = wtf_data1/";
mirror -v -x '^.*\/\.[^\/]*$' --parallel=10 ./wtf_data1 ${CFG_LOCAL_DIR};
echo " ... mirroring DIR = wtf_data2/";
mirror -v -x '^.*\/\.[^\/]*$' --parallel=10 ./wtf_data2 ${CFG_LOCAL_DIR};
exit;
EOF
) | tee -a "${VAR_FILE_lftpout}"

echo " ..... distributing WTF data"
# need to handle special characters inside filename
# regexp hardcoded for lftp output
ARR_FILES_input=()
while IFS=  read -r -d $'\0'
do
  ARR_FILES_input+=("$REPLY")
done < <(awk '/^ ... mirroring DIR = / { DIR=substr($0,22); } /^Transferring file `.*\047$/ { FILE=substr($0,20,length($0)-20); printf("%s%s\0",DIR,FILE) }' "${VAR_FILE_lftpout}")

for (( i=0; i!=${#ARR_FILES_input[@]}; i++ ))
do
  #rules to distribute files
  if   [[ "${ARR_FILES_input[i]}" =~ "^wtf_data1\/" ]]; then
    cp -pv "${CFG_LOCAL_DIR}${ARR_FILES_input[i]}" "${DP_DPD}/data1/inbox/"
  elif [[ "${ARR_FILES_input[i]}" =~ "^wtf_data2\/" ]]; then
    cp -pv "${CFG_LOCAL_DIR}${ARR_FILES_input[i]}" "${DP_DPD}/data2/inbox/"
  fi
done

rm "${VAR_FILE_lftpout}"

echo "WTF MIRROR DISTRIBUTION    END   Date: `date +"%Y%m%d%H%M%S"`"

exit 0
