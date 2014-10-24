package Net::SNMP::Mixin::Dot1dBase;

use strict;
use warnings;

#
# store this package name in a handy variable,
# used for unambiguous prefix of mixin attributes
# storage in object hash
#
my $prefix = __PACKAGE__;

#
# this module import config
#
use Carp ();
use Net::SNMP::Mixin::Util qw/idx2val normalize_mac/;

#
# this module export config
#
my @mixin_methods;

BEGIN {
  @mixin_methods = (
    qw/
      get_dot1d_base_group
      map_bridge_ports2if_indexes
      map_if_indexes2bridge_ports
      /
  );
}

use Sub::Exporter -setup => {
  exports   => [@mixin_methods],
  groups    => { default => [@mixin_methods], },
};

#
# SNMP oid constants used in this module
#
use constant {
  DOT1D_BASE_BRIDGE_ADDRESS => '1.3.6.1.2.1.17.1.1.0',
  DOT1D_BASE_NUM_PORTS      => '1.3.6.1.2.1.17.1.2.0',
  DOT1D_BASE_TYPE           => '1.3.6.1.2.1.17.1.3.0',

  DOT1D_BASE_PORT_IF_INDEX                => '1.3.6.1.2.1.17.1.4.1.2',
};

=head1 NAME

Net::SNMP::Mixin::Dot1dBase - mixin class for the switch dot1d base values

=head1 VERSION

Version 0.01_01

=cut

our $VERSION = '0.01_01';

=head1 SYNOPSIS

A Net::SNMP mixin class for Dot1d base info.

  use Net::SNMP;
  use Net::SNMP::Mixin qw/mixer init_mixins/;

  # class based mixin
  Net::SNMP->mixer('Net::SNMP::Mixin::Dot1dBase');

  # ...

  my $session = Net::SNMP->session( -hostname => 'foo.bar.com' );

  $session->mixer('Net::SNMP::Mixin::Dot1dBase');
  $session->init_mixins;
  snmp_dispatcher() if $session->nonblocking;
  die $session->error if $session->error;

  my $base_group = $session->get_dot1d_base_group;

  printf "BridgeAddr: %s NumPorts: %d Type: %d\n",
    $base_group->{dot1dBaseBridgeAddress},
    $base_group->{dot1dBaseNumPorts},
    $base_group->{dot1dBaseType};

  my $map = $session->map_bridge_ports2if_indexes;

  foreach my $bridge_port ( sort {$a <=> $b} keys %$map ) {
    my $if_index = $map->{$bridge_port};
    printf "bridgePort: %4d -> ifIndex: %4\n", $bridge_port, $if_index;
  }


=head1 DESCRIPTION

This mixin supports basic switch information from the BRIDGE-MIB.

Besides the bridge address and the number of bridge ports, it's primary use is the mapping between dot1dBasePorts and ifIndexes.

=head1 MIXIN METHODS

=head2 B<< OBJ->get_dot1d_base_group() >>

Returns the dot1dBase group as a hash reference:

  {
    dot1dBaseBridgeAddress => MacAddress,
    dot1dBaseNumPorts      => INTEGER,
    dot1dBaseType          => INTEGER,
  }

=cut

sub get_dot1d_base_group {
  my $session = shift;
  Carp::croak "'$prefix' not initialized,"
    unless $session->{$prefix}{__initialized};

  my $result = {};

  $result->{dot1dBaseBridgeAddress} =
    normalize_mac( $session->{$prefix}{dot1dBaseBridgeAddress} );

  $result->{dot1dBaseNumPorts}      = $session->{$prefix}{dot1dBaseNumPorts};
  $result->{dot1dBaseType}          = $session->{$prefix}{dot1dBaseType};

  return $result;
}

=head2 B<< OBJ->map_bridge_ports2if_indexes() >>

Returns a reference to a hash with the following entries:

  {
    # INTEGER        INTEGER
    dot1dBasePort => dot1dBasePortIfIndex,
  }

=cut

sub map_bridge_ports2if_indexes {
  my ( $session, ) = @_;
  Carp::croak "'$prefix' not initialized,"
    unless $session->{$prefix}{__initialized};

  # datastructure:
  # $session->{$prefix}{dot1dBasePortIfIndex}{$dot1d_base_port} = ifIndex
  #

  my $result = {};

  while ( my ( $bridge_port, $if_index ) =
    each %{ $session->{$prefix}{dot1dBasePortIfIndex} } )
  {
    $result->{$bridge_port} = $if_index;
  }

  return $result;
}

=head2 B<< OBJ->map_if_indexes2bridge_ports() >>

Returns a reference to a hash with the following entries:

  {
    # INTEGER               INTEGER
    dot1dBasePortIfIndex => dot1dBasePort ,
  }

=cut

sub map_if_indexes2bridge_ports {
  my ( $session, ) = @_;
  Carp::croak "'$prefix' not initialized,"
    unless $session->{$prefix}{__initialized};

  # datastructure:
  # $session->{$prefix}{dot1dBasePortIfIndex}{$dot1d_base_port} = ifIndex
  #

  my $result = {};

  while ( my ( $bridge_port, $if_index ) =
    each %{ $session->{$prefix}{dot1dBasePortIfIndex} } )
  {
    $result->{$if_index} = $bridge_port;
  }

  return $result;
}

=head1 INITIALIZATION

=cut

=head2 B<< OBJ->_init($reload) >>

Fetch the dot1d base related snmp values from the host. Don't call this method direct!

=cut

sub _init {
  my ($session, $reload) = @_;

  die "$prefix already initalized and reload not forced.\n"
  	if $session->{$prefix}{__initialized} && not $reload;

  # initialize the object for forwarding databases infos
  _fetch_dot1d_base($session);
  return if $session->error;

  # LLDP, Dot1Q, STP, LLDP, ... tables are indexed
  # by dot1dbaseports and not ifIndexes
  # table to map between dot1dBasePort <-> ifIndex

  _fetch_dot1d_base_ports($session);
  return if $session->error;

  return 1;
}

=head1 PRIVATE METHODS

Only for developers or maintainers.

=head2 B<< _fetch_dot1d_base($session) >>

Fetch values from the dot1dBase group once during object initialization.

=cut

sub _fetch_dot1d_base {
  my $session = shift;
  my $result;

  # fetch the dot1dBase group
  $result = $session->get_request(
    -varbindlist => [

      DOT1D_BASE_BRIDGE_ADDRESS,
      DOT1D_BASE_NUM_PORTS,
      DOT1D_BASE_TYPE,
    ],

    # define callback if in nonblocking mode
    $session->nonblocking ? ( -callback => \&_dot1d_base_cb ) : (),
  );

  return unless defined $result;
  return 1 if $session->nonblocking;

  # call the callback function in blocking mode by hand
  _dot1d_base_cb($session);

}

=head2 B<< _dot1d_base_cb($session) >>

The callback for _fetch_dot1d_base.

=cut

sub _dot1d_base_cb {
  my $session = shift;
  my $vbl     = $session->var_bind_list;

  return unless defined $vbl;

  $session->{$prefix}{dot1dBaseBridgeAddress} =
    $vbl->{DOT1D_BASE_BRIDGE_ADDRESS()};

  $session->{$prefix}{dot1dBaseNumPorts} =
    $vbl->{DOT1D_BASE_NUM_PORTS()};

  $session->{$prefix}{dot1dBaseType} =
    $vbl->{DOT1D_BASE_TYPE() };

  $session->{$prefix}{__initialized}++;
}

=head2 B<< _fetch_dot1d_base_ports($session) >>

Populate the object with the dot1dBasePorts.

=cut

sub _fetch_dot1d_base_ports {
  my $session = shift;
  my $result;

  # fetch the dot1dBasePorts, in blocking or nonblocking mode
  $result = $session->get_entries(
    -columns => [DOT1D_BASE_PORT_IF_INDEX,],

    # define callback if in nonblocking mode
    $session->nonblocking ? ( -callback => \&_dot1d_base_ports_cb ) : (),
  );

  return unless defined $result;
  return 1 if $session->nonblocking;

  # call the callback funktion in blocking mode by hand
  _dot1d_base_ports_cb($session);

}

=head2 B<< _dot1d_base_ports_cb($session) >>

The callback for _fetch_dot1d_base_ports.

=cut

sub _dot1d_base_ports_cb {
  my $session = shift;
  my $vbl     = $session->var_bind_list;

  return unless defined $vbl;

  # mangle result table to get plain idx->value

  $session->{$prefix}{dot1dBasePortIfIndex} =
    idx2val( $vbl, DOT1D_BASE_PORT_IF_INDEX );

  $session->{$prefix}{__initialized}++;
}

=head1 BUGS, PATCHES & FIXES

There are no known bugs at the time of this release. However, if you spot a bug or are experiencing difficulties that are not explained within the POD documentation, please submit a bug to the RT system (see link below). However, it would help greatly if you are able to pinpoint problems or even supply a patch. 

Fixes are dependant upon their severity and my availablity. Should a fix not be forthcoming, please feel free to (politely) remind me by sending an email to gaissmai@cpan.org .

  RT: http://rt.cpan.org/Public/Dist/Display.html?Name=Net-SNMP-Mixin-Dot1dBase

=head1 AUTHOR

Karl Gaissmaier <karl.gaissmaier at uni-ulm.de>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Karl Gaissmaier, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

unless ( caller() ) {
  print "$prefix compiles and initializes successful.\n";
}

1;

# vim: sw=2
