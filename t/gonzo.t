use strict;
use warnings;

use Data::Dumper;
use Test::More;
use JavaScript::Duktape::XS;

my $duk = JavaScript::Duktape::XS->new();
ok($duk, "created JavaScript::Duktape::XS object");

ok($duk->run(), "ran duktape");

done_testing;
