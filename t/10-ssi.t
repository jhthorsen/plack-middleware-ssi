use warnings;
use strict;
use lib qw(lib);
use Test::More;
use Plack::App::File::SSI;

plan skip_all => 'no test files' unless -d 't/file';
plan tests => 31;

my $file = Plack::App::File::SSI->new(root => 't/file');
my $TIME_RE = qr{\w+, \d+-\w+-\d+ [\d:]+};
my($res, %data);

{
    open my $FH, '<', 't/file/readline.txt';
    my $buf = '';
    ok(Plack::App::File::SSI::__readline(\$buf, $FH), '__readline() return true');
    is($buf, "first line\n", '__readline return one line');

    Plack::App::File::SSI::__readline(\$buf, $FH); # second line...
    ok(!Plack::App::File::SSI::__readline(\$buf, $FH), '__readline() return false after second line');
    is(length($buf), 23, 'all data is read');
}

{
    is(
        Plack::App::File::SSI::__ANON__->__eval_condition('$foo', { foo => 123 }),
        123,
        'eval foo to 123'
    );

    no strict 'refs';
    is(${"Plack::App::File::SSI::__ANON__::foo"}, 123, 'foo variable is part of __ANON__ package');
    Plack::App::File::SSI::__ANON__->__eval_condition('$bar', { bar => 123 }),
    is(${"Plack::App::File::SSI::__ANON__::foo"}, undef, 'foo variable is removed from __ANON__ package');
}

{
    $res = $file->parse_ssi_from_filehandle(ssi_fh('invalid expression'), \%data);
    is($res, 'B[an error occurred while processing this directive]A', 'SSI invalid expression: return comment');

    $res = $file->parse_ssi_from_filehandle(ssi_fh('set var="foo" value="123"'), \%data);
    is($res, 'BA', 'SSI set: will not result in any value');
    is($data{'foo'}, 123, 'SSI set: variable foo was found in expression');

    $res = $file->parse_ssi_from_filehandle(ssi_fh('echo var="foo"'), { foo => 123 });
    is($res, 'B123A', 'SSI echo: return 123');

    $res = $file->parse_ssi_from_filehandle(ssi_fh('echo var="foo"'), {});
    is($res, 'BA', 'SSI echo: return empty string');

    $res = $file->parse_ssi_from_filehandle(ssi_fh('fsize file="t/file/readline.txt"'), {});
    is($res, "B23A", 'SSI fsize: return 23');

    $res = $file->parse_ssi_from_filehandle(ssi_fh('flastmod file="t/file/readline.txt"'), {});
    like($res, qr"^B$TIME_RE \w+A$", 'SSI flastmod: return time string');

    $res = $file->parse_ssi_from_filehandle(ssi_fh('include virtual="readline.txt"'), {});
    is($res, "Bfirst line\nsecond line\nA", 'SSI include: return readline.txt');

    $res = $file->parse_ssi_from_filehandle(if_elif_else_filehandle(), { FOO => 42 });
    is($res, "\nELSE\nafter\n", 'SSI if/elif/else: ELSE');
    $res = $file->parse_ssi_from_filehandle(if_elif_else_filehandle(), { B => 2 });
    is($res, "\nELIF\nafter\n", 'SSI if/elif/else: ELIF');
    $res = $file->parse_ssi_from_filehandle(if_elif_else_filehandle(), { A => 1 });
    is($res, "\nIF\nafter\n", 'SSI if/elif/else: IF');
}

SKIP: {
    skip 'cannot execute "ls"', 1 if system 'ls >/dev/null';
    $res = $file->parse_ssi_from_filehandle(ssi_fh('exec cmd="ls"'), {});
    like($res, qr{\w}, 'SSI cmd: return directory list');
}

{
    $res = $file->serve_path({}, 't/file/folder.png');
    isa_ok($res->[2], 'Plack::Util::IOWithPath');
}

{
    $res = $file->serve_path({}, 't/file/index.html');
    is(ref($res->[2]), 'ARRAY', 'HTML is served with serve_ssi()');
    is($res->[0], 200, '..and code 200');
    ok(1 == grep({ $_ eq 'text/html' } @{ $res->[1] }), '..and with Content-Type text/html');
    ok(1 == grep({ $_ eq 'Content-Length' } @{ $res->[1] }), '..and with Content-Lenght');
    ok(1 == grep({ $_ eq 'Last-Modified' } @{ $res->[1] }), '..and with Last-Modified');

    like($res->[2][0], qr{^<!DOCTYPE HTML}, 'parsed result contain beginning...');
    like($res->[2][0], qr{</html>$}, '..and end of html file');
    like($res->[2][0], qr{DOCUMENT_NAME=index.html}, 'index.html contains DOCUMENT_NAME');
    like($res->[2][0], qr{DATE_GMT=$TIME_RE GMT}, 'index.html contains DATE_GMT');
    like($res->[2][0], qr{DATE_LOCAL=$TIME_RE \w+}, 'index.html contains DATE_LOCAL');
    like($res->[2][0], qr{LAST_MODIFIED=$TIME_RE \w+}, 'index.html contains LAST_MODIFIED');
}

sub ssi_fh {
    my $buf = 'B<!--#' .shift(@_) .' -->A';
    open my $FH, '<', \$buf;
    return $FH;
}

sub if_elif_else_filehandle {
    my $buf = <<'IF_ELIF_ELSE';
<!--#if expr="${A}" -->
IF
<!--#elif expr="${B}" -->
ELIF
<!--#else -->
ELSE
<!--#endif -->after
IF_ELIF_ELSE

    open my $FH, '<', \$buf;
    return $FH;
}
