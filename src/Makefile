scheduler: *.cr */*.cr
	crystal build -o scheduler scheduler.cr
cscope:
	find . -name "*.cr" > cscope.files
	cscope -b -q -k
