use inc::Module::Install;

name q(Plack-App-File-SSI);
all_from q(lib/Plack/App/File/SSI.pm);

requires q(Plack) => 0.99;
requires q(base) => 2.14;

test_requires q(Test::More) => 0.98;

bugtracker q(http://rt.cpan.org/NoAuth/Bugs.html?Dist=Plack-App-File-SSI);
homepage q(http://search.cpan.org/dist/Plack-App-File-SSI);
repository q(git://github.com///github.com/);

# install_script glob('bin/*');
auto_install;
WriteAll;
