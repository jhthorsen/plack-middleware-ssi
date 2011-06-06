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
use Path::Class::File;
use HTTP::Date;
use base 'Plack::App::File';

=head1 METHODS

=head2 serve_path

Will do the same as L<Plack::App::File/serve_path>, unless for files with
mimetype "text/html": Will use L</serve_ssi> then.

=cut

sub serve_path {
    my($self, $env, $file) = @_;
    my $content_type = $self->content_type || Plack::MIME->mime_type($file) || 'text/plain';

    if($content_type eq 'text/html') {
        return $self->serve_ssi($env, $file);
    }

    return $self->SUPER::serve_path($env, $file);
}

=head2 serve_ssi

    [$status, $headers, [$text]] = $self->serve_ssi($file);

Will parse the file and search for SSI statements.

=cut

sub serve_ssi {
    my($self, $env, $file) = @_;
    my @stat = stat $file;

    unless(@stat and -r $file) {
        return $self->return_403;
    }

    return [
        200,
        [
            'Content-Type' => 'text/html',
            'Content-Length' => $stat[7],
            'Last-Modified' => HTTP::Date::time2str($stat[9]),
        ],
        [
            $self->_parse_ssi_file($file, {}),
        ],
    ];

}

sub _parse_ssi_file {
    return 'TODO';
}

=head1 COPYRIGHT & LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Jan Henning Thorsen C<< jhthorsen at cpan.org >>

=cut

1;
