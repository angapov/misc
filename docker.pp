$pkg = [ 'icinga', 'icinga2', 'icinga-gui', 's3cmd', 'nagios-plugins-all' ]

package { $pkg: 
  ensure  => latest,
  require => [ Yumrepo['icinga'], Yumrepo['epel'] ],
}

yumrepo { 'icinga':
  baseurl => 'http://packages.icinga.org/epel/$releasever/release/',
  gpgkey  => 'http://packages.icinga.org/icinga.key',
}

yumrepo { 'epel':
  baseurl  => 'http://download.fedoraproject.org/pub/epel/7/$basearch',
  gpgcheck => 0,
}

yumrepo { 'docker':
  baseurl => 'https://yum.dockerproject.org/repo/main/centos/7/',
  gpgkey  => 'https://yum.dockerproject.org/gpg',
}
->
package { 'docker-engine':
  ensure          => present,
  install_options => [{ '--enablerepo' => '*' }],
}
->
class { 'docker':
  use_upstream_package_source => false,
  manage_package              => false,
}

service { 'icinga': 
  ensure => running,
  enable => true,
}

file_line { 'SELinux set permissive in config':
  path   => '/etc/selinux/config',
  line   => 'SELINUX=permissive',
  match  => '^SELINUX=\w+',
  notify => Exec['SELinux set permissive in runtime'],
}

exec { 'SELinux set permissive in runtime':
  command     => '/sbin/setenforce 0',
  refreshonly => true,
}

docker::image { 'mysql': }
docker::image { 'my-httpd':
  docker_file => '/root/httpd-Dockerfile',
  subscribe   => File['/root/httpd-Dockerfile'],
}

docker::image { 'my-mysql':
  docker_file => '/root/mysql-Dockerfile',
  subscribe   => File['/root/mysql-Dockerfile'],
}
 
file { '/root/httpd-Dockerfile':
  ensure => file,
  content => '
FROM centos:centos7
RUN yum install -y httpd php epel-release wget
RUN wget http://packages.icinga.org/epel/ICINGA-release.repo -O /etc/yum.repos.d/ICINGA-release.repo
RUN yum -y install icinga
RUN usermod -aG icinga,icingacmd apache
RUN usermod -aG icinga,icingacmd root
ENTRYPOINT ["/usr/sbin/httpd", "-D", "FOREGROUND"]
'
}

file { '/root/mysql-Dockerfile':
  ensure => file,
  content => '
FROM mysql
RUN echo -n "[mysqld]\ngeneral_log=1\ngeneral_log_file=/var/log/mysql/mysql.log\nlog_error=/var/log/mysql/mysql_error.log" >> /etc/my.cnf
VOLUME [ "/var/log/" ]
VOLUME [ "/var/lib/mysql" ]
RUN mkdir -p /var/log/mysql/ /var/lib/mysql/
RUN touch /var/log/mysql/mysql.log && touch /var/log/mysql/mysql_error.log
RUN chown mysql:mysql -R /var/log/mysql/ /var/lib/mysql/
CMD [ "mysqld" ]
ENTRYPOINT [ "docker-entrypoint.sh" ]
'
}

docker::run { 'my-mysql':
  image    => 'my-mysql',
  volumes  => ['/var/lib/mysql:/var/lib/mysql',
               '/var/log:/var/log',],
  env      => [ 'MYSQL_ROOT_PASSWORD=password' ],
  ports    => [ '127.0.0.1:3306:3306'],
  username => 'mysql',
}

docker::run { 'my-httpd':
  image    => 'my-httpd',
  volumes  => ['/etc/httpd:/etc/httpd',
               '/var/www:/var/www',
               '/var/log:/var/log',
               '/var/spool:/var/spool',
               '/usr/lib64/icinga:/usr/lib64/icinga',
               '/usr/share/icinga:/usr/share/icinga',
               '/etc/icinga:/etc/icinga',
               '/etc/icinga2:/etc/icinga2' ],
  ports    => [ '80:80' ],
}

cron { 'MySQL logs to S3':
  ensure  => present,
  command => 's3cmd sync /var/log/mysql/ s3://angapov/mysql_logs/',
  hour    => 19,
  minute  => 00,
}

cron { 'apache logs to S3':
  ensure  => present,
  command => 's3cmd sync /var/log/httpd/ s3://angapov/apache_logs/',
  hour    => 19,
  minute  => 00,
}

file { 'mysql_backup':
  ensure  => file,
  path    => '/root/mysql_backup',
  mode    => '0770',
  content => '#!/bin/bash
BASEDIR=/root/mysqlbackup/
mkdir -p $BASEDIR
mysqldump -uroot -ppassword -h127.0.0.1 --all-databases | gzip -9 > $BASEDIR/$(date +%F-%T).sql.gz
if [[ $(ls $BASEDIR/ | wc -l) -gt 7 ]]; then
    for FILE in `ls -t $BASEDIR | tail -n+8`; do
        rm -f $BASEDIR/$FILE
    done
fi
s3cmd -q sync /root/mysqlbackup s3://angapov/mysql_backup/
',
}

cron { 'mysql_backup':
  ensure  => present,
  command => '/root/mysql_backup',
  hour    => 19,
  minute  => 00,
  require => File['mysql_backup'],
}
