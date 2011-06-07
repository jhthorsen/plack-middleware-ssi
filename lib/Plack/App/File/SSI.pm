package Plack::App::File::SSI;

=head1 NAME

Plack::App::File::SSI - Extension of Plack::App::File to serve SSI

=head1 DESCRIPTION

Will try to handle HTML with server side include directives as well as doing
what L<Plack::App::File> does for "regular files".

=head1 SUPPORTED SSI DIRECTIVES

See L<http://httpd.apache.org/docs/2.0/mod/mod_include.html>,
L<http://httpd.apache.org/docs/2.0/howto/ssi.html> or
L<http://en.wikipedia.org/wiki/Server_Side_Includes> for more details.

=head2 set

    <!--#set var="SOME_VAR" value="123" -->

=head2 echo

    <!--#echo var="SOME_VAR" -->

=head2 exec

    <!--#exec cmd="ls -l" -->

=head2 flastmod

    <!--#flastmod virtual="index.html" -->

=head2 fsize

    <!--#fsize file="script.pl" -->

=head2 include

    <!--#include virtual="relative/to/root.txt" -->
    <!--#include file="/path/to/file/on/disk.txt" -->

=head1 SYNOPSIS

See L<Plack::App::File>.

=cut

use strict;
use warnings;
use Path::Class::File;
use HTTP::Date;
use base 'Plack::App::File';
use constant DEBUG => $ENV{'PLACK_SSI_TRACE'} ? 1 : 0;

my $SSI_EXPRESSION_START = qr{<!--\#};
my $SSI_EXPRESSION_END = qr{\s*-->};
my $ANON = 'Plack::App::File::SSI::__ANON__';
my $SKIP = '__SKIP__' . rand 1000;

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

    [$status, $headers, [$text]] = $self->serve_ssi($env, $file);

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
        $ssi_variables = $self->default_ssi_variables($env);
    }

    open my $FH, '<:raw', $file or return $self->return_403;

    return [
        200,
        [
            'Content-Type' => 'text/html',
            'Content-Length' => $stat[7],
            'Last-Modified' => HTTP::Date::time2str($stat[9]),
        ],
        [
            $self->parse_ssi_from_filehandle($FH, $ssi_variables),
        ],
    ];
}

=head2 default_ssi_variables

Returns a hash-ref with default SSI variables which can be used inside

    <!--#echo var="..." -->

=over 4

=item DATE_LOCAL

=item DOCUMENT_NAME

=item DOCUMENT_URI

=item LAST_MODIFIED

=item QUERY_STRING_UNESCAPED

=back

=cut

sub default_ssi_variables {
    my($self, $args) = @_;

    $args->{'stat'} ||= [stat $args->{'file'}];

    return {
        #DATE_GMT => HTTP::Date::time2str(...), <-- TODO
        DATE_LOCAL => HTTP::Date::time2str(time),
        DOCUMENT_NAME => $args->{'file'},
        DOCUMENT_URI => $args->{'REQUEST_URI'} || '',
        LAST_MODIFIED => HTTP::Date::time2str($args->{'stat'}[9]),
        QUERY_STRING_UNESCAPED => $args->{'QUERY_STRING'} || '',
    };
}

=head2 parse_ssi_from_filehandle

    $text = $self->parse_ssi_from_filehandle($FH, \%variables);

Will return the content from C<$FH> as a plain string, where all SSI
directives are expanded. All expression which could not be expanded
will be replaced with "<!-- unknown ssi expression -->".

=cut

sub parse_ssi_from_filehandle {
    my($self, $FH, $ssi_variables) = @_;
    my $buf = readline $FH;
    my $text = '';

    while(defined $buf) {
        if(my $pos = __find_and_replace(\$buf, $SSI_EXPRESSION_START)) {
            my($expression, $expression_end_pos, $method, $value);

            until($expression_end_pos = __find_and_replace(\$buf, $SSI_EXPRESSION_END)) {
                __readline(\$buf, $FH) or last;
            }

            $text .= substr $buf, 0, $pos unless($ssi_variables->{$SKIP});
            $expression = substr $buf, $pos, $expression_end_pos;
            $buf = substr $buf, $expression_end_pos; # after expression
            $method = $expression =~ s/^(\w+)// ? "_ssi_exp_$1" : '_ssi_exp_unknown';

            if($self->can($method)) {
                $value = $self->$method($expression, $ssi_variables);
            }
            else {
                $value = '<!-- unknown ssi expression -->';
            }

            $text .= $value unless($ssi_variables->{$SKIP});
        }
        else {
            $text .= $buf unless($ssi_variables->{$SKIP});
            $buf = readline $FH;
        }
    }

    return $text;
}

#=============================================================================
# SSI expression parsers

sub _ssi_exp_set {
    my($self, $expression, $ssi_variables) = @_;
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
    my($self, $expression, $ssi_variables) = @_;
    my($name) = $expression =~ /var="([^"]+)"/ ? $1 : undef;

    if(defined $name) {
        return $ssi_variables->{$name} || '';
    }

    warn "Found SSI echo expression, but no variable name ($expression)" if DEBUG;
    return '';
}

sub _ssi_exp_exec {
    my($self, $expression, $ssi_variables) = @_;
    my($cmd) = $expression =~ /cmd="([^"]+)"/ ? $1 : undef;

    if(defined $cmd) {
        return join '', qx{$cmd};
    }

    warn "Found SSI cmd expression, but no command ($expression)" if DEBUG;
    return '';
}

sub _ssi_exp_fsize {
    my($self, $expression, $ssi_variables) = @_;
    my $file = $self->_expression_to_file($expression) or return '';
    return eval { $file->stat->size } || '';
}

sub _ssi_exp_flastmod {
    my($self, $expression, $ssi_variables) = @_;
    my $file = $self->_expression_to_file($expression) or return '';
    return eval { HTTP::Date::time2str($file->stat->mtime) } || '';
}

sub _ssi_exp_include {
    my($self, $expression, $ssi_variables) = @_;
    my $file = $self->_expression_to_file($expression) or return '';
    return $self->parse_ssi_from_filehandle($file->openr, $ssi_variables);
}

sub _ssi_exp_if { $_[0]->_evaluate_if_elif_else($_[1], $_[2]) }
sub _ssi_exp_elif { $_[0]->_evaluate_if_elif_else($_[1], $_[2]) }
sub _ssi_exp_else { $_[0]->_evaluate_if_elif_else('expr="1"', $_[2]) }

sub _evaluate_if_elif_else {
    my($self, $expression, $ssi_variables) = @_;
    my $condition = $expression =~ /expr="([^"]+)"/ ? $1 : undef;

    unless(defined $condition) {
        warn "Found SSI if expression, but no expression ($expression)" if DEBUG;
        return '';
    }

    if(defined $ssi_variables->{$SKIP} and $ssi_variables->{$SKIP} != 1) {
        $ssi_variables->{$SKIP} = 2; # previously true
    }
    elsif($ANON->__eval_condition($condition, $ssi_variables)) {
        $ssi_variables->{$SKIP} = 0; # true
    }
    else {
        $ssi_variables->{$SKIP} = 1; # false
    }

    return '';
}

sub _ssi_exp_endif {
    my($self, $expression, $ssi_variables) = @_;
    delete $ssi_variables->{$SKIP};
    return '';
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

sub __eval_condition {
    my($class, $expression, $ssi_variables) = @_;

    no strict;

    if($expression =~ /\$/) { # 1 is always true. do not need variables to figure that out
        for my $key (keys %{"$pkg\::"}) {
            next if($key eq '__eval_condition');
            delete ${"$pkg\::"}{$key};
        }
        for my $key (keys %$ssi_variables) {
            next if($key eq '__eval_condition');
            *{"$pkg\::$key"} = \$ssi_variables->{$key};
        }
    }

    warn "eval ($expression)" if Plack::App::File::SSI::DEBUG;

    if(my $res = eval $expression) {
        return $res;
    }
    if($@) {
        warn $@;
    }

    return 0;
}

1;
