$pkg = [ 'icinga2', 'icinga-gui', ]
package { $pkg: ensure => latest }
yumrepo { 'docker':
  baseurl => 'https://yum.dockerproject.org/repo/main/centos/7/',
  gpgkey  => 'https://yum.dockerproject.org/gpg',
}
yumrepo { 'icinga':
  baseurl => 'http://packages.icinga.org/epel/$releasever/release/',
  gpgkey  => 'http://packages.icinga.org/icinga.key',
}
yumrepo { 'epel':
  mirrorlist =>'https://mirrors.fedoraproject.org/metalink?repo=epel-source-7&arch=$basearch',
  gpgcheck   => 0
}

class { 'docker':
  use_upstream_package_source => false,
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
               '/etc/my.cnf:/etc/my.cnf',
               '/etc/my.cnf.d:/etc/my.cnf.d' ],
  env      => [ 'MYSQL_ROOT_PASSWORD=password' ],
  ports    => [ '3306:3306'],
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
