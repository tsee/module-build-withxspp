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

  $self->add_build_element('map');
}

sub process_map_files {
  my $self = shift;

  my @files = $self->find_map_files;
  return if !@files;

  if (@files and -f 'typemap') {
    my $age = -M 'typemap';
    return if !grep {-M $_ < $age} @files;
  }

  # merge all typemaps into 'typemap'
  require ExtUtils::Typemap;
  my $merged = ExtUtils::Typemap->new;
  foreach my $file (@files) {
    $merged->merge(typemap => ExtUtils::Typemap->new(file => $file));
  }
  $merged->write(file => 'typemap');
  $self->add_to_cleanup('typemap');
}

sub find_map_files  {
  my @files = shift->_find_file_by_type('map', 'lib');
  push @files, glob("*.map");
  return @files;
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

=head2 Typemaps

You can put your XS typemaps into arbitray F<.map> files in the F<lib>
directory. You may use multiple F<.map> files if the entries do not
collide. They will be merged at build time into the F<typemap> file
in the top directory. For this reason, you B<MUST NOT> put your
typemaps into the top-level typemap file. They will be overwritten.

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

