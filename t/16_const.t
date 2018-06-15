use strict;
use warnings;

use Data::Dumper;
use Time::HiRes;
use Test::More;
use JavaScript::Duktape::XS;

sub test_const {
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");
    my $num = 42;
    my $got;

    $got = $duk->eval("const number = $num; number;");
    is($got, $num, "compiled const");
    $got = $duk->get('number');
    is($got, $num, "and const has correct value");

    # $got = $duk->eval('const webpack = (options, callback) => { const gonzo = 11; };');
    $got = $duk->eval('const webpack = function(options, callback) { const gonzo = 11; }; number');
    is($got, $num, "compiled funny");
}

sub main {
    test_const();
    done_testing;
    return 0;
}

exit main();
