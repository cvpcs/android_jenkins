#!/usr/bin/env bash

function check_result {
  if [ "0" -ne "$?" ] ; then
    echo $1
    exit 1
  fi
}

function set_node_env {
  if [ ! -z "$(eval echo \$\{android_sts_ics_${1}\})" ] ; then
    eval export ${1}=\$\{android_sts_ics_${1}\}
  fi
}

##### VARIABLE CHECKS #####

# The following variables are used throughout the script:
#
# WORKSPACE - base directory that all work is performed in [requisitely set by jenkins]
# LUNCH - lunch combo to build [requisitely set by jenkins]
# CLEAN_TYPE - how to clean before build (default: clobber) [optionally set by nodes]
# CCACHE_DIR - directory to store CCACHE data (default: disable CCACHE) [optionally set by nodes]
# BOOTSTRAP - directory to use to bootstrap .repo (default: don't bootstrap) [optionally set by user]
# 

if [ -z "${WORKSPACE}" ] ; then
  echo WORKSPACE not specified
  exit 1
fi

if [ -z "${LUNCH}" ] ; then
  echo LUNCH not specified
  exit 1
else
  echo Using LUNCH = \"${LUNCH}\"
fi

set_node_env CLEAN_TYPE
if [ -z "${CLEAN_TYPE}" ] ; then
  echo CLEAN_TYPE not specified. Defaulting to \"installclean\"
  export CLEAN_TYPE="installclean"
else
  echo Using CLEAN_TYPE = \"${CLEAN_TYPE}\"
fi

set_node_env CCACHE_DIR
if [ ! -z "${CCACHE_DIR}" ] ; then
  echo Using CCACHE_DIR = \"${CCACHE_DIR}\"
  export USE_CCACHE=1
else
  echo CCACHE_DIR not specified. Disabling CCACHE
fi

##### ENVIRONMENT SETUP #####

# get into the workspace
cd ${WORKSPACE}

# override these since we need them below
export JENKINS_DIR=${WORKSPACE}/jenkins
export ANDROID_DIR=${WORKSPACE}/android
export BIN_DIR=${WORKSPACE}/bin
export ARCHIVE_DIR=${WORKSPACE}/archive

# colorization fix in Jenkins
export CL_PFX="\"\033[34m\""
export CL_INS="\"\033[32m\""
export CL_RST="\"\033[0m\""

# clean out archive
rm -rf ${ARCHIVE_DIR}
mkdir -p ${ARCHIVE_DIR}

# wipe out build number
export BUILD_NO=${BUILD_NUMBER}
unset BUILD_NUMBER

# modify our path
export PATH="${BIN_DIR}:${PATH}:/opt/local/bin/:${WORKSPACE}/android/prebuilt/$(uname|awk '{print tolower($0)}')-x86/ccache"

# don't build with colors
export BUILD_WITH_COLORS=0

# find REPO
REPO=$(which repo)
if [ -z "${REPO}" ] ; then
  mkdir -p ${BIN_DIR}
  curl https://dl-ssl.google.com/dl/googlesource/git-repo/repo > ${BIN_DIR}/repo
  chmod a+x ${BIN_DIR}/repo
fi

# set our git configuration names
git config --global user.name $(whoami)@${NODE_NAME}
git config --global user.email jenkins@cvpcs.org

##### REPO INIT #####

# make sure we have our android directory
mkdir -p ${ANDROID_DIR}

# bootstrap if we are told to
if [ ! -z "${BOOTSTRAP}" -a -d "${BOOTSTRAP}" ] ; then
  echo Bootstrapping repo with: ${BOOTSTRAP}
  cp -R ${BOOTSTRAP}/.repo android
fi

# from this point on we sit in ${ANDROID_DIR}
cd ${ANDROID_DIR}

# repo init
repo init -u http://github.com/CyanogenMod/android.git -b ics

# copy local_manifest from jenkins
if [ -f ${JENKINS_DIR}/local_manifest.xml ] ; then
  cp ${JENKINS_DIR}/local_manifest.xml .repo/local_manifest.xml
fi

##### REPO SYNC #####

# sync
echo Syncing...
repo sync -d > /dev/null 2> /dev/null
check_result repo sync failed.
echo Sync complete.

# run setup
if [ -f ${JENKINS_DIR}/setup.sh ] ; then
  ${JENKINS_DIR}/setup.sh
fi

##### BUILD #####

# environment setup
. build/envsetup.sh

# perform lunch
lunch ${LUNCH}
check_result lunch failed.

# remove any existing update zips
rm -f ${OUT}/update*.zip*

# pre-build clean
make ${CLEAN_TYPE}

# build
mka bacon recoveryzip recoveryimage
check_result Build failed.

##### ARCHIVE #####

# copy our output artifacts
cp ${OUT}/*-CM9-*-UNOFFICIAL.zip* ${ARCHIVE_DIR}
if [ -f ${OUT}/utilties/update.zip ] ; then
  cp ${OUT}/utilties/update.zip ${ARCHIVE_DIR}/recovery.zip
fi
if [ -f ${OUT}/recovery.img ] ; then
  cp ${OUT}/recovery.img ${ARCHIVE_DIR}
fi

# archive the build.prop as well
unzip -c $(ls ${ARCHIVE_DIR}/*-CM9-*-UNOFFICIAL.zip) system/build.prop > ${ARCHIVE_DIR}/build.prop

# chmod the files in case UMASK blocks permissions
chmod -R ugo+r ${ARCHIVE_DIR}
