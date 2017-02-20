# ABSTRACT: Log to RabbitMQ

use 5.008008;
use strict;
use warnings;

package Log::Log4perl::Appender::RabbitMQ;

our @ISA = qw/ Log::Log4perl::Appender /;

use Net::AMQP::RabbitMQ 2.30000;
use Readonly;

Readonly my $CHANNEL => 1;

my $RabbitMQClass = 'Net::AMQP::RabbitMQ';

##################################################
sub new {
##################################################
    my($class, %args) = @_;

    # For testing use the Test::Net::RabbitMQ class
    if ($args{TESTING}) {
        $RabbitMQClass = 'Test::Net::RabbitMQ';
        require Test::Net::RabbitMQ;
    }

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

    # Store any given publish options for use when log is called
    my %publish_options;
    for my $name (qw/
        exchange
        mandatory
        immediate
    /) {
        $publish_options{$name} = $args{$name} if exists $args{$name};
    }

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
       ssl
       ssl_verify_host
       ssl_cacert
       ssl_init
    /) {
        $connect_options{$name} = $args{$name} if exists $args{$name};
    }

    my $self = bless {
        host        => $args{host}        || 'localhost',
        routing_key => $args{routing_key} || '%c'       ,
        declare_exchange => $args{declare_exchange},
        connect_options  => \%connect_options,
        exchange_options => \%exchange_options,
        publish_options  => \%publish_options,
        _is_connected    => 0,
    }, $class;

    # set a flag that tells us to do routing_key interpolation
    # only if there are things to interpolate.
    $self->{interpolate_routing_key} = 1 if $self->{routing_key} =~ /%c|%p/;

    # Create a new connection
    eval {
        my $mq = $self->_connect_cached();

        # declare the exchange if declare_exchange is set
        $mq->exchange_declare(
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
sub _connect_cached {
##################################################
    my $self = shift;

    my $mq;
    # use cached object
    if (exists $self->{mq}) {
        #warn "INFO using cached RabbitMQ object\n";
        $mq = $self->{mq};
    }
    else {
        #warn "INFO constructing new RabbitMQ object\n";
        $mq = $RabbitMQClass->new();
        # Cache RabbitMQ object
        $self->{mq} = $mq;
        $self->{_is_connected} = 0;
    }

    if (!$self->{_is_connected}) {
        #warn "INFO connecting to RabbitMQ\n";
        $mq->connect($self->{host}, $self->{connect_options});
        $mq->channel_open($CHANNEL);
        $self->{_is_connected} = 1;
    }

    # Return the RabbitMQ object and the channel we used
    return $mq;
}

##################################################
sub log {
##################################################
    my ($self, %args) = @_;

    my $mq = $self->_connect_cached();

    # do nothing if the Net::AMQP::RabbitMQ object is missing
    unless ($mq) {
        #warn "ERROR logging to RabbitMQ, invalid parameters\n";
        return;
    }

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
        # Net::AMQP::RabbitMQ object so we don't keep trying
        warn "ERROR logging to RabbitMQ via ".ref($self).": $@\n";
        # force a reconnect
        $self->{_is_connected} = 0;
    };

    return;
}

1;

__END__

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

This is a L<Log::Log4perl> appender for publishing log messages to RabbitMQ
using L<Net::AMQP::RabbitMQ>.
Defaults for unspecified options are provided by L<Net::AMQP::RabbitMQ> and
can be found in it's documentation.

=head1 CONFIG OPTIONS

All of the following options can be passed to the constructor, or be
specified in the Log4perl config file. Unless otherwise stated, any options
not specified will get whatever defaults L<Net::AMQP::RabbitMQ> provides.
See the documentation for that module for more details.

=head3 Connection Options

These options are used in the call to
L<Net::AMQP::RabbitMQ::connect()|Net::AMQP::RabbitMQ/"Methods"> when the
appender is created.

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

=item ssl

=item ssl_verify_host

=item ssl_cacert

=item ssl_init

=back

=head3 Exchange Options

Except for L<declare_exchange>, these options are used in a call to
L<Net::AMQP::RabbitMQ::exchange_declare()|Net::AMQP::RabbitMQ/"Methods"> to
declare the exchange specified on the L<exchange> option
(See L<Publish Options>).
If L<declare_exchange> is false (the default) the exchange will not be
declared and must already exist.

=over 4

=item declare_exchange

Declare the exchange, or just trust that it already exists?
Boolean, defaults to 0.

=item exchange_type

'direct, 'topic', etc.

=item durable_exchange

Should the exchange survive a restart? Boolean, defaults to 0.

=item auto_delete_exchange

Delete the exchange when this proccess disconnects? Boolean, defaults to 1.

=back

=head3 Publish Options

These options are used in the call to
L<Net::AMQP::RabbitMQ::publish()|Net::AMQP::RabbitMQ/"Methods"> for each
message.

=over 4

=item routing_key

The routing key for messages. If the routing key contains a C<%c> or a C<%p>
it will be interpolated for each message. C<%c> will be replaced with the
Log4perl category.
C<%p> will be replaces with the Log4perl priority.

Defaults to C<%C>

=item exchange

The exchange to publish the message too. This exchange must already exist
unless declare_exchange is set to true.

=item mandatory

boolean. Flag published messages mandatory.

=item immediate

boolean. Flag published messages immediate.

=back

=head1 METHODS

This is a subclass of L<Log::Log4perl::Appender>. It overrides the following
methods:

=over 4

=item new

=item log

=back

=cut
