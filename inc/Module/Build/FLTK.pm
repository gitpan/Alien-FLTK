package inc::Module::Build::FLTK;
use strict;
use warnings;
use base 'Module::Build';
#
$|++;

sub ACTION_build {
    my $s = shift;

    # TODO:
    #  - Find most recent version
    print 'finding the most recent snapshot of FLTK 1.3.x... ';
    my ($rev, $bz2, $gz)
        = $s->config_data('revision') ?
        ($s->config_data('revision'),
         $s->config_data('md5_bz2'),
         $s->config_data('md5_gz')
        )
        : $s->_latest_revision();
    $s->config_data('revision', $rev);
    $s->config_data('md5_bz2',  $bz2);
    $s->config_data('md5_gz',   $gz);
    print "r$rev\n";
    #
    my $dest = $s->base_dir . "/working/archive/fltk-1.3.x-r$rev.tar.bz2";
    if (-e $dest) {
        if (!$s->_hashcheck_snapshot($dest, $bz2)) {
            unlink $dest;
            $s->_download_snapshot($rev, $s->base_dir . '/working/archive/');
        }
    }
    else {
        $s->_download_snapshot($rev, $s->base_dir . '/working/archive/');

        #  - Check hash
        exit !1 if !$s->_hashcheck_snapshot($dest, $bz2);
    }

    #  - Extract to working/extract
    my $extract = $s->base_dir . '/working/extract';
    $s->_extract_snapshot($dest, $extract)
        if !-e "$extract/fltk-1.3.x-r$rev/src/Fl.cxx";
    exit !1 if !$extract;

    #  - Configure
    chdir "$extract/fltk-1.3.x-r$rev/";
    $s->_configure();

    #  - Compile and make libs
    $s->_make();
    chdir $s->base_dir;

    #  - Copy libs to ./blib/auto/Alien/FLTK/lib/
    $s->_copy_libs();

    #  - Copy headers to ./blib/auto/Alien/FLTK/include/
    $s->_copy_headers();

    # Do what you gotta do, man
    $s->SUPER::ACTION_build;
}

sub ACTION_clean {
    my $s = shift;
    $s->_clean();
    $s->SUPER::ACTION_clean;
}

sub ACTION_distclean {
    my $s = shift;

    # TODO:
    #  - Delete archive
    #  - rmdir ./working
    $s->SUPER::ACTION_distclean;
}

# Utility functions
sub _latest_revision {
    my $s   = shift;
    my $rev = $s->config_data('rev');
    return ($s->config_data('md5_bz2'), $s->config_data('md5_gz')) if $rev;
    require File::Fetch;
    my $response = '';
    my $okay = File::Fetch->new(uri => 'http://fltk.org/software.php')
        ->fetch(to => \$response);
    return () if !$okay;
    my ($bz2, $gz);
    ($rev) = ($response =~ m[1.3.x-r(\d{4,5})]);
    ($bz2, $gz) = (
        $response =~    # Ugly screen scrape...
            m[<tt>fltk-1.3.x-r$rev.tar.bz2</tt>.*<tt>(.{32})</tt>.*
      <tt>fltk-1.3.x-r$rev.tar.gz</tt>.*<tt>(.{32})</tt>]sx
    );
    ($rev, $bz2, $gz);
}

sub _download_snapshot {
    my ($s, $rev, $dest) = @_;

    #  - Pick mirror
    my %mirrors = (
            'California, USA' => 'ftp.easysw.com/pub',
            'New Jersey, USA' => 'ftp2.easysw.com/pub',
            'Espoo, Finland' => 'ftp.funet.fi/pub/mirrors/ftp.easysw.com/pub',
    );
    for my $loc (keys %mirrors) {
        for my $prot (qw[http ftp]) {

            #  - Download archive to working/archive (bz2 then gzip as backup)
            printf 'downloading snapshot from %s mirror in %s... ', $prot,
                $loc;
            require File::Fetch;
            my $ff = File::Fetch->new(
                uri => sprintf '%s://%s/fltk/snapshots/fltk-1.3.x-r%d.tar.%s',
                $prot, $mirrors{$loc}, $rev, 'bz2');
            my $where = $ff->fetch(to => $dest);
            if ($where) {
                print "done\n";
                return !!1;
            }
        }
    }

    # XXX - provide alternative (put archive in /working/archive/, etc)
    printf "Fail!\n";
    return !1;
}

sub _hashcheck_snapshot {
    my ($s, $where, $hash) = @_;
    print 'hash checking snapshot... ';
    require Digest::MD5;
    if (open(my $fh, '<', $where)) {
        binmode($fh);
        my $actual = lc(Digest::MD5->new->addfile($fh)->hexdigest);
        my $okay = lc($hash) eq $actual;
        print(($okay ? '' : 'not ') . "okay\n");
        return !!$okay;
    }
    print "Can't open $where: $!";
    return !1;
}

sub _extract_snapshot {
    my ($s, $where, $dest) = @_;
    require Archive::Extract;
    print 'extracting snapshot... ';
    my $ae = Archive::Extract->new(archive => $where);
    if ($ae->extract(to => $dest)) {
        printf "okay. %d bytes, %d files\n", scalar $ae->files,
            $#{$ae->files};
        return $ae->extract_path;
    }
    printf "Error: %s\n", $ae->error;
    return !1;
}

sub _configure {    # expects to be in the top of the extracted directory
    my $s = shift;
    return if -e 'config.status';
    my $ret = system(qw[sh configure]);
    my %flags = (cflags            => '--cflags',
                 cxxflags          => '--cxxflags',
                 ldflags           => '--ldflags',
                 ldflags_gl        => '--ldflags --use-gl',
                 ldflags_gl_images => '--ldflags --use-gl --use-images',
                 ldflags_images    => '--ldflags --use-images'
    );
    for my $flag (keys %flags) {
        my $_flags = `sh fltk-config $flags{$flag}`;
        chomp $_flags for 1 .. 3;
        $s->config_data($flag, $_flags);
    }
    $ret;
}

sub _make {    # expects to be in the top of the extracted directory
    chdir 'src';
    use Config;
    my $ret = system('gmake -n | sh') && system('make -n | sh');
    chdir '..';
    return !$ret;
}

sub _clean {    # expects to be in the top of the extracted directory
    1;
}

sub _copy_libs {
    my $s = shift;
    for my $lib ('', qw[_images _forms _gl]) {
        my $_a = sprintf '%s/working/extract/fltk-1.3.x-r%d/lib/libfltk%s.a',
            $s->base_dir, $s->config_data('revision'), $lib;
        mkdir $s->base_dir . '/working/shared';
        $s->copy_if_modified(from   => $_a,
                             to_dir => $s->base_dir . '/working/shared/lib');
    }
}

sub _copy_headers {
    my $s = shift;
    chdir sprintf('%s/working/extract/fltk-1.3.x-r%d',
                  $s->base_dir, $s->config_data('revision'));
    $s->copy_if_modified(from   => 'config.h',
                         to_dir => $s->base_dir . '/working/shared/include');
    for my $dir (qw[FL]) {
        opendir(my $dh, $dir) || die "can't opendir $dir: $!";
        $s->copy_if_modified(
                        from => "$dir/$_",
                        to => $s->base_dir . "/working/shared/include/$dir/$_"
        ) for grep { $_ =~ /\.[hH]$/ && -f "$dir/$_" } readdir($dh);
        closedir $dh;
    }
    chdir $s->base_dir;
}
1;
