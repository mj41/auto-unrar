#!/usr/bin/perl

use strict;
use warnings;

=head1 NAME

auto-unrar

=head1 ToDo

* fix Archive::Rar atributes bug and send patch to author
* check number of parts from archive
* add was modified check for archives in base dir (root)
* unrar and duplicate names
** unrar to temp directory - go back if error
** compare fname and fname.1 content, remove .1 if same
* password protected archives support
* backup old version of state_fpath files, remove backup after normal end
* unrar/test full paths of files in archive
* refactor to Perl package
* use do_cmd_sub inside do_cmds ?

=cut


use Carp qw(carp croak verbose);
use FindBin qw($RealBin);

use Getopt::Long;
use Pod::Usage;

use File::Spec::Functions qw/:ALL splitpath/;
use File::Copy;
use File::stat;

use Storable;
use Data::Dumper;
use Digest::SHA1;
use Filesys::DfPortable;

use lib "$FindBin::Bin/../lib";
use App::KeyPress;
use Archive::Rar;


=head1 NAME

unrar2.pl - Run auto-unrar utility.

=head1 SYNOPSIS

perl unrar2.pl [options]

 Options:
    --help ... Prints this help informations.

    --ver=$NUM ... Verbosity level 0..10 Default 2.

    --conf=?
      DATA or ../conf/unrar-data-conf.pl
      MY or ../conf/unrar-my-conf.pl

    --conf_part=?
    --conf_part=mydir1
        Process command only for given config part name.

    --cmd=? ... See availible commands below:

    --cmd=unrar
        Unrar/process all directories from configuration file.

    --cmd=process_action_file --action_fpath=$PATH
    --cmd=process_action_file --action_fpath=../conf/clear-done-list.pl
        Process action file. E.g. edit/clear auto-unrar database.

    --cmd=db_cleanup
        Clean up, upgrade and fix db files.

    --cmd=refresh_rsync_file
        Refresh db and rsync files.

    --cmd=db_remove_info
        Remove 'info' part from db file.

    --cmd=db_export
        Export/save db files to other formats.

    --cmd=db_remove_item --item_name=$PATH
    --cmd=db_remove_item --item_name=/subdir2/subdir2b
        Remove this item from db file. Use --conf_part to be more specific.

    --cmd=db_remove_dirs_from_src_dir
        Remove all directories found in source directory from db file. After this
        auto-unrar will process all directories inside source dir again.

=cut

# Global variables.

my $ver = 0;
my $keypress_obj = undef;


# Cache for input directories times of last modification .
my $src_dir_mtimes = {};

=head1 DESCRIPTION

B<This program> run auto-unrar utility. Smart extracting or RAR archives while
respect/dumplicate directory structure.

=head1 METHODS

=head2 main

Parse command line options and run commands.

=cut

sub main {

    # See SYNOPSIS part of perldoc above.
    my $help = 0;

    my $options = {
        ver => 3,
        conf_fpath => undef,
        only_conf_part => undef,
        cmd => undef,
   };

    my $conf_fpath = $ARGV[0];

    my $options_ok = GetOptions(
        'help|h|?' => \$help,
        'ver|v=i' => \$options->{'ver'},
        'conf=s' => \$options->{'conf_fpath'},
        'conf_part=s' => \$options->{'only_conf_part'},
        'cmd=s' => \$options->{'cmd'},

        'action_fpath=s' => \$options->{'action_fpath'},
        'item_name=s' => \$options->{'item_name'},
    );

    if ( $help || !$options_ok ) {
        pod2usage(1);
        return 0 unless $options_ok;
        return 1;
    }

    # Set global variables.
    $ver = $options->{ver};

    if ( ! $options->{cmd} ) {
        print "No command selected. Option 'cmd' is mandatory. Use --help to see more info.\n";
        return 0;
    }

    unless ( $options->{'conf_fpath'} ) {
        print "No configuration path/name given. Option 'conf' is mandatory. Use --help to see more info.\n";
        return 0;
    }

    # Process and test conf_fpath.
    if ( $options->{'conf_fpath'} eq 'MY' ) {
        $options->{'conf_fpath'}  = catfile( $RealBin, '..', 'conf', 'unrar-my-conf.pl' );

    } elsif ( $options->{'conf_fpath'}  eq 'DATA' ) {
        $options->{'conf_fpath'}  = catfile( $RealBin, '..', 'conf', 'unrar-data-conf.pl' );
    }

    unless ( -f $options->{'conf_fpath'} ) {
        print "Can't find defined config file '$options->{'conf_fpath'}'.\n" if $ver >= 1;
        return 0;
    }


    # Prepare/check 'process_action_file' cmd variables.
    my $action_file_data = undef;
    if ( $options->{cmd} eq 'process_action_file' ) {
        unless ( $options->{action_fpath} ) {
            print "No action file path given. Option 'action_fpath' is mandatory. Use --help to see more info.\n";
            return 0;
        }
        print "action_fpath: '$options->{action_fpath}'\n" if $ver >= 5;

        unless ( -f $options->{action_fpath} ) {
            print "Action file '$options->{action_fpath}' not found.\n" if $ver >= 1;
            return 0;
        }


        $action_file_data = load_perl_data( $options->{action_fpath} );
        if ( (not $action_file_data) || ref $action_file_data ne 'ARRAY'  ) {
            print "Action file '$options->{action_fpath}' data loading error.\n" if $ver >= 1;
            return 0;
        }

    # Prepare/check 'db_remove_item' cmd variables.
    } elsif ( $options->{cmd} eq 'db_remove_item' ) {
        unless ( $options->{item_name} ) {
            print "No item name given. Option 'item_name' is mandatory. Use --help to see more info.\n";
            return 0;
        }
    }

    # Init keypress object.
    $keypress_obj = App::KeyPress->new(
        $ver,
        0 # $debug
    );
    $keypress_obj->set_quit_pressed_sub(
        sub {
            print "Quit keypressed.\n" if $ver >= 2;
        }
    );
    $keypress_obj->set_return_on_exit( 1 );


    my $dirs_conf = load_perl_data( $options->{'conf_fpath'} );
    return 0 unless defined $dirs_conf;
    # dumper( '$dirs_conf', $dirs_conf ); my_croak(); # debug


    # Testing.
    if ( 0 ) {
        my $dconf = $dirs_conf->[0];
        my $base_dir = $dconf->{src_dir};
        my $sub_dir = 'subdir6/subdir5A-file';

        my $full_path = catdir( $base_dir, $sub_dir );
        my $dir_items = load_dir_content( $full_path );
        exit unless defined $dir_items;

        do_for_rar_file(
            $dconf,
            [], # $finish_cmds
            $base_dir,
            $sub_dir,
            'test14.part1.rar', # $file_name,
            $dir_items
        );

        return 1;
    }


    # Main loop.
    my $last_dconf_num = $#$dirs_conf;
    DCONF: foreach my $dconf_num ( 0..$last_dconf_num ) {
        my $dconf = $dirs_conf->[ $dconf_num ];

        # skip if only one selected
        if ( defined $options->{conf_part} && $dconf->{name} ne $options->{conf_part} ) {
            print "Skipping configuration $dconf->{name} (only '$options->{conf_part}' selected).\n" if $ver >= 2;
            next DCONF;
        }

        # Check configuration.
        if ( $dconf->{basedir_deep} <= 0 ) {
            print "Configuration $dconf->{name} error: 'basedir_deep' must be >= 1.\n" if $ver >= 1;
            next DCONF;
        }

        my $state = load_state( $dconf );

        # Cmd 'unrar'.
        if ( $options->{cmd} eq 'unrar' ) {

            unless ( -d $dconf->{src_dir} ) {
                print "Input directory '$dconf->{src_dir}' doesn't exists.\n" if $ver >= 1;
                next DCONF;
            }

            unless ( -d $dconf->{dest_dir} ) {
                print "Output directory '$dconf->{dest_dir}' doesn't exists.\n" if $ver >= 1;
                next DCONF;
            }

            dumper( 'dconf', $dconf ) if $ver >= 5;
            my $ud_err_code = unrar_dir_start(
                $state,
                [], # $undo_cmds
                [], # $finish_cmds
                $dconf,
                '', # $sub_dir
                0  # $deep
            );

            # Clean up 'info' part.
            foreach my $if_name ( keys %{$state->{done}} ) {
                if ( exists $state->{info}->{ $if_name } ) {
                    delete $state->{info}->{ $if_name };
                }
            }
            save_state( $state, $dconf );

            if ( $keypress_obj->get_exit_keypressed() ) {
                if ( $dconf_num < $last_dconf_num ) {
                    print "Keypress for Quit - skipping next configuration options.\n" if $ver >= 2;
                }
                last;
            }

            dumper( "state for '$dconf->{name}':", $state ) if $ver >= 5;



        # Cmd 'process_action_file'.
        } elsif ( $options->{cmd} eq 'process_action_file' ) {
            ADATA: foreach my $anum ( 0..$#$action_file_data ) {
                my $acmd = $action_file_data->[ $anum ];
                print "Action " . ($anum+1) . ": '$acmd->{action}'\n" if $ver >= 8;

                if ( exists $acmd->{where} ) {
                    my $where = $acmd->{where};
                    foreach my $w_key ( keys %$where ) {
                        my $w_value = $where->{$w_key};
                        print "Key '$w_key', value '$w_value'\n" if $ver >= 10;

                        if ( not exists $dconf->{$w_key} ) {
                            print "Unknown configuration key '$w_key'\n" if $ver >= 2;
                            next ADATA;

                        } elsif ( $dconf->{$w_key} ne $w_value ) {
                            print "Configuration key '$w_key' has value '$dconf->{$w_key}' != '$w_value'.\n" if $ver >= 10;
                            next ADATA;
                        }
                    }

                    print "Where condition fulfilled.\n" if $ver >= 4;
                }


                if ( $acmd->{action} eq 'remove_from_done_list' ) {
                    unless ( exists $acmd->{what} ) {
                        print "What part not found in action file.\n" if $ver >= 2;
                        next ADATA;
                    }
                    foreach my $item_name ( @{$acmd->{what}} ) {
                        print "Going to remove item '$item_name'\n" if $ver >= 10;
                        remove_item_from_state( $state, $item_name );
                    }

                } else {
                    print "Unknown action '$acmd->{action}'.\n" if $ver >= 2;
                }

            }

            save_state( $state, $dconf );
            next DCONF;


        # Cmd 'refresh_rsync_file'.
        }elsif ( $options->{cmd} eq 'refresh_rsync_file' ) {
            save_state( $state, $dconf );
            next DCONF;


        # Cmd 'db_cleanup'.
        } elsif ( $options->{cmd} eq 'db_cleanup' ) {

            # Upgrade from prev versions.
            delete $state->{err} if exists $state->{err};

            # Fix old errors.
            delete $state->{done}->{''} if exists $state->{done}->{''};

            # Clean up data.
            foreach my $name ( keys %{$state->{done}} ) {
                if ( exists $state->{info}->{ $name } ) {
                    delete $state->{info}->{ $name };
                }
            }

            save_state( $state, $dconf );
            next DCONF;


        # Cmd 'db_remove_info'.
        } elsif ( $options->{cmd} eq 'db_remove_info' ) {
            delete $state->{info} if exists $state->{info};
            save_state( $state, $dconf );
            next DCONF;


        # Cmd 'db_export'.
        } elsif ( $options->{cmd} eq 'db_export' ) {
            # Export to other format.
            if ( $dconf->{state_store_type} eq 'perl' ) {
                $dconf->{state_store_type} = 'storable';
                $dconf->{state_fpath} =~ s{\.pl$}{\.db};
            } else {
                $dconf->{state_store_type} = 'perl';
                $dconf->{state_fpath} =~ s{\.db$}{\.pl};
            }
            save_state( $state, $dconf );
            next DCONF;


        # Cmd 'db_remove_item'.
        } elsif ( $options->{cmd} eq 'db_remove_item' ) {
            # Remove some file from done and info parts.
            my $item_name = $options->{item_name};
            dumper( 'old $state', $state ) if $ver >= 6;
            remove_item_from_state( $state, $item_name );
            dumper( 'new $state', $state ) if $ver >= 6;
            save_state( $state, $dconf );
            next DCONF;


        # Cmd 'db_remove_dirs_from_src_dir'.
        } elsif ( $options->{cmd} eq 'db_remove_dirs_from_src_dir' ) {

            # Remove dirs found inside input dir from state:done list.
            my $items = load_dir_content( $dconf->{src_dir} );
            # dumper( '$items', $items ) if $ver >= 10;

            foreach my $item ( @$items ) {
                my $i_path = catfile( $dconf->{src_dir}, $item );
                next DCONF unless -d $i_path;
                my $full_item_name = '/' . $item;
                print "full_item_name: '$full_item_name'\n" if $ver >= 10;
                remove_item_from_state( $state, $full_item_name );
            }

            save_state( $state, $dconf );
            next DCONF;

        } # end of last cmd

    } # end foreach

    return 1;
}


=head2 my_croak

Do clean up before croak with given message.

=cut

sub my_croak {
    my ( $err_msg ) = @_;
    $keypress_obj->cleanup_before_exit();
    croak $err_msg;
}

sub load_perl_data {
    my ( $fpath ) = @_;

    print "Loading data from '$fpath'.\n" if $ver >= 4;
    my( $exception, $conf );
    {
        local $@;
        $conf = do $fpath;
        $exception = $@;
    }
    if ( $exception ) {
        print "Loading data from '$fpath' failed: $exception\n" if $ver >= 2;
        return undef;
    }
    return $conf;
}

sub debug_suffix {
    my ( $msg, $caller_back ) = @_;
    $caller_back = 1 unless defined $caller_back;

    $msg =~ s/[\n\s]+$//;

    my $has_new_line = 0;
    $has_new_line = 1 if $msg =~ /\n/;

    my $caller_line = (caller 0+$caller_back)[2];
    my $caller_sub = (caller 1+$caller_back)[3];

    $msg .= " ";
    $msg .= "(" unless $has_new_line;
    $msg .= "$caller_sub " if $caller_sub;
    $msg .= "on line $caller_line";
    $msg .= ')' unless $has_new_line;
    $msg .= ".\n";
    $msg .= "\n" if $has_new_line;
    return $msg;
}

sub dumper {
    my ( $prefix_text, $data, $caller_back ) = @_;

    my $ot = '';
    if ( (not defined $data) && $prefix_text =~ /^\n$/ ) {
        $ot .= $prefix_text;
        return 1;
    }

    $caller_back = 0 unless defined $caller_back;
    if ( defined $prefix_text ) {
        $prefix_text .= ' ';
    } else {
        $caller_back = 0;
        $prefix_text = '';
    }

    $ot = $prefix_text;
    if ( defined $data ) {
        local $Data::Dumper::Indent = 1;
        local $Data::Dumper::Purity = 1;
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Sortkeys = 1;
        $ot .= Data::Dumper->Dump( [ $data ], [] );
    }

    if ( $caller_back >= 0 ) {
        $ot = debug_suffix( $ot, $caller_back+1 );
    }

    print $ot;
    return 1;
}

sub load_dir_content {
    my ( $dir_name ) = @_;

    my $dir_h;
    if ( not opendir($dir_h, $dir_name) ) {
        print STDERR "Directory '$dir_name' not open for read.\n" if $ver >= 1;
        return undef;
    }
    my @all_items = readdir( $dir_h );
    close($dir_h);

    return [] unless scalar @all_items;

    my $items = [];
    foreach my $name ( @all_items ) {
        next if $name =~ /^\.$/;
        next if $name =~ /^\..$/;
        next if $name =~ /^\s*$/;
        push @$items, $name;
    }

    return $items;
}

sub do_cmd_sub {
    my ( $cmd_sub, $msg ) = @_;

    my $done_ok = 0;
    my $out_data = undef;
    my $sleep_time = 1;
    while ( not $done_ok ) {
        my $ret_val = $cmd_sub->();

        $out_data = undef;
        if ( ref $ret_val ) {
            ( $done_ok, $out_data ) = @$ret_val;
        } else {
            $done_ok = $ret_val;
        }

        unless ( $done_ok ) {
            if ( $ver >= 5 ) {
                print $msg;
                print $out_data if defined $out_data;
                print " Sleeping $sleep_time s ...\n";
            }
            $keypress_obj->sleep_and_process_keypress( $sleep_time );
            my $max_sleep_time = 10*60; # max 10 minutes
            if ( $sleep_time < $max_sleep_time ) {
                $sleep_time = $sleep_time * $sleep_time;
                $sleep_time = $max_sleep_time if $sleep_time > $max_sleep_time;
            }
        }
    }

    return $out_data;
}

sub get_item_info {
    my ( $base_path, $item_sub_path ) = @_;

    my $item_path = catdir( $base_path, $item_sub_path );
    my $stat_obj = get_item_stat_obj( $item_path );
    return undef unless $stat_obj;

    my $info = {
        path => $item_sub_path,
        mtime => $stat_obj->mtime,
    };
    if ( -d $item_path ) {
        $info->{is_dir} = 1;
    } else {
        $info->{size} = $stat_obj->size;
    }
    return $info;
}

sub get_rec_content_info {
    my ( $info, $base_path, $item_sub_path ) = @_;


    my $item_info = get_item_info( $base_path, $item_sub_path );
    return undef unless defined $item_info;
    push @$info, $item_info;

    my $item_path = catdir( $base_path, $item_sub_path );

    # No directory.
    return 1 unless -d $item_path;

    my $dir_items = load_dir_content( $item_path );
    return undef unless defined $dir_items;

    foreach my $sitem_name ( sort @$dir_items ) {
        my $sitem_sub_path = catdir( $item_sub_path, $sitem_name );
        my $sret_code = get_rec_content_info( $info, $base_path, $sitem_sub_path );
        return undef unless $sret_code;
    }

    return 1;
}

sub get_content_info_and_hash {
    my ( $base_path, $item_sub_path ) = @_;

    my $info = [];
    my $ret_code = get_rec_content_info( $info, $base_path, $item_sub_path );
    return ( undef, undef ) unless $ret_code;

    my $hash_str = '';
    foreach my $item_info ( @$info ) {
        map { $hash_str .= '|' . $_ . '|' . $item_info->{$_} } sort keys %$item_info;
        $hash_str .= '|';
    }
    my $hash = Digest::SHA1::sha1_hex( $hash_str );
    return ( $info, $hash );
}

sub save_item_rec_content_info {
    my ( $state, $dconf, $base_path, $item_sub_path, $info, $save_content_info ) = @_;

    return 1 unless $item_sub_path;

    $info = {} unless defined $info;

    my ( $content_info, $hash ) = get_content_info_and_hash( $base_path, $item_sub_path );
    $info->{time} = time();
    if ( $save_content_info ) {
        $info->{content} = $content_info;
    }
    $info->{content_meta_hash} = $hash;

    $state->{info}->{$item_sub_path} = [] unless defined $state->{info}->{$item_sub_path};
    push @{ $state->{info}->{$item_sub_path} }, $info;

    return save_state( $state, $dconf );
}

sub save_item_done {
    my ( $state, $dconf, $item_name ) = @_;

    if ( defined $item_name && $item_name ) {
        $state->{done}->{$item_name} = time();
    }

    my $state_store_type = $dconf->{state_store_type};
    if ( $state_store_type eq 'storable' ) {
        do_cmd_sub(
            sub { store( $state, $dconf->{state_fpath} ); },
            "Saving state to '$dconf->{state_fpath}' failed  (type=$state_store_type)."
        );

    } elsif ( $state_store_type eq 'perl' ) {
        my $dumper_obj = Data::Dumper->new( [ $state ], [ 'state' ] );
        $dumper_obj->Purity(1)->Terse(1)->Deepcopy(1)->Sortkeys(1)->Indent(1);
        my $state_dump_code = $dumper_obj->Dump;

        do_cmd_sub(
            sub {
                my $fh;
                open( $fh, '>', $dconf->{state_fpath} ) or return ( 0, $! );
                print $fh $state_dump_code;
                close $fh or return ( 0, $! );
            },
            "Saving state to '$dconf->{state_fpath}' failed (type=$state_store_type)."
        );

    } else {
        print "Unknown state_store_type '$state_store_type'.\n" if $ver >= 2;
        return 0;
    }

    if ( defined $item_name ) {
        print "Item '$item_name' saved to state_fpath.\n" if $ver >= 5;
    } else {
        print "State saved to state_fpath.\n" if $ver >= 5;
    }


    if ( $dconf->{exclude_list} ) {
        my $out_fh = do_cmd_sub(
            sub {
                my $out_fh = undef;
                my $ok = open( $out_fh, '>', $dconf->{exclude_list} );
                return [ $ok, $out_fh ];
            },
            "Open file '$dconf->{exclude_list}' for write."
        );
        foreach my $item ( sort keys %{ $state->{done} } ) {
            my $line = "- $item\n";
            print $out_fh $line;
        }
        do_cmd_sub(
            sub { close $out_fh; },
            "Closing file '$dconf->{exclude_list}'."
        );
    }

    return 1;
}

sub save_state {
    my ( $state, $dconf ) = @_;
    return save_item_done( $state, $dconf, undef );
}

sub load_state {
    my ( $dconf ) = @_;

    my $state_store_type = 'storable';
    if ( $dconf->{state_fpath} =~ /\.pl$/ ) {
        $state_store_type = 'perl';
    }
    $dconf->{state_store_type} = $state_store_type;

    unless ( -e $dconf->{state_fpath} ) {
        return {
            'done' => {},
        };
    }

    my $state = undef;
    if ( $dconf->{state_store_type} eq 'storable' ) {
        $state = retrieve( $dconf->{state_fpath} );
    } else {
        $state = load_perl_data( $dconf->{state_fpath} );
    }
    return $state;
}

sub get_item_stat_obj {
    my ( $path ) = @_;

    my $stat_obj = stat( $path );
    unless ( defined $stat_obj ) {
        print "Command stat for item '$path' failed.\n" if $ver >= 1;
        return undef;
    }
    return $stat_obj;
}

sub get_item_mtime {
    my ( $path ) = @_;

    my $stat_obj = get_item_stat_obj( $path );
    return undef unless $stat_obj;

    return $stat_obj->mtime;
}

sub set_dir_mtime {
    my ( $dest_dir_path, $src_mtime ) = @_;

    my $act_time = time();

    # Do not allow time in future.
    $src_mtime = $act_time if $src_mtime > $act_time;

    unless ( utime($act_time, $src_mtime, $dest_dir_path) ) {
        print "Command utime for '$dest_dir_path' failed: $^E\n" if $ver >= 1;
        return 0;
    }

    print "Finished setting '$dest_dir_path' mtime to " . (localtime $src_mtime) . "\n" if $ver >= 8;
    return 1;
}

sub set_saved_dir_mtime {
    my ( $dest_dir_path, $src_dir_part ) = @_;

    unless ( defined $src_dir_mtimes->{ $src_dir_part } ) {
        print "Error: Saved mtime for dir '$src_dir_part' not found.\n" if $ver >= 3;
        return 0;
    }

    return set_dir_mtime( $dest_dir_path, $src_dir_mtimes->{ $src_dir_part } );
}

sub copy_dir_mtime {
    my ( $dest_dir_path, $src_dir_path ) = @_;

    my $src_mtime = get_item_mtime( $src_dir_path );
    return 0 unless defined $src_mtime;

    return set_dir_mtime( $dest_dir_path, $src_mtime );
}

sub mkdir_copy_mtime {
    my ( $dest_dir_path, $src_dir_path ) = @_;

    return 1 if -d $dest_dir_path;

    print "mkdir_copy_mtime '$src_dir_path' -> '$dest_dir_path'\n" if $ver >= 8;

    unless ( mkdir( $dest_dir_path, 0777 ) ) {
        print "Command mkdir '$dest_dir_path' failed: $^E\n" if $ver >= 1;
        return 0;
    }

    return copy_dir_mtime( $dest_dir_path, $src_dir_path );
}

sub mkpath_copy_mtime {
    my ( $dest_base_dir, $src_base_dir, $sub_dirs ) = @_;

    my $full_dest_dir = catdir( $dest_base_dir, $sub_dirs );
    return 1 if -d $full_dest_dir;

    unless ( -d $dest_base_dir ) {
        print "Error mkpath_copy_mtime dest_base_dir '$dest_base_dir' doesn't exists.\n" if $ver >= 1;
        return 0;
    }

    unless ( -d $src_base_dir ) {
        print "Error mkpath_copy_mtime src_base_dir '$src_base_dir' doesn't exists.\n" if $ver >= 1;
        return 0;
    }

    my $full_src_dir = catdir( $src_base_dir, $sub_dirs );
    unless ( -d $full_src_dir ) {
        print "Error mkpath_copy_mtime full_src_dir '$full_src_dir' doesn't exists.\n" if $ver >= 1;
        return 0;
    }

    my @dir_parts = File::Spec->splitdir( $sub_dirs );
    my $tmp_dest_dir = $dest_base_dir;
    my $tmp_src_dir = $src_base_dir;
    foreach my $dir ( @dir_parts ) {
        $tmp_dest_dir = catdir( $tmp_dest_dir, $dir );
        $tmp_src_dir = catdir( $tmp_src_dir, $dir );
        return 0 unless mkdir_copy_mtime( $tmp_dest_dir, $tmp_src_dir );
    }
    return 1;
}

sub do_for_dir {
    my ( $dconf, $finish_cmds, $undo_cmds, $base_dir, $sub_dir ) = @_;

    push @$finish_cmds, [ 'mkpath_copy_mtime', $dconf->{dest_dir}, $base_dir, $sub_dir ];

    my $dest_path = catdir( $dconf->{dest_dir}, $sub_dir );
    push @$undo_cmds, [ 'rm_rec_empty_dir', $dest_path ];

    return 1;
}

sub do_for_rar_file {
    my ( $dconf, $finish_cmds, $base_dir, $sub_dir, $file_name, $dir_items ) = @_;


    my $base_name_part = undef;
    my $is_rar_archive = 0;
    my $part_num = undef;
    my $multipart_type = undef;
    my $part_num_str_length = undef;

    if ( $file_name =~ /^(.*)\.part(\d+)\.rar$/ ) {
        my $tmp_base_name_part = $1;
        my $tmp_part_num = $2;

        # See test/subdir11.
        my $mr_type_found = 0;
        NEXT_FILE: foreach my $next_file_name ( sort @$dir_items ) {
            if ( $next_file_name =~ /^\Q${tmp_base_name_part}.part${tmp_part_num}\E\.r(\d+)$/ ) {
                $mr_type_found = 1;
                last;
            }
        }

        if ( not $mr_type_found ) {
            $base_name_part = $tmp_base_name_part;
            $part_num = $tmp_part_num;
            $part_num_str_length = length( $tmp_part_num );
            $is_rar_archive = 1;
            $multipart_type = 'part';
        }
    }

    if ( defined $multipart_type ) {
        # Is 'part' type.

    } elsif ( $file_name =~ /^(.*)\.rar$/ ) {
        $base_name_part = $1;
        $part_num = 1;
        $part_num_str_length = undef;
        $is_rar_archive = 1;
        # initial value, is set to '' unless other parts found
        $multipart_type = 'mr';

    } elsif ( $file_name =~ /^(.*)\.r(\d+)$/ ) {
        $base_name_part = $1;
        $part_num = $2 + 2;
        $part_num_str_length = length( $2 );
        $is_rar_archive = 1;
        # initial value, is set to '' unless other parts found
        $multipart_type = 'mr';

    } elsif ( $file_name =~ /^(.*)\.(\d{3})$/ ) {
        $base_name_part = $1;
        $part_num = $2;
        $part_num_str_length = length( $2 );
        $is_rar_archive = 1;
        $multipart_type = 'unsup';
    }

    return ( 0, "File isn't rar archive.", undef, undef )
		unless $is_rar_archive;
    return ( 1, "File is part of multiparts archive (type $multipart_type), but isn't first part.", undef, undef )
		if $multipart_type && ($part_num != 1);
    return -1
		unless mkpath_copy_mtime( $dconf->{dest_dir}, $base_dir, $sub_dir );

    my $dest_dir = catdir( $dconf->{dest_dir}, $sub_dir );
    my $file_sub_path = catfile( $sub_dir, $file_name );
    my $file_path = catfile( $base_dir, $sub_dir, $file_name );

    my $rar_ver = $ver - 10;
    $rar_ver = 0 if $rar_ver < 0;
    my %rar_conf = (
        '-archive' => $file_path,
        '-initial' => $dest_dir,
    );
    $rar_conf{'-verbose'} = $rar_ver if $rar_ver;
    my $rar_obj = Archive::Rar->new( %rar_conf );
    $rar_obj->List();
    my @files_extracted = $rar_obj->GetBareList();

    if ( $ver >= 10 ) {
        print "Input file '$file_name':\n";
        $rar_obj->PrintList();
        dumper( 'rar_obj->list', $rar_obj->{list} );
        dumper( '@files_extracted', \@files_extracted );
    }

    my @rar_parts_list = ();
    $rar_parts_list[0] = $file_name;

    my %files_extracted = map { $_ => 1 } @files_extracted;
    #dumper( '%files_extracted', \%files_extracted );

    my $other_part_found = 0;
    NEXT_FILE: foreach my $next_file_name ( sort @$dir_items ) {
        next NEXT_FILE if $file_name eq $next_file_name;

        my $other_part_num = undef;
        my $other_part_num_str_length = undef;

        if ( $multipart_type eq 'part' ) {
            if ( $next_file_name =~ /^\Q$base_name_part\E\.part(\d+)\.rar$/ ) {
                $other_part_num = $1;
                $other_part_num_str_length = length( $1 );
            }

        } elsif ( $multipart_type eq 'mr' ) {
            if ( $next_file_name =~ /^\Q$base_name_part\E\.r(\d+)$/ ) {
                $other_part_num = $1 + 2;
                unless ( defined $part_num_str_length ) {
                    $part_num_str_length = length( $1 );
                }
                $other_part_num_str_length = length( $1 );
            }

        } elsif ( $multipart_type eq 'unsup' ) {
            if ( $next_file_name =~ /^\Q$base_name_part\E\.(\d+)$/ ) {
                $other_part_num = $1;
                $other_part_num_str_length = length( $1 );
            }
        }

        next unless defined $other_part_num;

        if ( defined $part_num_str_length ) {
            if ( $other_part_num_str_length != $part_num_str_length ) {
                print "Error: Found other_part_num $other_part_num with length $other_part_num_str_length which isn't same as base part length $part_num_str_length.\n" if $ver >= 2;
                next;
            }
        }

        if ( $part_num == $other_part_num ) {
            print "Error: Found other_part_num $other_part_num same as part_num $part_num.\n" if $ver >= 2;
            next;
        }

        $other_part_found = 1;

        print "Other rar part added '$next_file_name' ($other_part_num) for base_name '$base_name_part' and type '$multipart_type'.\n" if $ver >= 5;
        $rar_parts_list[ $other_part_num - 1 ] = $next_file_name;

        my $next_file_path = catfile( $base_dir, $sub_dir, $next_file_name );
        my %next_rar_conf = (
            '-archive' => $next_file_path,
            '-initial' => $dest_dir,
        );
        $rar_conf{'-verbose'} = $rar_ver if $rar_ver;
        my $next_rar_obj = Archive::Rar->new( %next_rar_conf );
        $next_rar_obj->List();

        my @next_files_extracted = $next_rar_obj->GetBareList();
        next NEXT_FILE unless scalar @next_files_extracted;

        #dumper( '@next_files_extracted', \@next_files_extracted );
        foreach my $next_file ( @next_files_extracted ) {
            next unless defined $next_file; # Archive::Rar bug?
            next if exists $files_extracted{$next_file};

            $files_extracted{$next_file} = 1;
            push @files_extracted, $next_file;
            print "Addding new extracted file '$next_file' to list from rar part num $other_part_num.\n" if $ver >= 8;
        }

    } # foreach end
    $multipart_type = '' unless $other_part_found;


    my $found_missing_part = 0;
    # ToDo - extract num of parts from archive.
    if ( $multipart_type ) {
        my $num_sprintf_format = '%0' . $part_num_str_length . 'd';
        foreach my $num ( 0..$#rar_parts_list ) {
            my $t_pfname = $rar_parts_list[ $num ];
            next if defined $t_pfname;

            $found_missing_part = 1;
            my $t_pnum = $num + 1;

            my $exp_file_name = 'unknown';
            if ( $multipart_type eq 'part' ) {
                my $other_part_num = $t_pnum;
                $exp_file_name = $base_name_part . '.part' . sprintf( $num_sprintf_format, $other_part_num ) . '.rar';

            } elsif ( $multipart_type eq 'mr' ) {
                my $other_part_num = $t_pnum - 2;
                $exp_file_name = $base_name_part . '.r' . sprintf( $num_sprintf_format, $other_part_num );

            } elsif ( $multipart_type eq 'unsup' ) {
                my $other_part_num = $t_pnum;
                $exp_file_name = $base_name_part . '.' . sprintf( $num_sprintf_format, $other_part_num );
            }

            my $ex_file_path = catfile( $sub_dir, $exp_file_name );
            print "Misssing part num '" . $t_pnum . "' - guessed file name '$ex_file_path'.\n" if $ver >= 2;
        }
    }

    if ( $ver >= 2 ) {
        my $num_of_parts = scalar @rar_parts_list;
        print "Extracting file '$file_sub_path'";
        print " (first of $num_of_parts parts)" if $num_of_parts > 1;
        print ".\n";
    }
    print "File '$file_name' - base_name_part '$base_name_part', is_rar_archive $is_rar_archive, part_num $part_num, multipart_type '$multipart_type'\n" if $ver >= 5;

    my $res = $rar_obj->Extract(
        '-donotoverwrite' => 1,
        '-quiet' => 1,
        '-lowprio' => 1
    );
    if ( $res && $res != 1 ) {
        print "Error $res in extracting from '$file_path'.\n" if $ver >= 1;
        return ( -1, $res, [], \@rar_parts_list );
    }
    return ( 3, undef, \@files_extracted, \@rar_parts_list );
}

sub do_for_norar_file {
    my ( $dconf, $finish_cmds, $base_dir, $sub_dir, $file_name ) = @_;

    return 1 if not $dconf->{move_non_rars} && not $dconf->{cp_non_rars};

    push @$finish_cmds, [ 'mkpath_copy_mtime', $dconf->{dest_dir}, $base_dir, $sub_dir ];

    my $file_path = catfile( $base_dir, $sub_dir, $file_name );
    my $new_file_path = catfile( $dconf->{dest_dir}, $sub_dir, $file_name );

    if ( $dconf->{move_non_rars} ) {
        print "Moving '$file_path' to '$new_file_path'.\n" if $ver >= 3;
        push @$finish_cmds, [ 'move_num', $file_path, $new_file_path ];


    } elsif ( $dconf->{cp_non_rars} ) {
        print "Copying '$file_path' to '$new_file_path'.\n" if $ver >= 3;
        push @$finish_cmds, [ 'cp_num', $file_path, $new_file_path ];

    }

    return 1;
}

sub get_next_file_path {
    my ( $file_path ) = @_;

    my $num = 2;
    my $new_file_path;
    do {
        $new_file_path = $file_path . '.' . $num;
        $num++;
    } while ( -e $new_file_path );

    return $new_file_path;
}

sub rm_empty_dir {
    my ( $dir_path ) = @_;

    my $other_items = load_dir_content( $dir_path );
    return 0 unless defined $other_items;

    if ( scalar(@$other_items) == 0 ) {
        unless ( rmdir($dir_path) ) {
            print "Command rmdir '$dir_path' failed: $^E\n" if $ver >= 1;
            return 0;
        }
        print "Command rmdir '$dir_path' done ok.\n" if $ver >= 8;
    }

    return 1;
}

sub rm_rec_empty_dir {
    my ( $dir_path ) = @_;

    my $dir_items = load_dir_content( $dir_path );
    return 0 unless defined $dir_items;

    if ( scalar @$dir_items ) {
        foreach my $name ( @$dir_items ) {
            my $path = catfile( $dir_path, $name );
            unless ( -d $path ) {
                print "Can't remove dir with items '$dir_path' (item '$name').\n" if $ver >= 1;
                return 0;
            }
        }

        # Only dirs remains.
        foreach my $name ( @$dir_items ) {
            my $path = catfile( $dir_path, $name );
            return 0 unless rm_rec_empty_dir( $path );
        }
    }

    return rm_empty_dir( $dir_path );
}

sub get_rec_dir_mtime {
    my ( $dir_path ) = @_;

    my $max_mtime = get_item_mtime( $dir_path );
    return undef unless defined $max_mtime;
    #print "Dir '$dir_path' max mtime " . (localtime $max_mtime) . " (max mtime " . (localtime $max_mtime) . ")\n" if $ver >= 8;

    my $dir_items = load_dir_content( $dir_path );
    return undef unless defined $dir_items;
    return $max_mtime unless scalar @$dir_items;

    foreach my $name ( @$dir_items ) {
        my $path = catdir( $dir_path, $name );

        my $item_mtime = get_item_mtime( $path );
        $max_mtime = $item_mtime if $item_mtime && $item_mtime > $max_mtime;
        #print "Item '$path' max mtime " . (localtime $item_mtime) . " (max mtime " . (localtime $max_mtime) . ")\n" if $ver >= 8;

        if ( -d $path ) {
            my $subdir_max_mtime = get_rec_dir_mtime( $path );
            return undef unless defined $subdir_max_mtime;
            $max_mtime = $subdir_max_mtime if $subdir_max_mtime > $max_mtime;
            #print "Subdir '$path' max mtime " . (localtime $subdir_max_mtime) . " (max mtime " . (localtime $max_mtime) . ")\n" if $ver >= 8;
        }
    }
    return $max_mtime;
}

sub do_cmds {
    my ( $state, $dconf, $finish_cmds ) = @_;

    my $all_ok = 1;
    foreach my $cmd_conf ( @$finish_cmds ) {
        my $cmd = shift @$cmd_conf;

        if ( $ver >= 2 && not defined $cmd ) {
            dumper( 'do_cmds error', $finish_cmds, 1 );
            next;
        }

        # unlink
        if ( $cmd eq 'unlink' ) {
            my $full_part_path = shift @$cmd_conf;
            unless ( unlink($full_part_path) ) {
                print "Command unlink '$full_part_path' failed: $^E\n" if $ver >= 1;
                $all_ok = 0;
            }

        # save_done
        } elsif ( $cmd eq 'save_done' ) {
            my $item_name = shift @$cmd_conf;
            unless ( save_item_done($state, $dconf, $item_name) ) {
                $all_ok = 0;
            }

        # rmdir
        } elsif ( $cmd eq 'rmdir' ) {
            my $dir_name = shift @$cmd_conf;

            unless ( rmdir($dir_name) ) {
                print "Command rmdir '$dir_name' failed: $! $^E\n" if $ver >= 1;
                $all_ok = 0;
            }

        # move_num
        } elsif ( $cmd eq 'move_num' ) {
            my $file_path = shift @$cmd_conf;
            my $new_file_path = shift @$cmd_conf;

            $new_file_path = get_next_file_path( $new_file_path ) if -e $new_file_path;
            unless ( move($file_path, $new_file_path) ) {
               print "Command move '$file_path' '$new_file_path' failed: $^E\n" if $ver >= 1;
               $all_ok = 0;
            }

        # cp_num
        } elsif ( $cmd eq 'cp_num' ) {
            my $file_path = shift @$cmd_conf;
            my $new_file_path = shift @$cmd_conf;

            $new_file_path = get_next_file_path( $new_file_path) if -e $new_file_path;
            unless ( cp($file_path, $new_file_path) ) {
               print "Command cp '$file_path' '$new_file_path' failed: $^E\n" if $ver >= 1;
               $all_ok = 0;
            }

        # mkpath_copy_mtime
        } elsif ( $cmd eq 'mkpath_copy_mtime' ) {
            my $dest_dir = shift @$cmd_conf;
            my $src_dir = shift @$cmd_conf;
            my $sub_dirs = shift @$cmd_conf;

            unless ( mkpath_copy_mtime( $dest_dir, $src_dir, $sub_dirs ) ) {
               $all_ok = 0;
            }

        # set_saved_dir_mtime
        } elsif ( $cmd eq 'set_saved_dir_mtime' ) {
            my $dest_dir_path = shift @$cmd_conf;
            my $sub_dir = shift @$cmd_conf;
            unless ( set_saved_dir_mtime( $dest_dir_path, $sub_dir ) ) {
                $all_ok = 0;
            }

        # rm_empty_dir
        } elsif ( $cmd eq 'rm_empty_dir' ) {
            my $dir_path = shift @$cmd_conf;
            $all_ok = 0 unless rm_empty_dir( $dir_path );

        # rm_rec_empty_dir
        } elsif ( $cmd eq 'rm_rec_empty_dir' ) {
            my $dir_path = shift @$cmd_conf;
            $all_ok = 0 unless rm_rec_empty_dir( $dir_path );

        }

    } # foreach

    return $all_ok;
}

sub check_minimum_free_space {
    my ( $dconf, $path ) = @_;

    my $min_fs_MB = 100;
    $min_fs_MB = $dconf->{'minimum_free_space'} if defined $dconf->{'minimum_free_space'};

    $path = $dconf->{dest_dir} unless defined $path;

    my $real_path = readlink( $path );
    $real_path = $path unless $real_path;

    my $df_ref = dfportable( $real_path, 1024*1024 );
    unless ( defined $df_ref ) {
        print "ERROR: Can't determine free space on device for '$path' (real path '$real_path')." if $ver >= 1;
        return 0;
    }

    my $free_MB =  $df_ref->{bfree};
    $free_MB = int( $free_MB + 0.5 );
    if ( $free_MB < $min_fs_MB ) {
        print "ERROR: There is not required amount of free space ($free_MB MB < $min_fs_MB MB) on device (path '$path', real path '$real_path').\n" if $ver >= 1;
        return 0;
    }

    print "Free space on device ok ($free_MB MB >= $min_fs_MB MB).\n" if $ver >= 4;
    return 1;
}

sub process_unrar_dir_ok {
    my (
        $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep,
        $ud_err_code, $base_dir
    ) = @_;

    if ( $sub_dir ) {
        if ( $dconf->{save_ok_info} ) {
            # Save state when extracted ok.
            my $base_info = {
                ok => 1,
                type => 'rar',
            };
            my $save_full_info = 1;
            save_item_rec_content_info( $state, $dconf, $base_dir, $sub_dir, $base_info, $save_full_info );
        }

        # Add this to done list.
        push @$finish_cmds, [ 'save_done', $sub_dir ];
    }

    # Finish command.
    if ( scalar @$finish_cmds ) {
        dumper( "Finishing prev sub_dir '$sub_dir', deep $deep", $finish_cmds, 1 ) if $ver >= 5;
        do_cmds( $state, $dconf, $finish_cmds );
    }

    # Empty stacks.
    @$undo_cmds = ();
    @$finish_cmds = ();

    return save_state( $state, $dconf );
}

sub process_unrar_dir_err {
    my (
        $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep,
        $ud_err_code, $base_dir, $save_info
    ) = @_;

    if ( $sub_dir && $save_info ) {

        # Save state when error occured.
        my $base_info = {
            error => 1,
            error_info => {
                # log => $dir_log,
                type => 'rar',
                err_code => $ud_err_code,
            },
        };
        dumper( 'Inserting new error info', $base_info ) if $ver >= 5;
        my $save_full_info = ( $dconf->{save_err_info} );
        save_item_rec_content_info( $state, $dconf, $base_dir, $sub_dir, $base_info, $save_full_info );
        # dumper( '$state', $state ); # debug
    }

    # Undo command.
    @$undo_cmds = reverse @$undo_cmds;
    dumper( "Undo cmds (reversed)", $undo_cmds, 1 ) if $ver >= 5;
    do_cmds( $state, $dconf, $undo_cmds );

    # Empty stacks.
    @$undo_cmds = ();
    @$finish_cmds = ();

    return save_state( $state, $dconf );
}

sub process_unrar_archive_ok {
    my (
        $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep,
        $file_sub_path, $rar_parts_list
    ) = @_;

    # Finish command.
    if ( scalar @$finish_cmds ) {
        dumper( "Finishing archive $file_sub_path (deep $deep):", $finish_cmds, 1 ) if $ver >= 5;
        do_cmds( $state, $dconf, $finish_cmds );
    }

    # Empty stacks.
    @$undo_cmds = ();
    @$finish_cmds = ();

    return save_state( $state, $dconf );
}

sub process_unrar_archive_err {
    my (
        $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep,
        $file_sub_path, $rar_parts_list
    ) = @_;

    # ToDo save error - check for modifications next time.

    # Undo command.
    @$undo_cmds = reverse @$undo_cmds;
    dumper( "Undoing archive '$file_sub_path' (deep $deep):", $undo_cmds, 1 ) if $ver >= 5;
    do_cmds( $state, $dconf, $undo_cmds );

    # Empty stacks.
    @$undo_cmds = ();
    @$finish_cmds = ();

    return save_state( $state, $dconf );
}

=head2 unrar_dir

Return
* undef if extracted ok,
* -2 on foreign error (e.g. can't list directory structure),
* -3 on unrar error and
* -4 on fatal foreign error (e.g. not free space),
* -5 quit keypress.

=cut

sub unrar_dir {
    my ( $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep ) = @_;

    $keypress_obj->process_keypress();
    return -5 if $keypress_obj->get_exit_keypressed();

    return -4 unless check_minimum_free_space( $dconf );

    if ( 0 && $ver >= 5 && $sub_dir eq '/subdir10/ssdB' ) {
        print "SIMULATED ERROR fro subdir '$sub_dir'.\n";
        return -2;
    }

    my $base_dir = $dconf->{src_dir};

    my $full_src_dir = catdir( $base_dir, $sub_dir );
    print "Entering directory '$full_src_dir'\n" if $ver >= 3;

    # Save mtime to cache for resurection.
    $src_dir_mtimes->{ $sub_dir } = get_item_mtime( $full_src_dir );

    my $items = load_dir_content( $full_src_dir );
    return -2 unless defined $items;
    return undef unless scalar @$items;

    my $space = '  ' x $deep;


    # dirs
    foreach my $name ( sort @$items ) {

        my $new_sub_dir = catdir( $sub_dir, $name );
        next if exists $state->{done}->{ $new_sub_dir };

        my $path = catdir( $base_dir, $new_sub_dir );

        # directories only
        next unless -d $path;

        if ( $deep + 1 == $dconf->{basedir_deep} ) {
            # Check change time.
            my $max_mtime = get_rec_dir_mtime( $path );
            return -2 unless defined $max_mtime;

            print "Directory '$path' max mtime " . (localtime $max_mtime) . "\n" if $ver >= 4;
            if ( defined $dconf->{min_dir_mtime} ) {
                if ( time() - $dconf->{min_dir_mtime} < $max_mtime ) {
                    print "Directory '$path' max mtime " . (localtime $max_mtime) . " is too high.\n" if $ver >= 2;
                    next;
                }
                print "Directory '$path' max mtime " . (localtime $max_mtime) . " is low enought.\n" if $ver >= 4;
            }

            if ( exists $state->{info}->{ $new_sub_dir } ) {
                my $last_info = ${$state->{info}->{ $new_sub_dir }}[-1];
                my $last_hash = $last_info->{content_meta_hash};
                # dumper( 'info', $last_info ); # debug
                my ( $new_content_info, $new_hash ) = get_content_info_and_hash( $base_dir, $new_sub_dir );
                if ( $new_hash eq $last_hash ) {
                    print "Directory '$path' content hash is same. Skipping unpacking.\n" if $ver >= 3;
                    next;
                }
                print "Directory '$path' content hash changed.\n" if $ver >= 4;
            }
        }

        do_for_dir( $dconf, $finish_cmds, $undo_cmds, $base_dir, $new_sub_dir, $name );

        if ( $dconf->{recursive} ) {

            # Going deeper and deeper inside directory structure.
            my $ud_err_code = unrar_dir( $state, $undo_cmds, $finish_cmds, $dconf, $new_sub_dir, $deep+1);

            # Unrar ok.
            unless ( defined $ud_err_code ) {
                print "Dir '$new_sub_dir' unrar status ok.\n" if $ver >= 5;

                if ( $deep < $dconf->{basedir_deep} ) {
                    process_unrar_dir_ok(
                        $state, $undo_cmds, $finish_cmds, $dconf, $new_sub_dir, $deep,
                        $ud_err_code, $base_dir
                    );
                }

                next; # Continue to next directory item.
            }

            # Unrar failed.
            print "Dir '$new_sub_dir' unrar failed (err code $ud_err_code).\n" if $ver >= 5;

            my $err_is_too_fatal = ( $ud_err_code <= -4 ); # -4, -5, ... Too fatal.

            if ( $deep < $dconf->{basedir_deep} ) {
                my $save_info = ( ! $err_is_too_fatal );
                process_unrar_dir_err(
                    $state, $undo_cmds, $finish_cmds, $dconf, $new_sub_dir, $deep,
                    $ud_err_code, $base_dir, $save_info
                );
            }

            if ( $deep < $dconf->{basedir_deep} ) {
                return $ud_err_code if $err_is_too_fatal;
                next; # Continue to next directory item.
            }

            # Unrar failed and nothing to undo (too deep).
            return $ud_err_code;
        }

    } # end foreach dir


    my $files_done = {};
    my $extract_error = 0;

    # Find first parts or rars.
    # 0 .. to unrar (not processed), 1 .. unrared ok, -1 .. unrar error
    my $parts_status = {};
    foreach my $name ( sort @$items ) {
        my $file_sub_path = catfile( $sub_dir, $name );
        next if exists $state->{done}->{ $file_sub_path };

        my $path = catfile( $full_src_dir, $name );
        # all files
        if ( -f $path ) {
            #print "$space$name ($path) " if $ver >= 3;

            if ( $name !~ /\.(r\d+|rar|\d{3})$/ ) {
                print "File '$name' isn't RAR archive.\n" if $ver >= 4;
                next;
            }

            my ( $rar_rc, $extract_err, $files_extracted, $rar_parts_list ) = do_for_rar_file(
                $dconf, $finish_cmds, $base_dir, $sub_dir, $name, $items
            );

            unless ( exists $parts_status->{$name} ) {
                $parts_status->{$name} = 0;
            }

            print "Subdir '$sub_dir', file '$name' -- rar_rc $rar_rc\n" if $ver >= 8;
            if ( $ver >= 9 ) {
                dumper( "files_extracted", $files_extracted ) if $files_extracted;
                dumper( "rar_parts_list", $rar_parts_list ) if $rar_parts_list;
            }
            if ( $rar_rc != 0 ) {
                # No first part of multipart archive.
                if ( $rar_rc == 1 ) {
                    print "Extract error: '$extract_err'\n" if $ver >= 6;
                    $files_done->{ $file_sub_path } = 1;
                    next;
                }

                # Is first part -> was extracted.

                # If error -> do not process these archives as normal files
                # in next code.
                foreach my $part ( @$rar_parts_list ) {
                    next unless defined $part;
                    my $part_sub_path = catfile( $sub_dir, $part );
                    $files_done->{ $part_sub_path } = 1;
                    $parts_status->{$part} = $extract_err ? -1 : 1;
                }

                # Add all extracted files to undo list.
                foreach my $ext ( @$files_extracted ) {
                    print "Extracted file '$ext' processed.\n" if $ver >= 5;
                    my $ext_path = catfile( $dconf->{dest_dir}, $sub_dir, $ext );
                    next unless -e $ext_path;
                    push @$undo_cmds, [ 'unlink', $ext_path ];
                }

                # Extract error.
                if ( $extract_err ) {
                    $extract_error = 1;
                    print "Rar archive extractiong error: $extract_err.\n" if $ver >= 2;
                    if ( $deep >= $dconf->{basedir_deep} ) {
                        print "Leaving dir '$sub_dir' ($deep, $dconf->{basedir_deep}).\n" if $ver >= 3;
                        return -3;
                    }
                    print "Continuing inside subdir '$sub_dir' ($deep, $dconf->{basedir_deep}) after error.\n" if $ver >= 3;

                    if ( $deep < $dconf->{basedir_deep} ) {
                        process_unrar_archive_err(
                            $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep,
                            $file_sub_path, $rar_parts_list
                        );
                    }

                    $keypress_obj->process_keypress();
                    return -5 if $keypress_obj->get_exit_keypressed();
                    next;
                }

                # Extracted ok.
                # Remove rar archives from list.
                foreach my $part ( @$rar_parts_list ) {
                    next unless defined $part;
                    print "Archive part '$part' processed.\n" if $ver >= 5;
                    my $part_path = catfile( $sub_dir, $part );
                    push @$finish_cmds, [ 'save_done', $part_path ] if $deep < $dconf->{basedir_deep};
                    if ( $dconf->{remove_done} ) {
                        my $full_part_path = catfile( $full_src_dir, $part );
                        push @$finish_cmds, [ 'unlink', $full_part_path ];
                    }
                }

                if ( $deep < $dconf->{basedir_deep} ) {
                    process_unrar_archive_ok(
                        $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep,
                        $file_sub_path, $rar_parts_list
                    );
                }

                $keypress_obj->process_keypress();
                return -5 if $keypress_obj->get_exit_keypressed();

            }
        }
    }

    dumper( '$parts_status', $parts_status ) if $ver >= 6;
    my $not_processed_parts_found = 0;
    foreach my $part ( keys %$parts_status ) {
        if ( $parts_status->{$part} == 0 ) {
            $not_processed_parts_found = 1;
            print "Extraction error. Archive part '$part' found, but not processed.\n" if $ver >= 5;
            last;
        }
    }

    # No rar files.
    # Use $files_done.
    foreach my $name ( sort @$items ) {
        my $file_sub_path = catfile( $sub_dir, $name );
        next if exists $state->{done}->{ $file_sub_path };
        next if exists $files_done->{ $file_sub_path };

        my $path = catfile( $full_src_dir, $name );
        # all files
        if ( -f $path ) {
            #print "$space$name ($path) " if $ver >= 3;
            do_for_norar_file( $dconf, $finish_cmds, $base_dir, $sub_dir, $name );
            push @$finish_cmds, [ 'save_done', $file_sub_path ] if $deep < $dconf->{basedir_deep};
        }
    }

    return -3 if $extract_error;
    return -3 if $not_processed_parts_found;

    if ( $deep >= $dconf->{basedir_deep} ) {
        push @$finish_cmds, [
            'set_saved_dir_mtime',
            catdir( $dconf->{dest_dir}, $sub_dir ),
            $sub_dir,
        ];
    }

    # Recursive remove main dir.
    if ( $deep == $dconf->{basedir_deep} ) {
        if ( $dconf->{remove_done} ) {
            push @$finish_cmds, [ 'rm_rec_empty_dir', $full_src_dir ];
        }
    }

    return undef;
}

sub unrar_dir_start {
    my ( $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep ) = @_;

    # Reset.
    $src_dir_mtimes = {};

    my $ud_err_code = unrar_dir(
        $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep
    );

    my $base_dir = $dconf->{src_dir};

    # Unrar ok.
    unless ( defined $ud_err_code ) {
        dumper( 'Last $finish_cmds', $finish_cmds ) if $ver >= 4;
        process_unrar_dir_ok(
            $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep,
            $ud_err_code, $base_dir
        );

       return undef;
    }

    my $err_is_too_fatal = ( $ud_err_code <= -4 ); # -4, -5, ... Too fatal.
    my $save_info = ( ! $err_is_too_fatal );

    # Unrar failed.
    dumper( 'Last $undo_cmds', $undo_cmds ) if $ver >= 4;
    process_unrar_dir_err(
        $state, $undo_cmds, $finish_cmds, $dconf, $sub_dir, $deep,
        $ud_err_code, $base_dir, $save_info
    );

    return $ud_err_code;
}

sub remove_item_from_state {
    my ( $state, $item_name ) = @_;

    if ( exists $state->{done}->{$item_name} ) {
        print "Removing item '$item_name' from state:done.\n" if $ver >= 6;
        delete $state->{done}->{$item_name};
    }
    if ( exists $state->{info}->{$item_name} ) {
        print "Removing item '$item_name' from state:info.\n" if $ver >= 6;
        delete $state->{info}->{$item_name};
    }
    return 1;
}

my $ret_code = main();
$keypress_obj->cleanup_before_exit() if defined $keypress_obj;

# 0 is ok, 1 is error. See Unix style exit codes.
exit(1) unless $ret_code;
exit(0);


=head1 AUTHOR

Michal Jurosz <au@mj41.cz>

=head1 COPYRIGHT

Copyright (c) 2009-2010 Michal Jurosz. All rights reserved.

=head1 LICENSE

auto-unrar is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

auto-unrar is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Foobar.  If not, see <http://www.gnu.org/licenses/>.

=head1 BUGS

L<http://github.com/mj41/auto-unrar/issues>

=cut