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
use constant DEBUG => $ENV{'PLACK_SSI_TRACE'} ? 1 : 0;
use constant EVAL => 'Plack::App::File::SSI::__ANON__';

my $SSI_EXPRESSION_START = qr{<!--\#};
my $SSI_EXPRESSION_END = qr{-->};
my $SSI_ENDIF = qr{<!--\#endif\s*-->};

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
    my $ssi_variables;

    unless(@stat and -r $file) {
        return $self->return_403;
    }

    {
        local $env->{'file'} = $file;
        local $env->{'stat'} = \@stat;
        $ssi_variables = $self->_default_ssi_variables($env);
    }

    return [
        200,
        [
            'Content-Type' => 'text/html',
            'Content-Length' => $stat[7],
            'Last-Modified' => HTTP::Date::time2str($stat[9]),
        ],
        [
            $self->_parse_ssi_file($file, $ssi_variables),
        ],
    ];

}

sub _default_ssi_variables {
    my($self, $args) = @_;

    $args->{'stat'} ||= [stat $args->{'file'}];

    return {
        DATE_GMT => '', #HTTP::Date::time2str(...),
        DATE_LOCAL => HTTP::Date::time2str(time),
        DOCUMENT_NAME => $args->{'file'},
        DOCUMENT_URI => $args->{'REQUEST_URI'} || '',
        LAST_MODIFIED => HTTP::Date::time2str($args->{'stat'}[9]),
        QUERY_STRING_UNESCAPED => $args->{'QUERY_STRING'} || '',
    };
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
    my($self, $buf, $FH, $ssi_variables) = @_;
    my($end_of_expression, $after_expression, $value);

    until($end_of_expression = __find_and_replace(\$buf, $SSI_EXPRESSION_END)) {
        __readline(\$buf, $FH) or return ['', $buf];
    }

    $after_expression = substr $buf, $end_of_expression;

    if($buf =~ s/^\s*(\w+)//) {
        my $method = "_ssi_exp_$1";
        my $expression = substr $buf, 0, $end_of_expression;

        if($self->can($method)) {
            my @res = $self->$method($expression, $FH, $ssi_variables);
            $value = $res[0];
            $after_expression = $res[1] .$after_expression if(defined $res[1]);
        }
        else {
            $value = '<!-- unknown ssi method -->';
        }
    }

    if(!defined $value) {
        $value = '<!-- unknown ssi expression -->';
    }

    return [
        $value,
        $after_expression,
    ];
}

sub _ssi_exp_set {
    my($self, $expression, $FH, $ssi_variables) = @_;
    my $name = $expression =~ /var="([^"]+)"/ ? $1 : undef;
    my $value = $expression =~ /value="([^"]+)"/ ? $1 : '';

    if(defined $name) {
        $ssi_variables->{$name} = $value;
    }
    else {
        warn "Found SSI set expression, but no variable name ($expression)" if DEBUG;
    }

    return '';
}

sub _ssi_exp_echo {
    my($self, $expression, $FH, $ssi_variables) = @_;
    my($name) = $expression =~ /var="([^"]+)"/ ? $1 : undef;

    if(defined $name) {
        return $ssi_variables->{$name} || '';
    }

    warn "Found SSI echo expression, but no variable name ($expression)" if DEBUG;
    return '';
}

sub _ssi_exp_exec {
    my($self, $expression, $FH, $ssi_variables) = @_;
    my($cmd) = $expression =~ /cmd="([^"]+)"/ ? $1 : undef;

    if(defined $cmd) {
        return join '', qx{$cmd};
    }

    warn "Found SSI cmd expression, but no command ($expression)" if DEBUG;
    return '';
}

sub _ssi_exp_fsize {
    my($self, $expression, $FH, $ssi_variables) = @_;
    my $file = $self->_expression_to_file($expression) or return '';
    return eval { $file->stat->size } || '';
}

sub _ssi_exp_flastmod {
    my($self, $expression, $FH, $ssi_variables) = @_;
    my $file = $self->_expression_to_file($expression) or return '';
    return eval { HTTP::Date::time2str($file->stat->mtime) } || '';
}

sub _ssi_exp_include {
    my($self, $expression, $FH, $ssi_variables) = @_;
    my $file = $self->_expression_to_file($expression) or return '';
    return $self->_parse_ssi_file("$file", $ssi_variables);
}

sub _ssi_exp_if {
    my($self, $buf, $FH, $ssi_variables) = @_;
    my($end_of_expression, $after_expression, $expression);
    my $value = '';

    until($end_of_expression = __find_and_replace(\$buf, $SSI_ENDIF)) {
        __readline(\$buf, $FH) or return '', $buf;
    }

    $after_expression = substr $buf, $end_of_expression;
    $expression = ($buf =~ /expr="([^"]+)"/)[0];

    unless(defined $expression) {
        warn "Found SSI if expression, but no expression ($buf)" if DEBUG;
        return '', $after_expression;
    }

    # TODO: Add support for
    # <!--#if expr="${Sec_Nav}" -->
    # <!--#include virtual="bar.txt" -->
    # <!--#elif expr="${Pri_Nav}" -->
    # <!--#include virtual="foo.txt" -->
    # <!--#else -->
    # <!--#include virtual="article.txt" -->
    # <!--#endif -->

    warn $buf;
    warn $expression;
    warn $after_expression;

    return $value, $after_expression;
}

sub _expression_to_file {
    my($self, $expression) = @_;

    if($expression =~ /file="([^"]+)"/) {
        return Path::Class::File->new(split '/', $1);
    }
    elsif($expression =~ /virtual="([^"]+)"/) {
        return Path::Class::File->new($self->root, split '/', $1);
    }

    warn "Could not find file from SSI expression ($expression)" if DEBUG;
    return;
}

#=============================================================================
# INTERNAL FUNCTIONS

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


package # hide from CPAN
    Plack::App::File::SSI::__ANON__;

my $pkg = __PACKAGE__;

sub __eval_expr {
    my($class, $expression, $ssi_variables) = @_;

    no strict;

    CLEAR_VAR:
    for my $key (keys %{"$pkg\::"}) {
        next if($key eq '__eval_expr');
        next if($key eq 'BEGIN');
        delete ${"$pkg\::"}{$key};
    }

    ADD_VAR:
    for my $key (keys %$ssi_variables) {
        next if($key eq '__eval_expr');
        next if($key eq 'BEGIN');
        *{"$pkg\::$key"} = \$ssi_variables->{$key};
    }

    warn "eval ($expression)" if Plack::App::File::SSI::DEBUG;

    return eval $expression;
}

1;
