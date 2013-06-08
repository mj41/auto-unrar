package App::KeyPress;

use strict;
use warnings;
use Carp qw(carp croak verbose);

use base 'Exporter';
our $VERSION = 0.06;

use Term::ReadKey;
our $ver = 0;


sub new {
    my ( $class, $ver, $debug ) = @_;

    my $self  = {};
    $self->{ver} = $ver;
    $self->{debug} = $debug;

    bless ($self, $class);

    Term::ReadKey::ReadMode('cbreak');
    select(STDOUT); $| = 1;

    my $hooks = {};
    $hooks->{before_exit} = sub {};
    $hooks->{quit_pressed} = sub {};
    $hooks->{pause_begin} = sub {};
    $hooks->{pause_refresh} = sub {};
    $hooks->{pause_refresh_rate} = 60*60;
    $hooks->{pause_end} = sub {};
    $self->{hooks} = $hooks;

    # Only process cleanup_before_exit (before_exit) and return. Do not call 'exit'.
    $self->{return_on_exit} = 0;
    $self->{exit_keypressed} = 0;

    return $self;
}

sub set_before_exit_sub {
    my ( $self, $sub_ref ) = @_;
    $self->{hooks}->{before_exit} = $sub_ref;
}

sub set_quit_pressed_sub {
    my ( $self, $sub_ref ) = @_;
    $self->{hooks}->{quit_pressed} = $sub_ref;
}

sub set_return_on_exit {
    my ( $self, $return_on_exit ) = @_;
    $self->{return_on_exit} = $return_on_exit;
}
sub set_pause_begin_sub {
    my ( $self, $sub_ref ) = @_;
    $self->{hooks}->{pause_begin} = $sub_ref;
}

sub set_pause_refresh_sub {
    my ( $self, $sub_ref ) = @_;
    $self->{hooks}->{pause_refresh} = $sub_ref;
}

sub set_pause_refresh_rate {
    my ( $self, $refresh_time ) = @_;
    $refresh_time = 1 if $refresh_time < 1;
    $self->{hooks}->{pause_refresh_rate} = $refresh_time;
}

sub set_pause_end_sub {
    my ( $self, $sub_ref ) = @_;
    $self->{hooks}->{pause_end} = $sub_ref;
}

sub cleanup_before_exit {
    my ( $self ) = @_;
    $self->{exit_keypressed} = 1;
    Term::ReadKey::ReadMode('normal');
    $self->{hooks}->{before_exit}->();
    return 1;
}

sub get_exit_keypressed {
    my ( $self ) = @_;
    return $self->{exit_keypressed};
}

sub reset_exit_keypressed {
    my ( $self ) = @_;
    $self->{exit_keypressed} = 0;
    return 1;
}

sub last_pressed_key() {
    my ( $self ) = @_;
    my $char = undef;
    my $t_char = undef;
    while ( defined ($t_char = ReadKey(-1)) ) {
        $char = $t_char if $t_char;
        #print "|$t_char|\n";
    }
    return $char;
}

sub process_keypress() {
    my ( $self, $start_time ) = @_;

    return 1 if $self->{exit_keypressed};

    $start_time = time() unless defined $start_time;

    my $report_time = $start_time;
    my $paused = undef;
    while ( $paused || not defined $paused ) {
        my $char = $self->last_pressed_key();
        if ( $char ) {
            $char = uc( $char );
            if ( $char eq 'P' ) {
                $self->{hooks}->{pause_begin}->() unless $paused;
                print "Paused. Press C to continue ...\n";
                print "User press pause key.\n" if $ver > 2;
                $paused = 1;

            } elsif ( $char eq 'C' ) {
                print "User press continue key.\n" if $ver > 2;
                $self->{hooks}->{pause_end}->() if $paused;
                $paused = 0;

            } elsif ( $char eq 'Q' || $char eq 'E' ) {
                $self->{hooks}->{quit_pressed}->();
                print "User press exit key.\n" if $ver > 2;
                $self->cleanup_before_exit();
                return 1 if $self->{return_on_exit};
                exit;

            } else {
                print "User press unknown key '$char'.\n" if $ver > 3;
            }
        }
        $paused = 0 unless defined $paused;
        if ( $paused ) {
            if ( defined $self->{hooks}->{pause_refresh} ) {
                if ( time() - $report_time >= $self->{hooks}->{pause_refresh_rate} ) {
                    $self->{hooks}->{pause_refresh}->();
                    $report_time = time();
                }
            }
            sleep 1; # ToDo Time::HiRes ?
        }
    }
    return 1;
}

sub sleep_and_process_keypress {
    my ( $self, $sleep_time ) = @_;

    my $start_time = time();
    my $num = 0;
    while ( time() - $start_time < $sleep_time ) {
        $self->process_keypress( $start_time );
        sleep 1;
        if ( $ver > 9 ) {
            print ".";
            if ( $num < (time() - $start_time) / 10 - 1 ) {
                print "\n";
                $num++;
            }
        }
    }
    print "\n" if $ver > 2;
    return 1;
}

1;
