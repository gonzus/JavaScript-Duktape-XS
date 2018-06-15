use strict;
use warnings;

use Data::Dumper;
use Time::HiRes;
use Test::More;

my $CLASS = 'JavaScript::Duktape::XS';

sub test_const {
    my $vm = $CLASS->new();
    ok($vm, "created $CLASS object");

    my $num = 42;
    my $got;

    $got = $vm->eval("const number = $num; number;");
    is($got, $num, "compiled const");
    $got = $vm->get('number');
    is($got, $num, "and const has correct value");

    # $got = $vm->eval('const webpack = (options, callback) => { const gonzo = 11; };');
    $got = $vm->eval('const webpack = function(options, callback) { const gonzo = 11; }; number');
    is($got, $num, "compiled funny");
}

sub main {
    use_ok($CLASS);

    test_const();
    done_testing;
    return 0;
}

exit main();
