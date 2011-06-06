use warnings;
use strict;
use lib qw(lib);
use Test::More;
use Plack::App::File::SSI;

plan skip_all => 'no test files' unless -d 't/file';
plan tests => 12;

my $file = Plack::App::File::SSI->new;
my $res;

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
    $res = $file->serve_path({}, 't/file/folder.png');
    isa_ok($res->[2], 'Plack::Util::IOWithPath');

    $res = $file->serve_path({}, 't/file/index.html');
    is(ref($res->[2]), 'ARRAY', 'HTML is served with serve_ssi()');
    is($res->[0], 200, '..and code 200');
    ok(1 == grep({ $_ eq 'text/html' } @{ $res->[1] }), '..and with Content-Type text/html');
    ok(1 == grep({ $_ eq 'Content-Length' } @{ $res->[1] }), '..and with Content-Lenght');
    ok(1 == grep({ $_ eq 'Last-Modified' } @{ $res->[1] }), '..and with Last-Modified');

    like($res->[2][0], qr{^<!DOCTYPE HTML}, 'parsed result contain beginning');
    like($res->[2][0], qr{</html>$}, '..and end of html file');

    TODO: {
        local $TODO = '_parse_ssi_file()';
    }
}

