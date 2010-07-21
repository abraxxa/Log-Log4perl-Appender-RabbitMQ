package Log::Log4perl::Appender::RabbitMQ;
##################################################

use 5.008008;
use strict;
use warnings;

our $VERSION = '0.02';

our @ISA = qw/ Log::Log4perl::Appender /;

use Net::RabbitMQ;
use Readonly;

Readonly my $CHANNEL => 1;

my $RabbitMQClass = 'Net::RabbitMQ';

##################################################
sub new {
##################################################
    my($class, %args) = @_;

    # For testing use the Test::Net::RabbitMQ class
    if ($args{TESTING}) {
        $RabbitMQClass = 'Test::Net::RabbitMQ';
        require Test::Net::RabbitMQ;
    }

    my $self = bless {
        host        => $args{host}        || 'localhost',
        routing_key => $args{routing_key} || '%c'       ,
        declare_exchange => $args{declare_exchange},
    }, $class;

    # set a flag that tells us to do routing_key interpolation
    # only if there are things to interpolate.
    $self->{interpolate_routing_key} = 1 if $self->{routing_key} =~ /%c|%p/;

    # Store any given exchange options for declaring an exchange
    my %exchange_options;
    for my $name (qw/
        exchange_type
        passive_exchange
        durable_exchange
        auto_delete_exchange
    /) {
        # convert from the param name we require in args to the name
        # exchange_declare() will look for by stripping off the _exchange
        (my $declare_param_name = $name) =~ s/(.*)_exchange$/$1/;
        $exchange_options{$declare_param_name} = $args{$name} if exists $args{$name};
    }
    $self->{exchange_options} = \%exchange_options;

    # Store any given publish options for use when log is called
    my %publish_options;
    for my $name (qw/
        exchange
        mandatory
        immediate
    /) {
        $publish_options{$name} = $args{$name} if exists $args{$name};
    }
    $self->{publish_options} = \%publish_options;

    # use any given connect options in connect
    my %connect_options;
    for my $name (qw/
       user
       password
       port
       vhost
       channel_max
       frame_max
       heartbeat
    /) {
        $connect_options{$name} = $args{$name} if exists $args{$name};
    }

    # Create a new connection
    eval {
        @{$self}{qw(mq channel)} = _connect_cached($self->{host}, \%connect_options);

        # declare the exchange if declare_exchange is set
        $self->{mq}->exchange_declare(
            $CHANNEL, 
            $self->{publish_options}{exchange}, 
            $self->{exchange_options},
        ) if $self->{declare_exchange};

        1;
    } or do {
        warn "ERROR creating $class: $@\n";
    };

    return $self;
}


##################################################
# this closure provides a private class method
# that will connect to RabbitMQ and cache that
# connection. The next time it's called with
# the same params it returns the cached connection.
{
    my %connection_cache;

    ##################################################
    sub _connect_cached {
    ##################################################
        my $host = shift;
        my $connect_options = shift;

        no warnings 'uninitialized';
        my $cache_key = join(':', $host, map { $_ , $connect_options->{$_} } sort keys %$connect_options);
        use warnings;

        return $connection_cache{$cache_key} if $connection_cache{$cache_key};

        # Create new RabbitMQ object & connection, open channel 1
        my $mq = $RabbitMQClass->new();
        $mq->connect($host, $connect_options);
        $mq->channel_open($CHANNEL);

        # Cache RabbitMQ object
        $connection_cache{$cache_key} = $mq;

        # Return the RabbitMQ object and the channel we used
        return $mq;
    }
}

##################################################
sub log {
##################################################
    my ($self, %args) = @_;

    my $mq = $self->{mq};

    # do nothing if the Net::RabbitMQ object is missing
    return unless $mq;

    # customize the routing key for this message by 
    # inserting category and level if interpolate_routing_key
    # flag is set
    my $routing_key = $self->{routing_key};
    if ($self->{interpolate_routing_key}) {
        $routing_key =~ s/%c/$args{log4p_category}/g;
        $routing_key =~ s/%p/$args{log4p_level}/g;
    }

    # publish the message to the specified group
    eval {
        $mq->publish($CHANNEL, $routing_key, $args{message}, $self->{publish_options});
        1;
    } or do {
        # If you got an error warn about it and clear the 
        # Net::RabbitMQ object so we don't keep trying
        warn "ERROR logging to RabbitMQ via ".ref($self).": $@\n";
        $self->{mq} = undef;
    };

    return;
}

1;

__END__

=head1 NAME

Log::Log4perl::Appender::RabbitMQ - Log to RabbitMQ

=head1 SYNOPSIS

    use Log::Log4perl;

    my $log4perl_config = q{
        log4perl.logger = DEBUG, RabbitMQ

        log4perl.appender.RabbitMQ             = Log::Log4perl::Appender::RabbitMQ
        log4perl.appender.RabbitMQ.exchange    = myexchange
        log4perl.appender.RabbitMQ.routing_key = mykey
        log4perl.appender.RabbitMQ.layout      = Log::Log4perl::Layout::PatternLayout
    };

    Log::Log4perl::init(\$log4perl_config);

    my $log = Log::Log4perl->get_logger();

    $log->warn('this is my message');

=head1 DESCRIPTION

This is a L<Log::Log4perl> appender for publishing log messages to RabbitMQ group using L<Net::RabbitMQ>.
Defaults for unspecified options are provided by L<Net::RabbitMQ> and can be found in it's documentation.

=head2 OPTIONS

All of the following options can be passed to the constructor, or be specified in the Log4perl config file. Unless otherwise
stated, any options not specified will get whatever defaults L<Net::RabbitMQ> provides. See the documentation for that module
for more details.

=head3 Connection Options

These options are used in the call to L<Net::RabbitMQ::connect()|Net::RabbitMQ/"methods"> when the appender is created.

=over 4

=item user

=item password

=item host

Defaults to localhost.

=item port

=item vhost

=item channel_max

=item frame_max

=item heartbeat

=back

=head3 Exchange Options

Except for L<declare_exchange>, these options are used in a call to L<Net::RabbitMQ::exchange_declare()|Net::RabbitMQ/"methods"> to declare the
exchange specified on the L<exchange> option (See L<Publish Options>).
If L<declare_exchange> is false (the default) the exchange will not be declared and must already exist.

=over 4

=item declare_exchange

Declare the exchange, or just trust that it already exists? Boolean, defaults to 0.

=item exchange_type

'direct, 'topic', etc. Boolean, defaults to 0.

=item durable_exchange

Should the exchange survive a restart? Boolean, defaults to 0.

=item auto_delete_exchange

Delete the exchange when this proccess disconnects? Boolean, defaults to 1.

=back

=head3 Publish Options

These options are used in the call to L<Net::RabbitMQ::publish()|Net::RabbitMQ/"methods"> for each message.

=over 4

=item routing_key

The routing key for messages. If the routing key contains a C<%c> or a C<%p> it will 
be interpolated for each message. C<%c> will be replaced with the Log4perl category.
C<%p> will be replaces with the Log4perl priority.

Defaults to C<%C>

=item exchange

The exchange to publish the message too. This exchange must already exist.

=item mandatory

boolean. Flag published messages mandatory.

=item immediate

boolean. Flag published messages immediate.

=back

=head1 AUTHOR

Trevor J. Little, E<lt>bundacia@tjlittle.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Trevor J. Little

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
