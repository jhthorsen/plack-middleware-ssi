use inc::Module::Install;

name q(Plack-App-File-SSI);
all_from q(lib/Plack/App/File/SSI.pm);

requires q(HTTP::Date) => 5.831;
requires q(Path::Class::File) => 0.23;
requires q(Plack) => 0.99;

test_requires q(Test::More) => 0.98;

bugtracker q(http://rt.cpan.org/NoAuth/Bugs.html?Dist=Plack-App-File-SSI);
homepage q(http://search.cpan.org/dist/Plack-App-File-SSI);
repository q(origin);

# install_script glob('bin/*');
auto_install;
WriteAll;
