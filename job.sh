cd ${WORKSPACE}

if [ ! -d jenkins ]
then
  git clone http://github.com/cvpcs/android_jenkins.git -b sts-ics jenkins
fi

cd jenkins
git reset --hard
git pull -s resolve

exec ./build.sh
