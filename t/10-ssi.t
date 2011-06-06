use warnings;
use strict;
use lib qw(lib);
use Test::More;
use Plack::App::File::SSI;

plan skip_all => 'no test files' unless -d 't/file';
plan tests => 37;

my $file = Plack::App::File::SSI->new(root => 't/file');
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
        Plack::App::File::SSI::__ANON__->__eval_expr('$foo', { foo => 123 }),
        123,
        'eval foo to 123'
    );

    no strict 'refs';
    is(${"Plack::App::File::SSI::__ANON__::foo"}, 123, 'foo variable is part of __ANON__ package');
    Plack::App::File::SSI::__ANON__->__eval_expr('1', { bar => 123 }),
    is(${"Plack::App::File::SSI::__ANON__::foo"}, undef, 'foo variable is removed from __ANON__ package');
}

{
    $res = $file->_parse_ssi_expression('%&]', dummy_filehandle(), \%data);
    is($res->[0], '<!-- unknown ssi expression -->', 'SSI unknown expression: return comment');
    $res = $file->_parse_ssi_expression('invalid expression', dummy_filehandle(), \%data);
    is($res->[0], '<!-- unknown ssi method -->', 'SSI invalid expression: return comment');
    is($res->[1], 'after', 'SSI invalid expression: got remaining buffer');
}

{
    $res = $file->_parse_ssi_expression('set var="foo" value="123"', dummy_filehandle(), \%data);
    is($res->[0], '', 'SSI set: will not result in any value');
    is($res->[1], 'after', 'SSI set: got remaining buffer');
    is($data{'foo'}, 123, 'SSI set: variable foo was found in expression');

    $res = $file->_parse_ssi_expression('echo var="foo"', dummy_filehandle(), { foo => 123 });
    is($res->[0], '123', 'SSI echo: return 123');
    is($res->[1], 'after', 'SSI echo: got remaining buffer');

    $res = $file->_parse_ssi_expression('echo var="foo"', dummy_filehandle(), {});
    is($res->[0], '', 'SSI echo: return empty string');

    $res = $file->_parse_ssi_expression('fsize file="t/file/readline.txt"', dummy_filehandle(), {});
    is($res->[0], 23, 'SSI fsize: return 23');

    $res = $file->_parse_ssi_expression('flastmod file="t/file/readline.txt"', dummy_filehandle(), {});
    like($res->[0], qr{GMT$}, 'SSI flastmod: return time string');

    $res = $file->_parse_ssi_expression('include virtual="readline.txt"', dummy_filehandle(), {});
    is($res->[0], "first line\nsecond line\n", 'SSI include: return readline.txt');
}

TODO: {
    local $TODO = 'cannot parse if/else yet';
    $res = $file->_parse_ssi_expression('if expr="$FOO"', elif_else_filehandle(), {});

    is($res->[0], '', 'SSI if/elif/else ...');
    is($res->[1], 'some text', 'SSI if/elif/else ...');
}

SKIP: {
    skip 'cannot execute "ls"', 1 if system 'ls >/dev/null';
    $res = $file->_parse_ssi_expression('exec cmd="ls"', dummy_filehandle(), {});
    like($res->[0], qr{\w}, 'SSI cmd: return directory list');
}

{
    my $vars = $file->_default_ssi_variables({
                   file => 't/file/readline.txt',
                   REQUEST_URI => 'http://foo.com/bar.html',
                   QUERY_STRING => 'a=42&b=24',
               });

    {
        local $TODO = 'not sure how to get gmtime...';
        like($vars->{'DATE_GMT'}, qr{\d}, "_default_ssi_variables has DATE_GMT $vars->{'DATE_GMT'}");
    }

    like($vars->{'DATE_LOCAL'}, qr{\d}, "_default_ssi_variables has DATE_LOCAL $vars->{'DATE_LOCAL'}");
    is($vars->{'DOCUMENT_NAME'}, 't/file/readline.txt', '_default_ssi_variables has DOCUMENT_NAME');
    is($vars->{'DOCUMENT_URI'}, 'http://foo.com/bar.html', '_default_ssi_variables has DOCUMENT_URI');
    like($vars->{'LAST_MODIFIED'}, qr{\d}, "_default_ssi_variables has LAST_MODIFIED $vars->{'LAST_MODIFIED'}");
    is($vars->{'QUERY_STRING_UNESCAPED'}, 'a=42&b=24', '_default_ssi_variables has QUERY_STRING_UNESCAPED');
}

{
    $res = $file->serve_path({}, 't/file/folder.png');
    isa_ok($res->[2], 'Plack::Util::IOWithPath');

    $res = $file->serve_path({}, 't/file/index.html');
    is(ref($res->[2]), 'ARRAY', 'HTML is served with serve_ssi()');
    is($res->[0], 200, '..and code 200');
    ok(1 == grep({ $_ eq 'text/html' } @{ $res->[1] }), '..and with Content-Type text/html');
    ok(1 == grep({ $_ eq 'Content-Length' } @{ $res->[1] }), '..and with Content-Lenght');
    ok(1 == grep({ $_ eq 'Last-Modified' } @{ $res->[1] }), '..and with Last-Modified');

    like($res->[2][0], qr{^<!DOCTYPE HTML}, 'parsed result contain beginning...');
    like($res->[2][0], qr{</html>$}, '..and end of html file');
    like($res->[2][0], qr{DOCUMENT_NAME=t/file/index.html}, 'index.html contains DOCUMENT_NAME');
}

sub dummy_filehandle {
    my $buf = shift || "-->after";
    open my $FH, '<', \$buf;
    return $FH;
}

sub elif_else_filehandle {
    my $buf = <<'IF_ELIF_ELSE';
-->
FOO
<!--#elif expr="${BAR}" -->
BAR
<!--#else -->
ELSE
<!--#endif -->
after
IF_ELIF_ELSE

    open my $FH, '<', \$buf;
    return $FH;
}
