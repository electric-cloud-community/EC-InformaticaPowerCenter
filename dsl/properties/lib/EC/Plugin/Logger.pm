package EC::Plugin::Logger;

use strict;
use warnings;
use Data::Dumper;

use constant {
    ERROR => -1,
    INFO => 0,
    DEBUG => 1,
    TRACE => 2,
};

sub new {
    my ($class, $level) = @_;
    $level ||= 0;
    my $self = {level => $level};
    return bless $self,$class;
}

sub info {
    my ($self, @messages) = @_;
    $self->log(INFO, @messages);
}

sub debug {
    my ($self, @messages) = @_;
    $self->log(DEBUG, '[DEBUG]', @messages);
}

sub error {
    my ($self, @messages) = @_;
    $self->log(ERROR, '[ERROR]', @messages);
}

sub trace {
    my ($self, @messages) = @_;
    $self->log(TRACE, '[TRACE]', @messages);
}

sub log {
    my ($self, $level, @messages) = @_;

    return if $level > $self->{level};
    my @lines = ();
    for my $message (@messages) {
        if (ref $message) {
            print Dumper($message);
        }
        else {
            print "$message\n";
        }
    }
}

sub level {
    my ($self, $level) = @_;
    if ($level) {
        $self->{level} = $level;
    }
    return $self->{level};
}

1;
