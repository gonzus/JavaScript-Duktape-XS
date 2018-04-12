use strict;
use warnings;

use Data::Dumper;
use Time::HiRes;
use Test::More;
use JavaScript::Duktape::XS;

sub test_stats {
    foreach my $gather_stats (@{[ undef, 0, 1 ]}) {
        my $duk;
        if (!defined $gather_stats) {
            $duk = JavaScript::Duktape::XS->new();
            ok($duk, "created JavaScript::Duktape::XS object with default options");
        } else {
            $duk = JavaScript::Duktape::XS->new({gather_stats => $gather_stats});
            ok($duk, "created JavaScript::Duktape::XS object with gather_stats => $gather_stats");
        }

        for (1..3) {
            my $got = $duk->eval('timestamp_ms()');
            my $stats = $duk->get_stats();
            foreach my $key (qw/ compile run /) {
                if (!$gather_stats) {
                    ok(!exists $stats->{$key}, "key $key does not exist in stats");
                }
                else {
                    ok(exists $stats->{$key}, "key $key exists in stats");
                    ok($stats->{$key} > 0, "key $key has a positive value in stats");
                }
            }
        }
    }
}

sub main {
    test_stats();
    done_testing;
    return 0;
}

exit main();
