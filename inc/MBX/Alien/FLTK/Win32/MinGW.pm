package MBX::Alien::FLTK::Win32::MinGW;
{
    use strict;
    use warnings;
    use lib '../../..';
    use base 'MBX::Alien::FLTK::Win32';

    #
    sub version { return qx[gcc -dumpversion]; }
}
1;
__END__

$Id: MinGW.pm b07aa6c 2009-08-22 05:23:41Z sanko@cpan.org $
