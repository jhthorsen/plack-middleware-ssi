use warnings;
use strict;
use lib qw(lib);
use Test::More;
use Plack::App::File::SSI;

plan skip_all => 'no test files' unless -d 't/file';
plan tests => 18;

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
}

sub dummy_filehandle {
    my $buf = shift || "-->after";
    open my $FH, '<', \$buf;
    return $FH;
}
