$pkg = [ 'icinga', 'icinga2', 'icinga-gui', 's3cmd', ]
package { $pkg: ensure => latest }

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
docker::image { 'centos-httpd':
  docker_file => '/root/Dockerfile',
  subscribe   => File['/root/Dockerfile'],
}
 
file { '/root/Dockerfile':
  ensure => file,
  content => '
FROM centos
RUN yum install -y httpd php
ENTRYPOINT ["/usr/sbin/httpd", "-D", "FOREGROUND"]
'
}

docker::run { 'mysql':
  image    => 'mysql',
  volumes  => ['/var/lib/mysql:/var/lib/mysql',
               '/var/log:/var/log',
               '/etc/my.cnf:/etc/my.cnf',
               '/etc/my.cnf.d:/etc/my.cnf.d' ],
  env      => [ 'MYSQL_ROOT_PASSWORD=password' ],
  ports    => [ '127.0.0.1:3306:3306'],
}

docker::run { 'centos-httpd':
  image    => 'centos-httpd',
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
