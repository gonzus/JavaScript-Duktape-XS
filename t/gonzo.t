use strict;
use warnings;

use Devel::Peek;
use Data::Dumper;
use Test::More;
use JavaScript::Duktape::XS;

sub test_simple {
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");

    my %values = (
        foo => "2+3*4",
        'aref' => [2,3,4],
        'aref aref' => [2, [3,4], 5 ],
        'href' => { foo => 1 },
        'href' => { foo => [1,2,[3,4,5]] },
        'aref href' => [2, { foo => 1 } ],
        'href aref' => { foo => [2] },
        'aref href' => [{ 1 => 2 }],
        'aref large' => [2, 4, [ 1, 3], [ [5, 7], 9 ] ],
        'href large' => { 'one' => [ 1, 2, { foo => 'bar'} ], 'two' => { baz => [3, 2]} },
        'gonzo' => sub { print("HOI\n"); },
    );
    foreach my $name (sort keys %values) {
        my $expected = $values{$name};
        $duk->set($name, $expected);
        my $got = $duk->get($name);
        is_deeply($got, $expected, "set and got [$name]")
            or printf STDERR ("%s", Dumper({got => $got, expected => $expected}));
    }
}

sub test_set_get {
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");

    my %values = (
        'undef'  => undef,
        '0' => 0,
        '1' => 1,
        '0.0' => 0.0,
        'pi' => 3.1416,
        'empty'  => '',
        'string'  => 'gonzo',
        'aref empty' => [],
        'aref ints' => [5, 6, 7],
        'aref mixed' => [1, 0, 'gonzo'],
        'href empty' => {},
        'href simple' => { 'one' => 1, 'two' => 2 },
        'gonzo' => sub { print("HOI\n"); },
    );
    foreach my $name (sort keys %values) {
        my $expected = $values{$name};
        $duk->set($name, $expected);
        my $got = $duk->get($name);
        is_deeply($got, $expected, "set and got [$name]")
            or printf STDERR ("%s", Dumper({got => $got, expected => $expected}));
    }
}

sub test_eval {
    my $duk = JavaScript::Duktape::XS->new();
    ok($duk, "created JavaScript::Duktape::XS object");

    $duk->set('gonzo' => sub { printf("HOI [%s]\n", join(",", map +(defined $_ ? $_ : "UNDEF"), @_)); });
    my @commands = (
        [ "'gonzo'" => 'gonzo' ],
        [ "3+4*5"   => 23 ],
        [ "true"    => 1 ],
        [ "null"    => undef ],
        [ "say('Hello world from Javascript!');" => undef ],
        [ "say(2+3*4);" => undef ],
        [ 'gonzo();' => undef ],
        [ 'gonzo(1);' => undef ],
        [ 'gonzo("a", "b");' => undef ],
        [ 'gonzo("a", 1, null, "b");' => undef ],
    );
    foreach my $cmd (@commands) {
        my ($js, $expected) = @$cmd;
        my $got = $duk->eval($js);
        is_deeply($got, $expected, "eval [$js]");
    }
}

sub main {
    test_simple();
    test_set_get();
    test_eval();
    done_testing;
    return 0;
}

exit main();
