package Module::Build::WithXSpp;
use strict;
use warnings;

use Module::Build;
use ExtUtils::CppGuess ();
our @ISA = qw(Module::Build);
our $VERSION = '0.01'; # update in SYNOPSIS, too!

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;

  # This gives us the correct settings for the C++ compile (hopefully)
  my $guess = ExtUtils::CppGuess->new();
  $guess->add_extra_compiler_flags($args{extra_compiler_flags})
    if defined $args{extra_compiler_flags};
  $guess->add_extra_linker_flags($args{extra_linker_flags})
    if defined $args{extra_linker_flags};

  $guess->add_extra_compiler_flags('-Isrc') if -d 'src';

  # Construct object using C++ options guess
  my $self = $class->SUPER::new(
    %args,
    $guess->module_build_options # FIXME find a way to let the user override this
  );

  $self->_init(\%args);

  return $self;
}

sub _init {
  my $self = shift;
  my $args = shift;

}

sub ACTION_create_buildarea {
  my $self = shift;
  mkdir('buildtmp');
  $self->add_to_cleanup("buildtmp");
}

sub ACTION_code {
  my $self = shift;
  $self->depends_on('create_buildarea');
  $self->depends_on('generate_typemap');
  return $self->SUPER::ACTION_code(@_);
}

sub ACTION_generate_typemap {
  my $self = shift;
  $self->depends_on('create_buildarea');

  $self->log_info("Processing XS typemap files...");

  require ExtUtils::Typemap;
  require File::Spec;

  my $files = $self->find_map_files;

  # merge all typemaps into 'buildtmp/typemap'
  # creates empty typemap file if there are no files to merge
  my $out_map_file = File::Spec->catfile('buildtmp', 'typemap');
  if (keys %$files and -f $out_map_file) {
    my $age = -M $out_map_file;
    return if !grep {-M $_ < $age} keys %$files;
  }

  my $merged = ExtUtils::Typemap->new;
  foreach my $file (keys %$files) {
    $merged->merge(typemap => ExtUtils::Typemap->new(file => $file));
  }
  $merged->write(file => $out_map_file);
}

sub find_map_files  {
  my $self = shift;
  my $files = $self->_find_file_by_type('map', 'lib');
  $files->{$_} = $_ foreach map $self->localize_file_path($_),
                            glob("*.map");
  $files->{'typemap'} = 'typemap' if -f 'typemap';

  return $files;
}


sub find_xsp_files  {
  my $self = shift;
  my $files = $self->_find_file_by_type('xsp', 'lib');
  $files->{$_} = $_ foreach map $self->localize_file_path($_),
                            glob("*.xsp");

  require File::Basename;
  # XS++ typemaps aren't XSP files in this regard
  foreach my $file (keys %$files) {
    delete $files->{$file}
      if File::Basename::basename($file) =~ /^typemap.*\.xsp$/; 
  }

  return $files;
}

sub find_xsp_typemaps {
  my $self = shift;
  my $files = $self->_find_file_by_type('xsp', 'lib');
  $files->{$_} = $_ foreach map $self->localize_file_path($_),
                            glob("*.xsp");

  require File::Basename;
  # XS++ typemaps aren't XSP files in this regard
  foreach my $file (keys %$files) {
    delete $files->{$file}
      if File::Basename::basename($file) !~ /^typemap.*\.xsp$/; 
  }

  return $files;
}


1;

__END__

=head1 NAME

Module::Build::WithXSpp - XS++ enhanced flavour of Module::Build

=head1 SYNOPSIS

In F<Build.PL>:

    use strict;
    use warnings;
    use 5.006001;
    
    use Module::Build::WithXSpp;
    
    my $build = Module::Build::WithXSpp->new(
      configure_requires => {
        'Module::Build::WithXSpp' => '0.01',
      },
      # normal Module::Build arguments...
    );
    $build->create_build_script;

=head1 DESCRIPTION

This subclass of L<Module::Build> adds some tools and
processes to make it easier to use for wrapping C++
using XS++ (L<ExtUtils::XSpp>).

There are a few minor differences from using C<Module::Build>
for an ordinary XS module and a fewconventions that you
should be aware of as an XS/XS++ module author:

=head1 FEATURES AND CONVENTIONS

=head2 Build directory

When building your XS++ based extension, a temporary
build directory F<buildtmp> is created for the byproducts.

=head2 Typemaps

You can put your XS typemaps into arbitray F<.map> files in the F<lib>
directory, any F<.map> files in the main directory, or
in the main directories F<typemap> file.
You may use multiple F<.map> files if the entries do not
collide. They will be merged at build time into a F<typemap> file
in the temporary build directory.

=head2 Detecting the C++ compiler

C<Module::Build::WithXSpp> uses L<ExtUtils::CppGuess> to detect
a C++ compiler on your system that is compatible with the C compiler
that was used to compile your perl binary. It sets some
additional compiler/linker options.

This is known to work on GCC (Linux, MacOS, Windows, and ?) as well
as the MS VC toolchain. Patches to enable other compilers are
B<very> welcome.

=head1 AUTHOR

Steffen Mueller <smueller@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2010 Steffen Mueller.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

