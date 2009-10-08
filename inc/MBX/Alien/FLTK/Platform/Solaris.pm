package MBX::Alien::FLTK::Platform::Solaris;
{
    use strict;
    use warnings;
    use Carp qw[];
    use Config qw[%Config];
    use lib qw[.. ../../../..];
    use MBX::Alien::FLTK::Utility
        qw[_o _a _dir _rel _abs find_h find_lib can_run];
    use MBX::Alien::FLTK;
    use base 'MBX::Alien::FLTK::Platform::Unix';
    $|++;

    sub configure {
        my ($self) = @_;
        $self->SUPER::configure();    # Get basic config data
        print "Gathering Solaris specific configuration data...\n";
        print "(Not using $uname scandir emulation function.)\n";
        $self->notes('config')->{'HAVE_SCANDIR'} = undef;
        return 1;
    }
    1;
}

=pod

=head1 Author

Sanko Robinson <sanko@cpan.org> - http://sankorobinson.com/

CPAN ID: SANKO

=head1 License and Legal

Copyright (C) 2009 by Sanko Robinson E<lt>sanko@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it under
the terms of The Artistic License 2.0. See the F<LICENSE> file included with
this distribution or http://www.perlfoundation.org/artistic_license_2_0.  For
clarification, see http://www.perlfoundation.org/artistic_2_0_notes.

When separated from the distribution, all POD documentation is covered by the
Creative Commons Attribution-Share Alike 3.0 License. See
http://creativecommons.org/licenses/by-sa/3.0/us/legalcode.  For
clarification, see http://creativecommons.org/licenses/by-sa/3.0/us/.

=for git $Id: Solaris.pm af23f6c 2009-09-01 14:10:31Z sanko@cpan.org $

=cut