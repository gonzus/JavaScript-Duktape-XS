use strict;
use warnings;

use Data::Dumper;
use Test::More;
use JavaScript::Duktape::XS;

sub main {
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");

    $duk->set('gonzo', sub { print("HOI\n"); });

    my @commands = (
        [ "'gonzo'" => 'gonzo' ],
        [ "3+4*5"   => 23 ],
        [ "true"    => 1 ],
        [ "null"    => undef ],
        [ "say('Hello world from Javascript!');" => undef ],
        [ "say(2+3*4);" => undef ],
        [ "gonzo();" => undef ],
    );
    foreach my $cmd (@commands) {
        my ($js, $expected) = @$cmd;
        my $got = $duk->eval($js);
        # printf STDERR ("EVAL [%s] => [%s]\n", $js, $got // 'undef');
        is($got, $expected, "ran duktape [$js]");
    }

    done_testing;
    return 0;
}

exit main();
