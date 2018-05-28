use strict;
use warnings;

use Ref::Util qw/ is_scalarref /;
use Test::More;
use JavaScript::Duktape::XS;

sub test_typeof {
    # boolean is tested separately on test_typeof_boolean()
    my %data = (
        'undefined' => [ \'DO NOT SET VALUE' ],
        'null'      => [ undef ],
        'number'    => [ 11, 3.1415 ],
        'string'    => [ '', 'gonzo' ],
        'object'    => [ [], [1, 2, 3], {}, { foo => 1, bar => 2 } ],
    );
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");

    foreach my $type (sort keys %data) {
        my $name = "var_$type";
        my $values = $data{$type};
        foreach my $value (@$values) {
            $duk->set($name, $value) unless is_scalarref($value);
            my $got = $duk->typeof($name);
            is($got, $type, "got correct typeof for $type");
        }
    }
}

sub test_typeof_boolean {
    my $js = <<JS;
var var_true      = true;
var var_false     = false;
var var_Boolean_1 = Boolean(1);
var var_Boolean_0 = Boolean(0);
JS
    my @booleans = qw/ var_true var_false var_Boolean_1 var_Boolean_0 /;
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");
    $duk->eval($js);

    my $type = 'boolean';
    foreach my $boolean (@booleans) {
        my $got = $duk->typeof($boolean);
        is($got, $type, "got correct typeof for $type");
    }
}

sub main {
    test_typeof();
    test_typeof_boolean();
    done_testing;

    return 0;
}

exit main();
