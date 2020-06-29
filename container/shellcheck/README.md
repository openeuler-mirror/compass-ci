# Run shellcheck in the container.
# Run "shellchell $script" on the host machine to check the syntax in the shell script.
1.If this is the first time, please check whether there is a shellcheck container image.
	docker images |grep shellcheck
  If the image does not exist, run:
   	./build
2.After creating the image ,please run:
	./run $script
	or
	./shellcheck $script

