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
        # "print('Hello world from Javascript!');",
        # "print(2+3*4);",
        "gonzo();",
    );
    foreach my $cmd (@commands) {
        my $run = $duk->run($cmd);
        ok($run, "ran duktape [$cmd]");
    }

    done_testing;
    return 0;
}

exit main();
