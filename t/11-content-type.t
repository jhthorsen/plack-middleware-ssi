#!/usr/bin/env perl
use warnings;
use strict;
use Plack::Middleware::SSI;
use Test::More;

my @cts = qw(
                application/xhtml+xml
                text/html
                application/xml
                application/xhtml
);

my @bad_cts = qw(
                    app/xhtml+xml
                    txt/htm
                    app/mlx
                    app/hxtml
);

foreach (@cts) {
    ok Plack::Middleware::SSI::_matching_content_type($_), "Content type $_ matches";
}

foreach (@bad_cts) {
    ok ! Plack::Middleware::SSI::_matching_content_type($_), "Content type $_ matches";
}
done_testing;
