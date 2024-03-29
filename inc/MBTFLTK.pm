package MBTFLTK;
use lib './lib';
use strict;
use warnings;
use Exporter 5.57 'import';
our @EXPORT = qw/Build Build_PL/;

use CPAN::Meta;
use ExtUtils::Config 0.003;
use ExtUtils::Helpers 0.020 qw/make_executable split_like_shell man1_pagename man3_pagename detildefy/;
use ExtUtils::Install qw/pm_to_blib install/;
use ExtUtils::InstallPaths 0.002;
use File::Basename qw/basename dirname/;
use File::Find ();
use File::Path qw/mkpath/;
use File::Spec::Functions qw/catfile catdir rel2abs abs2rel splitdir/;
use Getopt::Long qw/GetOptions/;
use JSON::PP 2 qw/encode_json decode_json/;
use HTTP::Tiny;
use Archive::Extract;
use File::pushd;
use File::Copy;
use File::Copy::Recursive qw[dircopy];

sub write_file {
	my ($filename, $mode, $content) = @_;
	open my $fh, ">:$mode", $filename or die "Could not open $filename: $!\n";;
	print $fh $content;
}
sub read_file {
	my ($filename, $mode) = @_;
	open my $fh, "<:$mode", $filename or die "Could not open $filename: $!\n";
	return do { local $/; <$fh> };
}

sub get_meta {
	my ($metafile) = grep { -e $_ } qw/META.json META.yml/ or die "No META information provided\n";
	return CPAN::Meta->load_file($metafile);
}

sub manify {
	my ($input_file, $output_file, $section, $opts) = @_;
	return if -e $output_file && -M $input_file <= -M $output_file;
	my $dirname = dirname($output_file);
	mkpath($dirname, $opts->{verbose}) if not -d $dirname;
	require Pod::Man;
	Pod::Man->new(section => $section)->parse_from_file($input_file, $output_file);
	print "Manifying $output_file\n" if $opts->{verbose} && $opts->{verbose} > 0;
	return;
}

sub process_xs {
	my ($source, $options) = @_;

	die "Can't build xs files under --pureperl-only\n" if $options->{'pureperl-only'};
	my (undef, @dirnames) = splitdir(dirname($source));
	my $file_base = basename($source, '.xs');
	my $archdir = catdir(qw/blib arch auto/, @dirnames, $file_base);

	my $c_file = catfile('lib', @dirnames, "$file_base.c");
	require ExtUtils::ParseXS;
	ExtUtils::ParseXS::process_file(filename => $source, prototypes => 0, output => $c_file);

	my $version = $options->{meta}->version;
	require ExtUtils::CBuilder;
	my $builder = ExtUtils::CBuilder->new(config => $options->{config}->values_set);
	my $ob_file = $builder->compile(source => $c_file, defines => { VERSION => qq/"$version"/, XS_VERSION => qq/"$version"/ });

	mkpath($archdir, $options->{verbose}, oct '755') unless -d $archdir;
	return $builder->link(objects => $ob_file, lib_file => catfile($archdir, "$file_base.".$options->{config}->get('dlext')), module_name => join '::', @dirnames, $file_base);
}

sub get_lib {
    my ($meta) = @_;
    my $location;
    my $index = 'http://fltk.org/pub/fltk/snapshots/';
    my $snaps = qr[fltk-1.3.x-r([\d\.]+)\.tar\.gz];
    {
        print "Finding most recent version...";
        my $response = HTTP::Tiny->new->get($index);
        if ($response->{success}) {
            my ($version) = reverse sort ($response->{content} =~ /$snaps/g);
            $location = $index . 'fltk-1.3.x-r'.$version.'.tar.gz';
            print " r$version\n";
        }
        else {
            print " Hrm. Grabbing latest stable release\n";
            $location = 'http://fltk.org/pub/fltk/1.3.2/fltk-1.3.2-source.tar.gz';
        }
    }
    my  $file  = basename($location);
    {
        print "Downloading $file...";
        my $response = HTTP::Tiny->new->mirror($location, $file );
        if ($response->{success}) {
            print " Done\n";
            return $file;
        }
    }
    exit !!print " Fail!";
}

sub build_lib {
    my ($options) = @_;
    my (%libinfo, $dir);
    my $meta = $options->{meta};
    my $cwd = rel2abs './'; # XXX - use Cwd;

    # This is an ugly cludge. A working, ugly cludge though. :\
    if (!-d 'share') {
        mkpath('share', $options->{verbose}, oct '755') unless -d 'share';
        $dir = tempd();
        $libinfo{archive} = get_lib($meta->custom('x_alien'));
        print "Extracting...";
        my $ae = Archive::Extract->new(archive => $libinfo{archive});
        exit print " Fail! " . $ae->error if ! $ae->extract();
        print " Done\nConfigure...\n";
        chdir($ae->extract_path);
        system q[sh configure];
        $libinfo{cflags} = `sh fltk-config --cflags` ;
        $libinfo{cxxflags} = `sh fltk-config --cxxflags`;
        $libinfo{ldflags} = `sh fltk-config --ldflags` ;
        $libinfo{ldflags_gl} =     `sh fltk-config --ldflags --use-gl` ;
        $libinfo{ldflags_gl_images} = `sh fltk-config --ldflags --use-gl --use-images` ;
        $libinfo{ldflags_images} = `sh fltk-config --ldflags --use-images` ;

        # XXX - The following block is a mess!!!
        chdir 'src';
		use Config;
		system (
			$^O =~ m[win32]i ?
			'gmake -n | sh' :
			`which make`);
		chdir '..';
        my $archdir = catdir($cwd, qw[share]);
        mkpath($archdir, $options->{verbose}, oct '755') unless -d $archdir;
        # XXX - Copy FL  => shared dir

        dircopy
            rel2abs('FL'),
            catdir($archdir, 'include', 'FL') or die $!;

        copy
            rel2abs(catdir('config.h')),
            catdir($archdir, 'include', 'config.h') or die $!;

        dircopy
            rel2abs('lib'),
            catdir($archdir, 'lib') or die $!;

        #
        write_file(catfile($archdir, qw[config.json]), 'utf8', encode_json(\%libinfo));
    }
}
sub find {
	my ($pattern, $dir) = @_;
	my @ret;
	File::Find::find(sub { push @ret, $File::Find::name if /$pattern/ && -f }, $dir) if -d $dir;
	return @ret;
}

my %actions = (
	build => sub {
		my %opt = @_;
		system $^X, $_ and die "$_ returned $?\n" for find(qr/\.PL$/, 'lib');
		my %modules = map { $_ => catfile('blib', $_) } find(qr/\.p(?:m|od)$/, 'lib');
		my %scripts = map { $_ => catfile('blib', $_) } find(qr//, 'script');
        build_lib(\%opt);
		my %shared =  map { $_ => catfile(qw/blib lib auto share dist/, $opt{meta}->name, abs2rel($_, 'share')) } find(qr//, 'share');
        pm_to_blib({ %modules, %scripts, %shared }, catdir(qw/blib lib auto/));
		make_executable($_) for values %scripts;
		mkpath(catdir(qw/blib arch/), $opt{verbose});
        process_xs($_, \%opt) for find(qr/.xs$/, 'lib');

		if ($opt{install_paths}->install_destination('libdoc') && $opt{install_paths}->is_default_installable('libdoc')) {
			manify($_, catfile('blib', 'bindoc', man1_pagename($_)), $opt{config}->get('man1ext'), \%opt) for keys %scripts;
			manify($_, catfile('blib', 'libdoc', man3_pagename($_)), $opt{config}->get('man3ext'), \%opt) for keys %modules;
		}
	},
	dist => sub {
		my $meta = get_meta();
		my $name = $meta->name;
		require Alien::FLTK;
		$meta->{version} = $Alien::FLTK::VERSION;
		my $version = $meta->version;
     	printf "Creating new dist for '%s' version '%s'\n", $name, $version;

		#
		$meta->save("META.json", {version => 2});
		$meta->save("META.yml",  {version => 1.4});

		#
		require Pod::Readme;
		Pod::Readme->new( readme_type => 'text' )->parse_from_file( 'lib/Alien/FLTK.pm', 'README' );

		# XXX - Use a distdir
		require Archive::Tar;
		open my $fh, 'MANIFEST';
		my $files = [split m[\n], do { local $/; <$fh> }];

		# Archive::Tar versions >= 1.09 use the following to enable a compatibility
		# hack so that the resulting archive is compatible with older clients.
		# If no file path is 100 chars or longer, we disable the prefix field
		# for maximum compatibility.  If there are any long file paths then we
		# need the prefix field after all.
		$Archive::Tar::DO_NOT_USE_PREFIX =
		(grep { length($_) >= 100 } @$files) ? 0 : 1;

		my $tar   = Archive::Tar->new;
		$tar->add_files(@$files);
		for my $f ($tar->get_files) {
			$f->mode($f->mode & ~022); # chmod go-w
		}
		$tar->write("$name-$version.tar.gz", 1);
	},
	test => sub {
		my %opt = @_;
		die "Must run `./Build build` first\n" if not -d 'blib';
		require TAP::Harness;
		my $tester = TAP::Harness->new({verbosity => $opt{verbose}, lib => [ map { rel2abs(catdir(qw/blib/, $_)) } qw/arch lib/ ], color => -t STDOUT});
		$tester->runtests(sort +find(qr/\.t$/, 't'))->has_errors and exit 1;
	},
	install => sub {
		my %opt = @_;
		die "Must run `./Build build` first\n" if not -d 'blib';
		install($opt{install_paths}->install_map, @opt{qw/verbose dry_run uninst/});
	},
);

sub Build {
	my $action = @ARGV && $ARGV[0] =~ /\A\w+\z/ ? shift @ARGV : 'build';
	die "No such action '$action'\n" if not $actions{$action};
	unshift @ARGV, @{ decode_json(read_file('_build_params', 'utf8')) };
	GetOptions(\my %opt, qw/install_base=s install_path=s% installdirs=s destdir=s prefix=s config=s% uninst:1 verbose:1 dry_run:1 pureperl-only:1 create_packlist=i/);
	$_ = detildefy($_) for grep { defined } @opt{qw/install_base destdir prefix/}, values %{ $opt{install_path} };
	@opt{'config', 'meta'} = (ExtUtils::Config->new($opt{config}), get_meta());
	$actions{$action}->(%opt, install_paths => ExtUtils::InstallPaths->new(%opt, dist_name => $opt{meta}->name));
}

sub Build_PL {
	my $meta = get_meta();
	printf "Creating new 'Build' script for '%s' version '%s'\n", $meta->name, $meta->version;
	my $dir = $meta->name eq 'MBTFLTK' ? '' : "use lib 'inc';";
	write_file('Build', 'raw', "#!perl\n$dir\nuse MBTFLTK;\n\$|++;\nBuild();\n");
	make_executable('Build');
	my @env = defined $ENV{PERL_MB_OPT} ? split_like_shell($ENV{PERL_MB_OPT}) : ();
	write_file('_build_params', 'utf8', encode_json([ @env, @ARGV ]));
	$meta->save(@$_) for ['MYMETA.json'], ['MYMETA.yml' => { version => 1.4 }];
}

1;

=head1 SEE ALSO

L<Module::Build::Tiny>

=head1 ORIGINAL AUTHORS

=over 4

=item *

Leon Timmermans <leont@cpan.org>

=item *

David Golden <dagolden@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Leon Timmermans, David Golden.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
