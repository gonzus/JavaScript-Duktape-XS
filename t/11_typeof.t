use strict;
use warnings;

use Ref::Util qw/ is_scalarref /;
use Test::More;
use JavaScript::Duktape::XS;

sub test_typeof {
    my %data = (
        'undefined' => [ \'DO NOT SET VALUE' ],
        'null'      => [ undef ],
        # 'boolean'   => [ 0, 1 ],
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

sub main {
    test_typeof();
    done_testing;

    return 0;
}

exit main();
