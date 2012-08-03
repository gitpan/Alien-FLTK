use strict;
use warnings;
use inc::Module::Build::FLTK;
$|++;
my $builder =
    inc::Module::Build::FLTK->new(
                 module_name    => 'Alien::FLTK',
                 license        => 'artistic_2',
                 build_requires => {'Archive::Extract' => 0,
                                    Config             => 0,
                                    'Digest::MD5'      => 0,
                                    'File::Fetch'      => 0
                 },
                 configure_requires => {'Module::Build'  => 0.40},
                 requires           => {'File::ShareDir' => 0},
                 add_to_cleanup => ['working/extract/*', '*.a', '*.o', '*.h'],
                 share_dir      => 'working/shared',
                 recursive_test_files => 1,
                 create_license       => 1,
                 create_readme        => 1
    );
#
exit $builder->create_build_script();
