use strict;
use warnings;

use Devel::Peek;
use Data::Dumper;
use Test::More;
use JavaScript::Duktape::XS;

sub test_set_get {
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");

    my %values = (
        # 'gonzo' => sub { print("HOI\n"); },
        # 'nico'  => 11,
        'sofi'  => [ 0, 1, 2 ],
    );
    foreach my $name (sort keys %values) {
        my $expected = $values{$name};
        printf STDERR ("==== WHAT WE EXPECT =====\n");
        Dump($expected);
        # printf STDERR ("BEFORE %s", Dumper($expected));
        $duk->set($name, $expected);
        # printf STDERR ("AFTER SET %s", Dumper($expected));
        my $got = $duk->get($name);
        printf STDERR ("==== WHAT WE GOT =====\n");
        Dump($got);
        # printf STDERR ("AFTER GET %s", Dumper($expected));
        # printf STDERR ("GET [%s] = %s", $name, Dumper($got));
        is($got, $expected, "set and got [$name]")
            or printf STDERR ("%s", Dumper({got => $got, expected => $expected}));
    }
}

sub test_eval {
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");

    $duk->set('gonzo' => sub { print("HOI\n"); });
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
        printf STDERR ("EVAL [%s] => [%s]\n", $js, $got // 'undef');
        is($got, $expected, "eval [$js]");
    }
}

sub main {
    test_set_get();
    test_eval();
    done_testing;
    return 0;
}

exit main();
