package JavaScript::Duktape::XS;
use strict;
use warnings;
use parent 'Exporter';

use JSON::PP;
use Text::Trim qw(trim rtrim);
use XSLoader;

our $VERSION = '0.000070';
XSLoader::load( __PACKAGE__, $VERSION );

our @EXPORT_OK = qw[];

sub _get_js_source_fragment {
    my ($context, $range) = @_;

    $range //= 5;
    foreach my $frame (@{ $context->{frames} }) {
        open my $fh, '<', $frame->{file};
        if (!$fh) {
            # TODO: error message?
            return;
        }
        my $lineno = 0;
        my @lines;
        while (my $line = <$fh>) {
            ++$lineno;
            next unless $lineno >= ($frame->{line} - $range);
            $frame->{line_offset} = $lineno unless exists $frame->{line_offset};

            last unless $lineno <= ($frame->{line} + $range);
            push @lines, rtrim($line);
        }
        $frame->{lines} = \@lines;
    }
}

sub parse_js_stacktrace {
    my ($self, $stacktrace_lines, $desired_frames, $priority_files) = @_;

    $desired_frames //= 1;
    my %priority_files = map +( $_ => 1 ), @{ $priority_files // [] };

    # @contexts => [ {
    #   message => "undefined variable foo",
    #   frames => [ {
    #       file => 'foo.js',
    #       line => 232,  # line 232 is the one with the error
    #       line_offset => 230, # first line in @lines is 230
    #       lines => [
    #           "function a()",
    #           "{",
    #           "  return foo.length",
    #           "}",
    #       ],
    #   }, {...} ]
    #   } ]
    my @contexts_hiprio;
    my @contexts_normal;
    foreach my $line (@$stacktrace_lines) {
        $line = trim($line);
        next unless $line;

        my @texts = split /\n/, $line;
        my %context;
        $context{frames} = [];
        foreach my $text (@texts) {
            $text = trim($text);
            next unless $text;

            # skip any of Duktape's internal functions
            next if $text =~ m/^\s*at\s*.*internal$/;

            $context{message} = $text unless exists $context{message};

            next unless $text =~ m/^\s*at\s*(\S*)\s*\(([^:]*):([0-9]+)(:([0-9]+))?\)/;

            push @{ $context{frames} //= [] }, {
                file => $2,
                line => $3,
            };
            last if scalar @{ $context{frames} } >= $desired_frames;
        }
        next unless exists $context{message};
        next unless scalar @{ $context{frames} };
        my $top_file = $context{frames}[0]{file};
        next unless $top_file;

        _get_js_source_fragment(\%context);
        if ($priority_files && exists $priority_files{$top_file}) {
            push @contexts_hiprio, \%context;
        }
        else {
            push @contexts_normal, \%context;
        }
    }
    return [ @contexts_hiprio, @contexts_normal ];
}

1;
__END__

=pod

=encoding utf8

=head1 NAME

JavaScript::Duktape::XS - Perl XS binding for the Duktape Javascript embeddable
engine

=head1 VERSION

Version 0.000070

=head1 SYNOPSIS

    my $vm = JavaScript::Duktape::XS->new();

    my $options = {
        gather_stats     => 1,
        save_messages    => 1,
        max_memory_bytes => 256*1024,
        max_timeout_us   => 2*1_000_000,
    };
    my $vm = JavaScript::Duktape::XS->new($options);

    $vm->set('global_name', [1, 2, 3]);
    my $aref = $vm->get('global_name');
    $vm->remove('global_name');

    $vm->set('my.object.slot', { foo => [ 4, 5 ] });
    my $href = $vm->get('my.object.slot');

    if ($vm->exists('my.object.slot')) { ... }

    my $typeof = $vm->typeof('my.object.slot');

    my $ok = $vm->instanceof('my.car.object', 'Car');

    # When function_name is called from JS, the arguments passed in
    # will be converted to Perl values; likewise, the value returned
    # from the Perl function will be converted to JS values.
    $vm->set('function_name', sub { my @args = @_; return \@args; });
    my $returned = $vm->eval('function_name(my.object.slot)');

    my $stats_href = $vm->get_stats();
    $vm->reset_stats();

    my $msgs_href = $vm->get_msgs();
    $vm->reset_msgs();

    my $globals = $vm->global_objects();

    my $context = $vm->parse_js_stacktrace($stacktrace_lines, 2);

    my $rounds = $vm->run_gc();

    $vm->set('perl_module_resolve', \&module_resolve);
    $vm->set('perl_module_load',    \&module_load);
    $vm->eval('var badger = require("badger");');

=head1 DESCRIPTION

This module provides an XS wrapper to call Duktape from Perl.

The wrapper is used in an OO way: you create an instance of
C<JavaScript::Duktape::XS> and then invoke functions on it.

=head1 METHODS/ATTRIBUTES

=head2 new

Create a new instance of C<JavaScript::Duktape::XS>.  You can give an optional
hashref with a set of desired options; they can be:

=head3 gather_stats

The XS object will gather statistics about elapsed time and memory usage for
several of its operations.  You can then retrieve the stats by calling
C<get_stats>.

=head3 save_messages

Any message printed to the JavaScript console will instead be saved in a
hashref, where each key represents a "target" for the message (for example,
C<stdout> or C<stderr>).  You can then retrieve the messages by calling
C<get_msgs>.

=head3 max_memory_bytes

Limit the memory dynamically allocated to this many bytes.  If this option is
not used, there is no limit in place.

=head3 max_timeout_us

Limit the execution runtime of any single JavaScript call to this many
microseconds.  If this option is not used, there is no limit in place.

=head2 set

Give a value to a given JavaScript variable or object slot.

The Perl value is converted into an equivalent JavaScript value, so you can
freely pass nested structures (hashes of arrays of hashes) and they will be
handled correctly.

You can also pass a Perl coderef as a value, in which case the named JavaScript
variable / object slot becomes a function which, when executed, will end up
calling the Perl coderef.  Any values passed from JavaScript into the Perl
coderef will be properly converted into equivalent Perl values; likewise, any
values returned from the Perl coderef back to JavaScript will be also converted
into equivalent JavaScript values.

=head2 get

Get the value stored in a JavaScript variable or object slot.

The JavaScript value is converted into an equivalent Perl value, so you can
freely pass nested structures (hashes of arrays of hashes) and they will be
handled correctly.

=head2 remove

Remove a JavaScript variable or object slot.

=head2 exists

Checks to see if there is a value stored in a JavaScript variable or object
slot. Returns a boolean and avoids all JavaScript to Perl value conversions.

=head2 typeof

Returns a string with the JavaScript type of a given variable.  Possible
returned values are C<undefined>, C<null>, C<boolean>, C<number>, C<string>,
C<array>, C<object>, C<symbol>, C<function>, C<pointer>, C<c_function>,
C<lightfunc>, C<thread>, C<buffer>.

This method returns C<null> for null values, which fixes the long-standing
JavaScript bug of returning C<object> for null values.

=head2 instanceof

Returns a true value when the variable given by the first parameter is an
instance of the class given by the second parameter.

=head2 eval

Run a piece of JavaScript code, given as a string, and return the results.
After running the code, wait until all timers (if any) have been dispatched.


For now the XS object will both compile and run the JavaScript code when this
method is invoked; in the future this might be split into separate functions.

Any returned values will be treated in the same way as a call to C<get>.

=head2 get_stats

Return a hashref with the statistics gathered as a result of creating the XS
object with option C<gather_stats> set to true.

=head2 reset_stats

Reset the accumulated statistics, as if the XS object had just been created.

=head2 get_msgs

Return a hashref with the messages collected as a result of creating the XS
object with option C<save_messages> set to true.

=head2 reset_msgs

Reset the accumulated messages, as if the XS object had just been created.

=head2 global_objects

Get an arrayref with the names of all global objects known to JavaScript.

=head2 parse_js_stacktrace

Parse a JavaScript stacktrace (usually returned via C<get_msgs>) and obtain
structured information from it.  For each of the number of frames requested
(default to 1), it gets the error message, the file name and line number where
the error happened, and an array of lines surrounding the actual error message.

The optional third parameter is an arrayref containing names of files that
should be treated as top priority, meaning any errors pointing to those files
will appear first in the returned stacktrace information.

=head2 run_gc

Run at least one round of the JavaScript garbage collector, and return the
number of rounds that were effectively run.

The documentation recommends to run two rounds, so that's what we always do.

=head1 MODULE SUPPORT

There is support for managing JavaScript modules in the style of node.js.  In
order to do this, you need to set two Perl callbacks:

    $vm->set('perl_module_resolve', \&module_resolve);
    $vm->set('perl_module_load',    \&module_load);

Please see
L<https://github.com/svaarala/duktape/tree/master/extras/module-node> for more
details.

=head1 SEE ALSO

=over 4

=item * L<< https://metacpan.org/pod/JavaScript::Duktape >>

=item * L<< https://metacpan.org/pod/JavaScript::V8::XS >>

=back

=head1 LICENSE

Copyright (C) Gonzalo Diethelm.

This library is free software; you can redistribute it and/or modify it under
the terms of the MIT license.

=head1 AUTHOR

=over 4

=item * Gonzalo Diethelm C<< gonzus AT cpan DOT org >>

=back

=head1 THANKS

=over 4

=item * L<< Sami Vaarala|https://github.com/svaarala >> for creating the L<<
Duktape Javascript embeddable engine|http://duktape.org >>.

=back

=cut
