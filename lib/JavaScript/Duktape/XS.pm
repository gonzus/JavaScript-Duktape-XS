package JavaScript::Duktape::XS;

use strict;
use warnings;

use XSLoader;
use parent 'Exporter';

our $VERSION = '0.000021';
XSLoader::load( __PACKAGE__, $VERSION );

our @EXPORT_OK = qw[];

1;

__END__

=pod

=encoding utf8

=head1 NAME

JavaScript::Duktape::XS - WTF?

=head1 VERSION

Version 0.000001

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS/ATTRIBUTES

=head2 foo

=head2 bar

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Gonzalo Diethelm.

This library is free software; you can redistribute it and/or modify it under
the terms of the MIT license.

=head1 AUTHOR

=over 4

=item * Gonzalo Diethelm C<< gonzus AT cpan DOT org >>

=back

=head1 THANKS
