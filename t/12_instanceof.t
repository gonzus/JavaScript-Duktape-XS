use strict;
use warnings;

use Test::More;

my $CLASS = 'JavaScript::Duktape::XS';

sub test_instanceof {
    my $js = <<JS;
function Car(make, model, year) {
  this.make = make;
  this.model = model;
  this.year = year;
}

var honda = new Car('Honda', 'Accord', 1998);
honda.older = new Car('Ford', 'T', 1945);
var empty = [];
JS
    my %data = (
        'honda'       => [ 'Car', 'Object' ],
        'honda.older' => [ 'Car', 'Object' ],
        'empty'       => [ 'Array', 'Object' ],
    );
    my $vm = $CLASS->new();
    ok($vm, "created $CLASS object");

    $vm->eval($js);

    foreach my $name (sort keys %data) {
        my $classes = $data{$name};
        foreach my $class (@$classes) {
            my $got = $vm->instanceof($name, $class);
            ok($got, "$name is a $class");
        }
    }
}

sub main {
    use_ok($CLASS);

    test_instanceof();
    done_testing;

    return 0;
}

exit main();
