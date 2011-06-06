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

my $SSI_EXPRESSION_START = qr{<!--\#};
my $SSI_EXPRESSION_END = qr{-->};

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
    my($self, $file, $ssi_variables) = @_;
    my($comment, $buf);
    my $text = '';

    open my $FH, '<:raw', $file or return $self->return_403;
    $buf = readline $FH;

    while(defined $buf) {
        if(my $pos = __find_and_replace(\$buf, $SSI_EXPRESSION_START)) {
            my $before_expression = substr $buf, 0, $pos;
            my $expression = substr $buf, $pos;
            my $value_buf = $self->_parse_ssi_expression($expression, $FH, {%$ssi_variables});

            $text .= $before_expression;
            $text .= $value_buf->[0];
            $buf = $value_buf->[1];
        }
        else {
            $text .= $buf;
            $buf = readline $FH;
        }
    }

    return $text;
}

sub _parse_ssi_expression {
    my($self, $buf, $FH, $args) = @_;
    my($end_of_expression, $after_expression, $value);

    until($end_of_expression = __find_and_replace(\$buf, $SSI_EXPRESSION_END)) {
        __readline(\$buf, $FH) or return ['', $buf];
    }

    $after_expression = substr $buf, $end_of_expression;

    return ['', $after_expression];
}

sub __readline {
    my($buf, $FH) = @_;
    my $tmp = readline $FH;
    return unless(defined $tmp);
    $$buf .= $tmp;
    return 1;
}

sub __find_and_replace {
    my($buf, $re) = @_;
    return $-[0] || '0e0' if($$buf =~ s/$re//);
    return;
}

=head1 COPYRIGHT & LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Jan Henning Thorsen C<< jhthorsen at cpan.org >>

=cut

1;
