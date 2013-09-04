linuxsbds
=========

###description

_The linux "small-business developers server" installation script_

Using free and opensource software to build a small business server capable
of supporting a group of developers in their day to day business. 

###quick install
* export PASSWORD=mypassword
* export HOSTNAME=dev.mysite.com
* date # begin
* curl -s https://raw.github.com/boardstretcher/linuxsbds/master/linux_sbds_installer.sh | bash -x &> /tmp/output.log
* date # end


###requirements 
_(based on small business of less than 10 developers)_
* ubuntu 12.10
* 2 cores
* 4 Gb ram
* 40 Gb hdd (more needed depending on codebase size)

###provides
* git repo
* gitlab frontend
* mediawiki
* pastebin: zerobin
* gerrit code review
* mantis bug tracker/bugzilla?
* jenkins build server
* testlink test management
* watir test suite
* redmine project management
* redis keystore / redis commander
* sqlbuddy sql frontend
* mysql / php / apache / nginx
* extplorer
* rsync backups
