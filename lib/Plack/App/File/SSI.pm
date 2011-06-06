package Plack::App::File::SSI;

=head1 NAME

Plack::App::File::SSI - Extension of Plack::App::File to serve SSI

=head1 DESCRIPTION

Will try to handle HTML server side include files as well as doing
what L<Plack::App::File> does for "regular files".

=head1 SYNOPSIS

See L<Plack::App::File>.

=cut

use strict;
use warnings;
use base 'Plack::App::File';

=head1 METHODS

=head2 serve_path

=cut

sub serve_path {
}

=head1 COPYRIGHT & LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Jan Henning Thorsen C<< jhthorsen at cpan.org >>

=cut

1;
