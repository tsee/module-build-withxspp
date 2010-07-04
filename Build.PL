#!/usr/bin/perl -w

use strict;
use Module::Build;

my $build = Module::Build->new(
  module_name    => 'Module::Build::WithXSpp',
  license        => 'perl',
  requires       => {
    'ExtUtils::XSpp' => '0.11',
    'Module::Build' => '0',
  },
  configure_requires => {
    'Module::Build' => '0',
  },
  test_requires  => {
    'Test::More' => '0',
  },
);

$build->create_build_script;
