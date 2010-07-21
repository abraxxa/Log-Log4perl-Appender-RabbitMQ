#!/usr/bin/perl

use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
    module_name => 'Log::Log4perl::Appender::RabbitMQ',
    license  => 'perl',
    requires => {
        'perl'           => '5.6.1',
        'Net::RabbitMQ'  => '0.1.5',
    },
    build_requires => {
        'Test::Net::RabbitMQ' => 0,
        'Test::More'          => 0,
        'Test::Output'        => 0,
    },
    create_readme   => 1,
    create_install  => 1,
    create_metafile => 1,
    meta_merge => {
       resources => {
          repository => 'http://github.com/bundacia/Log-Log4perl-Appender-RabbitMQ',
      },
    }, 
);
$build->create_build_script;
