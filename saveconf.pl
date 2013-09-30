#!/usr/bin/perl

use YAML 'DumpFile';

my $config = {
app_path => '/var/www/london/weblog',
db_path => '/var/www/london/weblog/storage',
db_name => 'users.db',
yaml_path => '/var/www/london/htdocs/blogfiles',
http_user => 'apache',
blog_name => 'test a blog test blog blog',
post_limit => 2,
action_hdr => 'Actions',
functn_hdr => 'Functions',
base_url => 'http://london.evolone.org/weblog/miniblog.pl',
doc_root => '/var/www/london/htdocs',
css_url => '/css',
admin_page => 'announce.yml',
ssh_host => 'evolone.org',
ssh_user => 'root',
pub_key =>'/home/col/.ssh/id_dsa.pub',
priv_key =>'/home/col/.ssh/id_dsa',
};

DumpFile('testconf.yml',$config);
