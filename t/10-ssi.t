use warnings;
use strict;
use lib qw(lib);
use Test::More;
use Plack::App::File::SSI;

plan skip_all => 'no test files' unless -d 't/file';
plan tests => 7;

my $file = Plack::App::File::SSI->new;
my $res;

{
    $res = $file->serve_path({}, 't/file/folder.png');
    isa_ok($res->[2], 'Plack::Util::IOWithPath');

    $res = $file->serve_path({}, 't/file/index.html');
    is(ref($res->[2]), 'ARRAY', 'HTML is served with serve_ssi()');
    is($res->[0], 200, '..and code 200');
    ok(1 == grep({ $_ eq 'text/html' } @{ $res->[1] }), '..and with Content-Type text/html');
    ok(1 == grep({ $_ eq 'Content-Length' } @{ $res->[1] }), '..and with Content-Lenght');
    ok(1 == grep({ $_ eq 'Last-Modified' } @{ $res->[1] }), '..and with Last-Modified');

    TODO: {
        local $TODO = '_parse_ssi_file()';
        is($res->[2][0], 'TODO', '_parse_ssi_file() parsed file');
    }
}

