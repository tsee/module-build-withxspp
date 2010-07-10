package Module::Build::WithXSpp;
use strict;
use warnings;

use Module::Build;
use ExtUtils::CppGuess ();
our @ISA = qw(Module::Build);
our $VERSION = '0.02';

# TODO
# - configurable set of xsp and xspt files (and XS typemaps?)
#   => works via directories for now.
# - configurable includes/C-preamble for the XS?
#   => Works in the .xsp files, but the order of XS++ inclusion
#      is undefined.
# - configurable C++ source folder(s) (works, needs docs)
#   => to be documented another time. This is really not a feature that
#      should be commonly used.
# - regenerate main.xs only if neccessary

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

  push @{$self->extra_compiler_flags}, map "-I$_", @{$self->cpp_source_dirs||[]};

  $self->_init(\%args);

  return $self;
}

sub _init {
  my $self = shift;
  my $args = shift;

}

sub auto_require {
  my ($self) = @_;
  my $p = $self->{properties};

  if ( $self->dist_name ne 'Module-Build-WithXSpp'
    && $self->auto_configure_requires
    && ! exists $p->{configure_requires}{'Module::Build::WithXSpp'}
  ) {
    (my $ver = $VERSION) =~ s/^(\d+\.\d\d).*$/$1/; # last major release only
    $self->_add_prereq('configure_requires', 'Module::Build::WithXSpp', $ver);
  }

  $self->SUPER::auto_require();

  return;
}

sub ACTION_create_buildarea {
  my $self = shift;
  mkdir($self->build_dir);
  $self->add_to_cleanup($self->build_dir);
}

sub ACTION_code {
  my $self = shift;
  $self->depends_on('create_buildarea');
  $self->depends_on('generate_typemap');
  $self->depends_on('generate_main_xs');

  my $files = {};
  foreach my $ext (qw(c cc cxx cpp C)) {
    foreach my $dir (@{$self->cpp_source_dirs||[]}) {
      my $this = $self->_find_file_by_type($ext, $dir);
      $files = $self->_merge_hashes($files, $this);
    }
  }

  my @objects;
  foreach my $file (keys %$files) {
    my $obj = $self->compile_c($file);
    push @objects, $obj;
    $self->add_to_cleanup($obj);
  }

  $self->{properties}{objects} ||= [];
  push @{$self->{properties}{objects}}, @objects;

  return $self->SUPER::ACTION_code(@_);
}

sub ACTION_generate_main_xs {
  my $self = shift;

  my $xs_files = $self->find_xs_files;

  if (keys(%$xs_files) > 1
      or keys(%$xs_files) == 1
      && (values(%$xs_files))[0] =~ /\bmain\.xs$/) # FIXME better detection of auto-gen main.XS
  {
    # user knows what she's doing, do not generate XS
    $self->log_info("Found custom XS files. Not auto-generating main XS file...\n");
    return 1;
  }

  $self->log_info("Generating main XS file...\n");
  my $xsp_files = $self->find_xsp_files;
  my $xspt_files = $self->find_xsp_typemaps;

  my $module_name = $self->module_name;
  my $xs_code = <<"HERE";
/*
 * WARNING: This file was auto-generated. Changes will be lost!
 */

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#undef do_open
#undef do_close
#ifdef __cplusplus
}
#endif

MODULE = $module_name	PACKAGE = $module_name

HERE

  my $typemap_args = '';
  $typemap_args .= '-t ' . Cwd::abs_path($_) . ' ' foreach keys %$xspt_files;

  foreach my $xsp_file (keys %$xsp_files) {
    my $full_path_file = Cwd::abs_path($xsp_file);
    my $cmd = "INCLUDE_COMMAND: \$^X -MExtUtils::XSpp::Cmd -e xspp -- $typemap_args $full_path_file\n\n";
    $xs_code .= $cmd;
  }

  my $outfile = File::Spec->catdir($self->build_dir, 'main.xs');
  open my $fh, '>', $outfile
    or die "Could not open '$outfile' for writing: $!";
  print $fh $xs_code;
  close $fh;

  return 1;
}

sub ACTION_generate_typemap {
  my $self = shift;
  $self->depends_on('create_buildarea');

  $self->log_info("Processing XS typemap files...\n");

  require ExtUtils::Typemap;
  require File::Spec;

  my $files = $self->find_map_files;

  # merge all typemaps into 'buildtmp/typemap'
  # creates empty typemap file if there are no files to merge
  my $out_map_file = File::Spec->catfile($self->build_dir, 'typemap');
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
  my @extra_files = map glob($_),
                    map File::Spec->catfile($_, '*.map'),
                    @{$self->extra_xs_dirs||[]};
  $files->{$_} = $_ foreach map $self->localize_file_path($_),
                            @extra_files;
  $files->{'typemap'} = 'typemap' if -f 'typemap';

  return $files;
}


sub find_xsp_files  {
  my $self = shift;

  my @extra_files = map glob($_),
                    map File::Spec->catfile($_, '*.xsp'),
                    @{$self->extra_xs_dirs||[]};
  my $files = $self->_find_file_by_type('xsp', 'lib');
  $files->{$_} = $_ foreach map $self->localize_file_path($_),
                            @extra_files;

  require File::Basename;
  # XS++ typemaps aren't XSP files in this regard
  foreach my $file (keys %$files) {
    delete $files->{$file}
      if File::Basename::basename($file) eq 'typemap.xsp';
  }

  return $files;
}

sub find_xsp_typemaps {
  my $self = shift;

  my $xsp_files = $self->_find_file_by_type('xsp', 'lib');
  my $xspt_files = $self->_find_file_by_type('xspt', 'lib');

  foreach (keys %$xsp_files) { # merge over 'typemap.xsp's
    next unless File::Basename::basename($_) eq 'typemap.xsp';
    $xspt_files->{$_} = $_
  }

  my @extra_files = map glob($_),
                    grep defined $_ && /\S/ && -e $_,
                    map { ( File::Spec->catfile($_, 'typemap.xsp'),
                            File::Spec->catfile($_, '*.xspt') ) }
                    @{$self->extra_xs_dirs||[]};
  $xspt_files->{$_} = $_ foreach map $self->localize_file_path($_),
                                 @extra_files;
  return $xspt_files;
}


# This overrides the equivalent in the base class to add the buildtmp and
# the main directory
sub find_xs_files {
  my $self = shift;
  my $xs_files = $self->SUPER::find_xs_files;

  my @extra_files = map glob($_),
                    map File::Spec->catfile($_, '*.xs'),
                    @{$self->extra_xs_dirs||[]};

  $xs_files->{$_} = $_ foreach map $self->localize_file_path($_),
                               @extra_files;

  my $auto_gen_file = File::Spec->catfile($self->build_dir, 'main.xs');
  if (-e $auto_gen_file) {
    $xs_files->{$auto_gen_file} =  $self->localize_file_path($auto_gen_file);
  }
  return $xs_files;
}


# overridden from original. We really require
# EU::ParseXS, so the "if (eval{require EU::PXS})" is gone.
sub compile_xs {
  my ($self, $file, %args) = @_;
  $self->log_verbose("$file -> $args{outfile}\n");

  require ExtUtils::ParseXS;

  my $main_dir = Cwd::abs_path( Cwd::cwd() );
  my $build_dir = Cwd::abs_path( $self->build_dir );
  ExtUtils::ParseXS::process_file(
    filename   => $file,
    prototypes => 0,
    output     => $args{outfile},
    # not default:
    'C++' => 1,
    hiertype => 1,
    typemap    => File::Spec->catfile($build_dir, 'typemap'),
  );

}

# modified from orinal M::B (FIXME: shouldn't do this with private methods)
# Changes from the original:
# - If we're looking at the "main.xs" file in the build
#   directory, override the TARGET paths with the real
#   module name.
# - In that case, also override the file basename for further
#   build products (maybe this should only be done on installation
#   into blib/.../?)
sub _infer_xs_spec {
  my $self = shift;
  my $file = shift;

  my $cf = $self->{config};

  my %spec;

  my( $v, $d, $f ) = File::Spec->splitpath( $file );
  my @d = File::Spec->splitdir( $d );
  (my $file_base = $f) =~ s/\.[^.]+$//i;

  my $build_folder = $self->build_dir;
  if ($d =~ /\Q$build_folder\E/ && $file_base eq 'main') {
    my $name = $self->module_name;
    @d = split /::/, $name;
    $file_base = $d[-1];
    pop @d if @d;
  }
  else {
    # the module name
    shift( @d ) while @d && ($d[0] eq 'lib' || $d[0] eq '');
    pop( @d ) while @d && $d[-1] eq '';
  }

  $spec{base_name} = $file_base;

  $spec{src_dir} = File::Spec->catpath( $v, $d, '' );

  $spec{module_name} = join( '::', (@d, $file_base) );

  $spec{archdir} = File::Spec->catdir($self->blib, 'arch', 'auto',
				      @d, $file_base);

  $spec{bs_file} = File::Spec->catfile($spec{archdir}, "${file_base}.bs");

  $spec{lib_file} = File::Spec->catfile($spec{archdir},
					"${file_base}.".$cf->get('dlext'));

  $spec{c_file} = File::Spec->catfile( $spec{src_dir},
				       "${file_base}.c" );

  $spec{obj_file} = File::Spec->catfile( $spec{src_dir},
					 "${file_base}".$cf->get('obj_ext') );

  return \%spec;
}

__PACKAGE__->add_property( 'cpp_source_dirs' => ['src'] );
__PACKAGE__->add_property( 'build_dir'       => 'buildtmp' );
__PACKAGE__->add_property( 'extra_xs_dirs'   => [qw(. xs XS xsp XSP)] );


sub _merge_hashes {
  my $self = shift;
  my %h;
  foreach my $m (@_) {
    $h{$_} = $m->{$_} foreach keys %$m;
  }
  return \%h;
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
    # normal Module::Build arguments...
  );
  $build->create_build_script;

=head1 DESCRIPTION

This subclass of L<Module::Build> adds some tools and
processes to make it easier to use for wrapping C++
using XS++ (L<ExtUtils::XSpp>).

There are a few minor differences from using C<Module::Build>
for an ordinary XS module and a few conventions that you
should be aware of as an XS++ module author. They are documented
in the L</"FEATURES AND CONVENTIONS"> section below. But if you
can't be bothered to read all that, you may choose skip it and
blindly follow the advice in L</"JUMP START FOR THE IMPATIENT">.

An example of a full distribution based on this build tool
can be found in the L<ExtUtils::XSpp> distribution under
F<examples/XSpp-Example>. Using that example as the basis
for your C<Module::Build::WithXSpp>-based distribution
is probably a good idea.

=head1 FEATURES AND CONVENTIONS

=head2 XS files

By default, C<Module::Build::WithXSpp> will automatically
generate a main XS file for your module which includes
all XS++ files and does the correct incantations to support
C++.

If C<Module::Build::WithXSpp> detects any XS files in your
module, it will skip the generation of this default file
and assume that you wrote a custom main XS file. If
that is not what you want, and wish to simply include
plain XS code, then you should put the XS in a verbatim
block of an F<.xsp> file. In case you need to use the plain-C
part of an XS file for C<#include> directives and other code,
then put your code into a header file and C<#include> it
from an F<.xsp> file:

In F<src/mystuff.h>:

  #include <something>
  using namespace some::thing;

In F<xsp/MyClass.xsp>

  #include "mystuff.h"
  
  %{
    ... verbatim XS here ...
  %}

Note that there is no guarantee about the order in which the
XS++ files are picked up.

=head2 Build directory

When building your XS++ based extension, a temporary
build directory F<buildtmp> is created for the byproducts.
It is automatically cleaned up by C<./Build clean>.

=head2 Source directories

A Perl module distribution typically has the module C<.pm> files
in its F<lib> subdirectory. In a C<Module::Build::WithXSpp> based
distribution, there are two more such conventions about source
directories:

If any C++ source files are present in the F<src> directory, they
will be compiled to object files and linked automatically.

Any C<.xs>, C<.xsp>, and C<.xspt> files in an F<xs> or F<xsp>
subdirectory will be automatically picked up and included
by the build system.

For backwards compatibility, files of the above types are also
recognized in F<lib>.

=head2 Typemaps

In XS++, there are two types of typemaps: The ordinary XS typemaps
which conventionally put in a file called F<typemap>, and XS++ typemaps.

The ordinary XS typemaps will be found in the main directory,
under F<lib>, and in the XS directories (F<xs> and F<xsp>). They are
required to carry the C<.map> extension or to be called F<typemap>.
You may use multiple F<.map> files if the entries do not
collide. They will be merged at build time into a complete F<typemap> file
in the temporary build directory.

The XS++ typemaps are required to carry the C<.xspt> extension or (for
backwards compatibility) to be called C<typemap.xsp>.

=head2 Detecting the C++ compiler

C<Module::Build::WithXSpp> uses L<ExtUtils::CppGuess> to detect
a C++ compiler on your system that is compatible with the C compiler
that was used to compile your perl binary. It sets some
additional compiler/linker options.

This is known to work on GCC (Linux, MacOS, Windows, and ?) as well
as the MS VC toolchain. Patches to enable other compilers are
B<very> welcome.

=head1 JUMP START FOR THE IMPATIENT

There are as many ways to start a new CPAN distribution as there
are CPAN distributions. Choose your favourite
(I just do C<h2xs -An My::Module>), then apply a few
changes to your setup:

=over 2

=item *

Obliterate any F<Makefile.PL>.

This is what your F<Build.PL> should look like:

  use strict;
  use warnings;
  use 5.006001;
  use Module::Build::WithXSpp;
  
  my $build = Module::Build::WithXSpp->new(
    module_name         => 'My::Module',
    license             => 'perl',
    dist_author         => q{John Doe <john_does_mail_address>},
    dist_version_from   => 'lib/My/Module.pm',
    build_requires => { 'Test::More' => 0, },
  );
  $build->create_build_script;

If you need to link against some library C<libfoo>, add this to
the options:

    extra_linker_flags => [qw(-lfoo)],

There is C<extra_compiler_flags>, too, if you need it.

=item *

You create two folders in the main distribution folder:
F<src> and F<xsp>.

=item *

You put any C++ code that you want to build and include
in the module into F<src/>. All the typical C(++) file
extensions are recognized and will be compiled to object files
and linked into the module. And headers in that folder will
be accessible for C<#include E<lt>myheader.hE<gt>>.

For good measure, move a copy of F<ppport.h> to that directory.
See L<Devel::PPPort>.

=item *

You do not write normal XS files. Instead, you write XS++ and
put it into the F<xsp/> folder in files with the C<.xsp>
extension. Do not worry, you can include verbatim XS blocks
in XS++. For details on XS++, see L<ExtUtils::XSpp>.

=item *

If you need to do any XS type mapping, put your typemaps
into a F<.map> file in the C<xsp> directory. XS++ typemaps
belong into F<.xspt> files in the same directory.

=item *

In this scheme, F<lib/> only contains Perl module files (and POD).
If you started from a pure-Perl distribution, don't forget to add
these magic two lines to your main module:

  require XSLoader;
  XSLoader::load('My::Module', $VERSION);

=head1 SEE ALSO

L<Module::Build> upon which this module is based.

L<ExtUtils::XSpp> implements XS++. The C<ExtUtils::XSpp> distribution
contains an F<examples> directory with a usage example of this module.

=head1 AUTHOR

Steffen Mueller <smueller@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2010 Steffen Mueller.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

