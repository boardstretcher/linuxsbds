#!/bin/bash -x
#
# The linux small business development server installation script
# 
# Using free and opensource software to build a small business server 
# capable of supporting a group of developers in their day to day business. 

# must be run as root
	if [[ $EUID -ne 0 ]]; then
		echo "script must be run as root"
		exit
	fi

# check ubuntu version
	{ lsb_release -a | grep "Ubuntu 12.10"; } || { echo "requires ubuntu 12.10"; exit; }

# check processors
	PROCS=$(grep -c ^processor /proc/cpuinfo)
	if [ $PROCS == "1" ]; then
		echo "This setup requires a minimum of 2 processors"
		exit
	fi
	
# check ram
	RAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
	if [ $RAM -lt 2048000 ]; then
		echo "This setup requires a minimum of 2GB of ram"
		exit
	fi

# check hostname
	if [ $HOSTNAME == "localhost" ]; then
		echo "You must set your hostname to the correct FQDN"
		exit
	fi
# check password env variable
	if [ -z $PASSWORD ]; then
		echo "You must set the PASSWORD variable to something for us to use as a default password"
		exit
	fi

# update ubuntu
	apt-get -y update
	apt-get -y upgrade

# set non-interactive mysql password
	echo "mysql-server mysql-server/root_password password $PASSWORD" | sudo debconf-set-selections
	echo "mysql-server mysql-server/root_password_again password $PASSWORD" | sudo debconf-set-selections

# set non-interactive postfix
	echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections	
	echo "postfix postfix/mailname string $HOSTNAME" | debconf-set-selections

# install needed packages
	apt-get -y install git subversion vim make gcc build-essential zlib1g-dev libyaml-dev \
	libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl git-core \
	openssh-server redis-server checkinstall libxml2-dev libxslt-dev libicu-dev \
	libexpat1-dev gettext libz-dev libssl-dev build-essential python-docutils postfix \
	mysql-server mysql-client libmysqlclient-dev nginx libpq-dev python-software-properties \
	python g++ make imagemagick libcurl4-gnutls-dev empty-expect apache2 apache2-mpm-prefork \
	apache2-utils apache2.2-common libapache2-mod-php5 libapr1 libaprutil1 libdbd-mysql-perl \
	libdbi-perl libnet-daemon-perl libplrpc-perl libpq5 mysql-client-5.5 mysql-common \
	php5-common php5-mysql php5-xcache default-jdk libapache2-mod-passenger 
	# graphicsmagick-libmagick-dev-compat libmagickwand-dev software-properties-common

# node.js repo and installation
	add-apt-repository -y ppa:chris-lea/node.js
	apt-get -y update
  	apt-get -y install nodejs

# stop apache2 if running
	service apache2 stop

# remove old packages
	apt-get remove -y ruby1.8
	
# use vim as default editor
	update-alternatives --set editor /usr/bin/vim.basic
	
# update git
	cd
	git clone https://github.com/git/git.git
	cd git
	make prefix=/usr/local all
	apt-get -y purge git
	sudo make prefix=/usr/local install
	ln -s /usr/local/bin/git /usr/bin/git
	git --version

# install ruby
	mkdir /tmp/ruby && cd /tmp/ruby
	curl --progress ftp://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p247.tar.gz | tar xz
	cd ruby-2.0.0-p247
	./configure
	make
	make install
	gem install bundler --no-ri --no-rdoc

# install gitlab
# username: admin@local.host
# password: 5iveL!fe
# endpoint: http://servername.org:80

	sudo adduser --disabled-login --gecos 'GitLab' git
	cd /home/git
	sudo -u git -H git clone https://github.com/gitlabhq/gitlab-shell.git
	cd /home/git/gitlab-shell
	sudo -u git -H git checkout v1.7.0
	sudo -u git -H cp config.yml.example config.yml
	sed -i "s/localhost/$HOSTNAME/g" config.yml
	sudo -u git -H ./bin/install
	mysql -e "CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$PASSWORD';"
	mysql -e "CREATE DATABASE IF NOT EXISTS gitlabhq_production;"
	mysql -e "GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON gitlabhq_production.* TO 'gitlab'@'localhost';"
	cd /home/git
	sudo -u git -H git clone https://github.com/gitlabhq/gitlabhq.git gitlab
	cd /home/git/gitlab
	sudo -u git -H git checkout 6-0-stable
	sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml
	sed -i "s/localhost/$HOSTNAME/g" config/gitlab.yml
	chown -R git log/
	chown -R git tmp/
	chmod -R u+rwX  log/
	chmod -R u+rwX  tmp/
	sudo -u git -H mkdir /home/git/gitlab-satellites
	sudo -u git -H mkdir tmp/pids/
	sudo -u git -H mkdir tmp/sockets/
	chmod -R u+rwX  tmp/pids/
	chmod -R u+rwX  tmp/sockets/
	sudo -u git -H mkdir public/uploads
	chmod -R u+rwX  public/uploads
	sudo -u git -H cp config/unicorn.rb.example config/unicorn.rb
	sudo -u git cp config/database.yml.mysql config/database.yml
	sed -i "s/root/gitlab/g" config/database.yml
	sed -i "s/\"secure password\"/$PASSWORD/g" config/database.yml
	sudo -u git -H chmod o-rwx config/database.yml
	gem install charlock_holmes --version '0.6.9.4'
	sudo -u git -H bundle install --deployment --without development test postgres aws
	empty -f -i in -o out sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production
   	empty -w -i out -o in "(yes/no)? " "yes\n"
   	cp lib/support/init.d/gitlab /etc/init.d/gitlab
	chmod +x /etc/init.d/gitlab	
	update-rc.d gitlab defaults 21
	gem install pg -v '0.15.1'
	bundle install
	cd /home/git
	sudo -u git -H git config --global user.name "GitLab"
	sudo -u git -H git config --global user.email "gitlab@$HOSTNAME"
	sudo -u git -H git config --global core.autocrlf input
	cd /home/git/gitlab
	sudo -u git -H bundle exec rake gitlab:env:info RAILS_ENV=production
	service gitlab start	
	sudo -u git -H bundle exec rake sidekiq:start RAILS_ENV=production
	sudo -u git -H bundle exec rake gitlab:check RAILS_ENV=production
	
	cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
	ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
	sed -i "s/YOUR_SERVER_FQDN/$HOSTNAME/g" /etc/nginx/sites-available/gitlab
	sed -i "s/#\ server/server/g" /etc/nginx/nginx.conf
	service nginx restart

# apache2 installation
# http://yoursite.com:81
	sed -i "s/80/81/g" /etc/apache2/ports.conf 
	sed -i "s/80/81/g" /etc/apache2/sites-available/default
	service apache2 restart

# mediawiki installation
# http://yoursite.com:81/wiki
	cd /var/www
	curl -O http://dumps.wikimedia.org/mediawiki/1.21/mediawiki-1.21.1.tar.gz
	tar zxvf mediawiki-1.21.1.tar.gz 
	mv mediawiki-1.21.1 wiki
	chown -R www-data.www-data wiki
	rm mediawiki-1.21.1.tar.gz 

# install zerobin pastebin
# http://yoursite.com:81/pastebin
	cd /var/www
	git clone https://github.com/sebsauvage/ZeroBin.git
	mv ZeroBin pastebin
	chown -R www-data.www-data pastebin

# install gerrit code review
# http://yoursite.com:8081
	cd /opt
	wget https://gerrit.googlecode.com/files/gerrit-2.7-rc1.war
	java -jar gerrit-2.7-rc1.war init --batch -d ~/gerrit
	cd ~
	sed -i "s/8080/8081/g" /root/gerrit/etc/gerrit.config 
	/root/gerrit/bin/gerrit.sh restart
	
# mantis installation
# http://yoursite.com:81/mantis
	cd /var/www
	wget http://downloads.sourceforge.net/project/mantisbt/mantis-stable/1.2.15/mantisbt-1.2.15.tar.gz
	tar zxvf mantisbt-1.2.15.tar.gz 
	mv mantisbt-1.2.15 mantis
	chown -R www-data.www-data mantis
	rm mantisbt-1.2.15.tar.gz 

# jenkins installation
# http://yoursite.com:8082
	cd ~
	wget -q -O - http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | sudo apt-key add -
	sh -c 'echo deb http://pkg.jenkins-ci.org/debian binary/ > /etc/apt/sources.list.d/jenkins.list'
	apt-get update
	apt-get install -y jenkins
	sed -i "s/8080/8082/g" /etc/default/jenkins 
	service jenkins restart

# testlink installation
# http://yoursite.com:81/testlink
	cd /var/www
	wget http://downloads.sourceforge.net/project/testlink/TestLink%201.9/TestLink%201.9.7/testlink-1.9.7.tar.gz
	tar zxvf testlink-1.9.7.tar.gz 
	mv testlink-1.9.7 testlink
	chown -R www-data.www-data testlink
	mkdir /var/testlink/logs -p
	mkdir /var/testlink/upload_area -p
	chown -R www-data.www-data /var/testlink

# watir installation
# this is a local installation, see docs for usage
# http://watir.com/documentation/
	cd ~
	gem update --system --no-rdoc --no-ri
	gem install watir --no-rdoc --no-ri

# redmine installation
# 
	cd /opt
	sudo adduser --disabled-login --gecos 'redmine' redmine
	svn co http://svn.redmine.org/redmine/branches/2.3-stable redmine
	mysql -e "CREATE DATABASE redmine CHARACTER SET utf8;"
	mysql -e "CREATE DATABASE redmine_development CHARACTER SET utf8;"
	mysql -e "CREATE DATABASE redmine_test CHARACTER SET utf8;"
	mysql -e "CREATE USER 'redmine'@'localhost' IDENTIFIED BY '$PASSWORD';"
	mysql -e "GRANT ALL PRIVILEGES ON redmine.* TO 'redmine'@'localhost';"
	mysql -e "GRANT ALL PRIVILEGES ON redmine_development.* TO 'redmine'@'localhost';"
	mysql -e "GRANT ALL PRIVILEGES ON redmine_test.* TO 'redmine'@'localhost';"
	cat > /opt/redmine/config/database.yml << EOF
	production:
  	adapter: mysql2
  	database: redmine
  	host: localhost
  	username: redmine
  	password: $PASSWORD
  	encoding: utf8
	
	development:
  	adapter: mysql2
  	database: redmine_development
  	host: localhost
  	username: redmine
  	password: $PASSWORD
  	encoding: utf8
	
	test:
  	adapter: mysql2
  	database: redmine_test
  	host: localhost
  	username: redmine
  	password: $PASSWORD
  	encoding: utf8
EOF
	cd /opt/redmine
  	bundle install --without development test
	rake generate_secret_token
  	RAILS_ENV=production rake db:migrate
	export REDMINE_LANG=en
 	RAILS_ENV=production rake redmine:load_default_data
	mkdir -p tmp tmp/pdf public/plugin_assets
  	sudo chown -R redmine:redmine files log tmp public/plugin_assets
  	sudo chmod -R 755 files log tmp public/plugin_assets
  	cd /opt 
	chown -R redmine.redmine redmine/
  	cd /opt/redmine/
  	ruby script/rails server webrick -e production -d

# redis commander
# http://yoursite.com:8084
# redis @ yoursite.com:6379
	cd ~
	npm install -g redis-commander
  	redis-commander -p 8084

# sqlbuddy
# root/$PASSWORD
# http://yoursite.com:81/sqlbuddy
	cd /var/www
	wget https://github.com/calvinlough/sqlbuddy/raw/gh-pages/sqlbuddy.zip
	unzip sqlbuddy.zip 
  	chown -R www-data.www-data sqlbuddy
  	rm sqlbuddy.zip 

# extplorer
# admin/admin
# http://yoursite.com:81/extplorer
	cd /var/www
	 wget http://downloads.sourceforge.net/project/extplorer/extplorer/eXtplorer%202.1.0/eXtplorer_2.1.0RC3.zip
  	mkdir extplorer
  	chown -R www-data.www-data extplorer
  	cd extplorer/
  	unzip ../eXtplorer_2.1.0RC3.zip 
  
# menu
# http://yoursite.com:81/index.html
	cat > /var/www/index.html << EOF
	<a href="http://$HOSTNAME:80">gitlab</a><br/>
	<a href="http://$HOSTNAME:81/wiki">wiki</a><br/>
	<a href="http://$HOSTNAME:81/pastebin">pastebin</a><br/>
	<a href="http://$HOSTNAME:8081">gerrit codereview</a><br/>
	<a href="http://$HOSTNAME:81/mantis">mantis bugtracker</a><br/>
	<a href="http://$HOSTNAME:8082">jenkins</a><br/>
	<a href="http://$HOSTNAME:81/testlink">testlink</a><br/>
	<a href="http://$HOSTNAME:3000">redmine project management</a><br/>
	<a href="http://$HOSTNAME:8084">redis commander</a><br/>
	<a href="http://$HOSTNAME:81/sqlbuddy">sqlbuddy</a><br/>
	<a href="http://$HOSTNAME:81/extplorer">extplorer</a><br/>
EOF
