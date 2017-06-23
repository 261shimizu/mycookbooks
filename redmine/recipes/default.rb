#
# Cookbook:: chef_repo
# Recipe:: default
#
# Copyright:: 2017, The Authors, All Rights Reserved.


%w{openssl-devel readline-devel zlib-devel curl-devel libyaml-devel libffi-devel postgresql-server postgresql-devel httpd httpd-devel ImageMagick ImageMagick-devel ipa-pgothic-fonts}.each do |pkg|
  package pkg do
    action :install
  end
end

bash "download ruby" do
  user  "vagrant"
  code <<-EOH
    cd /home/vagrant
    curl -O https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.3.tar.gz
  EOH
  not_if { File.exists?("/home/vagrant/ruby-2.3.3.tar.gz") }
end

bash "expand ruby" do
  code <<-EOH
    cd /home/vagrant
    tar xvf ruby-2.3.3.tar.gz
    cd ruby-2.3.3
    ./configure --disable-install-doc
    make
    make install
  EOH
  not_if { File.exists?("/home/vagrant/ruby-2.3.3") }
end

bash "install bundler" do
  user  "vagrant"
  code <<-EOH
    cd /home/vagrant
    sudo /usr/local/bin/gem install bundler --no-rdoc --no-ri
  EOH
end

execute "postgresql-setup" do
  command "postgresql-setup initdb"
  not_if { File.exists?("/var/lib/pgsql/data/pg_hba.conf") }
end

bash "/var/lib/pgsql/data/pg_hba.conf" do
  have_done = <<-EOH
    cat /var/lib/pgsql/data/pg_hba.conf | grep -c redmine
  EOH

  code <<-EOH
    sed -i -e '/configuration parameter/a\host    redmine   redmine   127.0.0.1/32  md5' /var/lib/pgsql/data/pg_hba.conf
    sed -i -e '/redmine/a\host    redmine   redmine   ::1/128   md5' /var/lib/pgsql/data/pg_hba.conf
  EOH
  not_if have_done
end

service "postgresql" do
  action [ :enable, :start ]
end

bash "postgre user create" do
  exists_user = <<-EOH
    cd /var/lib/pgsql
    sudo -u postgres psql -c "SELECT * FROM pg_user WHERE usename='redmine'" | grep -c 'redmine'
  EOH

  code <<-EOH
    cd /var/lib/pgsql
    sudo -u postgres psql -c "CREATE ROLE redmine WITH LOGIN PASSWORD 'redmine';"
  EOH
  not_if exists_user
end

bash "postgre database create" do
  exists_database = <<-EOH
    cd /var/lib/pgsql
    sudo -u postgres psql -c "SELECT * FROM pg_database;" | grep -c redmine
  EOH

  code <<-EOH
    cd /var/lib/pgsql
    sudo -u postgres psql -c "CREATE DATABASE redmine ENCODING 'UTF8' LC_CTYPE 'ja_JP.UTF-8' LC_COLLATE 'ja_JP.UTF-8' OWNER redmine TEMPLATE template0;"
  EOH
  not_if exists_database
end

execute "download redmine" do
  command "svn co http://svn.redmine.org/redmine/branches/3.3-stable /var/lib/redmine"
  not_if { File.exists?("/var/lib/redmine") }
end

bash "create database.yml" do
  code <<-EOH
    cd /var/lib/redmine
    touch /var/lib/redmine/config/database.yml
    echo "production:" >> /var/lib/redmine/config/database.yml
    echo "  adapter: postgresql" >> /var/lib/redmine/config/database.yml
    echo "  database: redmine" >> /var/lib/redmine/config/database.yml
    echo "  host: localhost" >> /var/lib/redmine/config/database.yml
    echo "  username: redmine" >> /var/lib/redmine/config/database.yml
    echo '  password: "redmine"' >> /var/lib/redmine/config/database.yml
    echo "  encoding: utf8" >> /var/lib/redmine/config/database.yml
  EOH
  not_if { File.exists?("/var/lib/redmine/config/database.yml") }
end

bash "bundle install" do
  user  "vagrant"
  code <<-EOH
    cd /var/lib/redmine
    sudo /usr/local/bin/bundle install --without development test --path vendor/bundle
  EOH
end

bash "redmine setup" do
  user  "vagrant"
  code <<-EOH
    cd /var/lib/redmine
    sudo /usr/local/bin/bundle exec rake generate_secret_token
    sudo RAILS_ENV=production /usr/local/bin/bundle exec rake db:migrate
    sudo RAILS_ENV=production REDMINE_LANG=ja /usr/local/bin/bundle exec rake redmine:load_default_data
  EOH
end

bash "apache passenger setup" do
  code <<-EOH
    /usr/local/bin/gem install passenger --no-rdoc --no-ri
    passenger-install-apache2-module --auto --languages ruby
    touch /etc/httpd/conf.d/redmine.conf
    echo '<Directory "/var/lib/redmine/public">' >> /etc/httpd/conf.d/redmine.conf
    echo "  Require all granted" >> /etc/httpd/conf.d/redmine.conf
    echo "</Directory>" >> /etc/httpd/conf.d/redmine.conf
    passenger-install-apache2-module --snippet >> /etc/httpd/conf.d/redmine.conf
  EOH
  not_if { File.exists?("/etc/httpd/conf.d/redmine.conf") }
end

bash "change mode /var/lib/redmine" do
  code <<-EOH
    chown -R apache:apache /var/lib/redmine
  EOH
end

bash "change httpd.conf" do
  have_done = <<-EOH
    cat /etc/httpd/conf/httpd.conf | grep -c redmine
  EOH

  code <<-EOH
    sed -i -e 's:DocumentRoot "/var/www/html":DocumentRoot "/var/lib/redmine/public":g' /etc/httpd/conf/httpd.conf
  EOH
  not_if have_done
end

service "httpd" do
  action [ :enable, :start]
end
