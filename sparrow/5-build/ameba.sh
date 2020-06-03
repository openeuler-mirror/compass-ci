#! /bin/bash
#Usage: sh script_name.sh ameba_store_dir
#use ameba,exec "ameba code_dir" in cmd line.
ameba_dir=$1
#check if dir exists
check_dir() {
if [ -d $1 ]
then
  echo ""
else
  mkdir -p $1
fi
}
#Clond and build ameba
clone_build_ameba() {
  git clone https://github.com/crystal-ameba/ameba $1/ameba > /dev/null
  if [ $? -eq 0 ]
  then
    cd $1/ameba; crystal src/cli.cr -o bin/ameba
  fi
}
check_dir $ameba_dir
clone_build_ameba $ameba_dir
#creat lias file into the PATH dir
ln -s $1/ameba/bin/ameba ~/bin/ameba
