# ToDo
# min_dir_mtime
# check free space
# duplicate names
# unrar to temp directory
# * compare fname and fname.1 content, remove .1 if same
# refactore, better configuration, help, ...
# merge changes to Archive::Rar

use strict;
use warnings;

use Carp qw(carp croak verbose);
use FindBin qw($RealBin);
use File::Spec::Functions qw/:ALL splitpath/;
use File::Path;
use File::Copy;

use Storable;
use Archive::Rar;
use Data::Dumper;


use lib 'lib';
use App::KeyPress;


my $run_type = $ARGV[0];
$run_type = 'test' unless $run_type;

my $ver = $ARGV[1];
$ver = 2 unless defined $ver;


my $keypress_obj = App::KeyPress->new(
    $ver,
    0 # $debug
);


sub my_croak {
    my ( $err_msg ) = @_;
    $keypress_obj->cleanup_before_exit();
    croak $err_msg;
}



my $dirs_conf = [
];

# devel
if ( $run_type ne 'final' ) {
    $dirs_conf = [
        {
            name => 'test',
            src_dir => '/mnt/pole2/scripts/auto-unrar-test/in',
            dest_dir => '/mnt/pole2/scripts/auto-unrar-test/out',
            done_list => '/mnt/pole2/scripts/auto-unrar-test/test-unrar.db',
            exclude_list => '/mnt/pole2/scripts/auto-unrar-test/rsync-exclude.txt',
            done_list_deep => 1,
            recursive => 1,
            remove_done => 1,
            move_non_rars => 1,
            min_dir_mtime => 3*60*60,
        },
    ];
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
    my @all_items = readdir($dir_h);
    close($dir_h);

    my @items = ();
    foreach my $name ( @all_items ) {
        if ($name =~ /^\.$/) { next; }
        if ($name =~ /^\..$/) { next; }
        if ($name =~ /^\s*$/) { next; }
        push @items, $name;
    }

    return @items;
}


sub do_cmd_sub {
    my ( $cmd_sub, $msg ) = @_;

    my $done_ok = 0;
    my $out_data = undef;
    my $sleep_time = 1;
    while ( not $done_ok ) {
        my $ret_val = $cmd_sub->();
        if ( ref $ret_val ) {
            ( $done_ok, $out_data ) = @$ret_val;
        } else {
            $done_ok = $ret_val;
        }

        unless ( $done_ok ) {
            if ( $ver >= 1 ) {
                print $msg;
                print " Sleeping $sleep_time s ...\n";
            }
            $keypress_obj->sleep_and_process_keypress( $sleep_time );
            $sleep_time = $sleep_time * $sleep_time if $sleep_time < 60*60; # one hour
        }
    }

    return $out_data;
}


sub save_item_done {
    my ( $done_list, $dconf, $item_name ) = @_;

    $done_list->{$item_name} = time();

    do_cmd_sub(
        sub { store( $done_list, $dconf->{done_list} ); },
        "Store done list to '$dconf->{done_list}' failed."
    );
    print "Item '$item_name' saved to done_list.\n" if $ver >= 5;


    if ( $dconf->{exclude_list} ) {
        my $out_fh = do_cmd_sub(
            sub {
                my $out_fh = undef;
                my $ok = open( $out_fh, '>', $dconf->{exclude_list} );
                return [ $ok, $out_fh ];
            },
            "Open file '$dconf->{exclude_list}' for write."
        );
        foreach my $item ( sort keys %$done_list ) {
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


sub do_for_dir {
    my ( $dconf, $base_dir, $sub_dir, $dir_name ) = @_;

    my $dir_path = catfile( $base_dir, $sub_dir, $dir_name );
    return 0 unless -d $dir_path;

    my $dest_dir_path = catdir( $dconf->{dest_dir}, $sub_dir, $dir_name );
    mkdir( $dest_dir_path, 0777 ) unless -d $dest_dir_path;

    return 1;
}


sub do_for_rar_file {
    my ( $dconf, $base_dir, $sub_dir, $file_name, $dir_items ) = @_;


    my $base_name_part = undef;
    my $is_rar_archive = 0;
    my $part_num = undef;
    my $multipart_type = undef;

    if ( $file_name =~ /^(.*)\.part(\d+)\.rar$/ ) {
        $base_name_part = $1;
        $part_num = $2;
        $is_rar_archive = 1;
        $multipart_type = 'part';

    } elsif ( $file_name =~ /^(.*)\.rar$/ ) {
        $base_name_part = $1;
        $part_num = 1;
        $is_rar_archive = 1;
        # initial value, is set to '' unless other parts found
        $multipart_type = 'mr';
    }

    return ( 0, "File isn't rar archive", undef, undef ) unless $is_rar_archive;

    my $multipart_error_msg = "File is part of multiparts archive, but isn't first part.";
    return ( 1, $multipart_error_msg, undef, undef ) if $multipart_type && ($part_num != 1);


    my $file_path = catfile( $base_dir, $sub_dir, $file_name );

    my $dest_dir = catdir( $dconf->{dest_dir}, $sub_dir );
    mkpath( $dest_dir, { mode => 0777, verbose => ($ver >= 3), } ) unless -d $dest_dir;

    my $rar_obj = Archive::Rar->new(
        '-archive' => $file_path,
        '-initial' => $dest_dir
    );
    $rar_obj->List();
    my @files_extracted = $rar_obj->GetBareList();

    if ( $ver >= 6 ) {
        print "Input file '$file_name':\n";
        $rar_obj->PrintList();
        dumper( 'rar_obj->list', $rar_obj->{list} );
        dumper( 'list', \@files_extracted );
    }

    my @rar_parts_list = ( $file_name );

    my %files_extracted = map { $_ => 1 } @files_extracted;
    #dumper( '%files_extracted', \%files_extracted );

    my $other_part_found = 0;
    NEXT_FILE: foreach my $next_file_name ( sort @$dir_items ) {

        my $other_part_num = undef;
        if ( $multipart_type eq 'part' ) {
            if ( $next_file_name =~ /^\Q$base_name_part\E\.part(\d+)\.rar$/ ) {
                $other_part_num = $1;
            }

        } elsif ( $multipart_type eq 'mr' ) {
            if ( $next_file_name =~ /^\Q$base_name_part\E\.r(\d+)$/ ) {
                $other_part_num = $1 + 2;
            }
        }

        if ( defined $other_part_num && $part_num != $other_part_num ) {
            $other_part_found = 1;

            print "Other rar part added '$next_file_name' ($other_part_num) for base_name '$base_name_part' and type '$multipart_type'.\n" if $ver >= 5;
            push @rar_parts_list, $next_file_name;

            my $next_file_path = catfile( $base_dir, $sub_dir, $next_file_name );
            my $next_rar_obj = Archive::Rar->new(
                '-archive' => $next_file_path,
                #'-quiet' => 1, # no way
                '-initial' => $dest_dir
            );
            $next_rar_obj->List();
            my @next_files_extracted = $next_rar_obj->GetBareList();
            next NEXT_FILE unless scalar @next_files_extracted;

            #dumper( '@next_files_extracted', \@next_files_extracted );
            foreach my $next_file ( @next_files_extracted ) {
                next unless defined $next_file; # Archive::Rar bug?
                next if exists $files_extracted{$next_file};

                $files_extracted{$next_file} = 1;
                push @files_extracted, $next_file;
                print "Addding new extracted file '$next_file' to list from rar part num $other_part_num.\n" if $ver >= 5;
            }
        }

    } # foreach end
    $multipart_type = '' unless $other_part_found;

    print "File '$file_name' - base_name_part '$base_name_part', is_rar_archive $is_rar_archive, part_num $part_num, multipart_type '$multipart_type'\n" if $ver >= 5;


    my $res = $rar_obj->Extract(
        '-donotoverwrite' => 1,
        '-quiet' => 1,
        '-lowprio' => 1
    );
    if ( $res ) {
        print "Error $res in extracting from '$file_path'.\n" if $ver >= 1;
        return ( 1, $res, [], \@rar_parts_list );
    }
    return ( 1, undef, \@files_extracted, \@rar_parts_list );
}


sub do_for_norar_file {
    my ( $dconf, $base_dir, $sub_dir, $file_name ) = @_;

    return 1 if not $dconf->{move_non_rars} && not $dconf->{cp_non_rars};


    my $file_path = catfile( $base_dir, $sub_dir, $file_name );

    my $dest_dir = catdir( $dconf->{dest_dir}, $sub_dir );
    mkpath( $dest_dir, { mode => 0777, verbose => ($ver >= 3), } ) unless -d $dest_dir;

    my $new_file_path = catfile( $dest_dir, $file_name );
    if ( -e $new_file_path ) {
        my $num = 2;
        my $new_file_path_num;
        do {
            $new_file_path_num = $new_file_path . '.' . $num;
            $num++;
        } while ( -e $new_file_path_num );
        $new_file_path = $new_file_path_num;
    }

    if ( $dconf->{move_non_rars} ) {
        print "Moving '$file_path' to '$new_file_path'.\n" if $ver >= 3;
        $! = undef;
        unless ( move($file_path,$new_file_path) ) {
           print "Command mv '$file_path' '$new_file_path' failed: $! $^E\n" if $ver >= 1;
           return 0;
        }

    } elsif ( $dconf->{cp_non_rars} ) {
        print "Copying '$file_path' to '$new_file_path'.\n" if $ver >= 3;
        $! = undef;
        unless ( cp($file_path,$new_file_path) ) {
           print "Command cp '$file_path' '$new_file_path' failed: $! $^E\n" if $ver >= 1;
           return 0;
        }
    }

    return 1;
}


sub unrar_dir {
    my ( $done_list, $dconf, $sub_dir, $deep ) = @_;

    my $base_dir = $dconf->{'src_dir'};

    my $dir_name = catdir( $base_dir, $sub_dir );
    print "Entering directory '$dir_name'\n" if $ver >= 3;

    my @items = load_dir_content( $dir_name );

    $keypress_obj->process_keypress();

    my $space = '  ' x $deep;

    # dirs
    foreach my $name ( sort @items ) {
        my $new_sub_dir = catdir( $sub_dir, $name );
        next if exists $done_list->{ $new_sub_dir };

        my $path = catdir( $base_dir, $new_sub_dir );

        # directories
        next unless -d $path;
        #print "$space$name\n" if $ver >= 3;

        do_for_dir( $dconf, $base_dir, $sub_dir, $name );
        if ( $dconf->{recursive} ) {
            if ( not unrar_dir( $done_list, $dconf, $new_sub_dir, $deep+1) ) {
                return 0;
            }
        }
        save_item_done( $done_list, $dconf, $new_sub_dir ) if $deep < $dconf->{done_list_deep};
   }

    my $files_done = {};
    # find first parts or rars
    foreach my $name ( sort @items ) {
        my $file_sub_path = catfile( $sub_dir, $name );
        next if exists $done_list->{ $file_sub_path };

        my $path = catdir( $dir_name, $name );
        # all files
        if ( -f $path ) {
            #print "$space$name ($path) " if $ver >= 3;

            if ( $name !~ /\.(r\d+|rar)$/ ) {
                print "File '$name' isn't RAR archive.\n" if $ver >= 4;
                next;
            }

            my ( $is_rar, $extract_err, $files_extracted, $rar_parts_list ) = do_for_rar_file(
                $dconf, $base_dir, $sub_dir, $name, \@items
            );

            #print "$sub_dir, $name -- $is_rar, $extract_err\n";
            if ( $is_rar ) {

                # If error -> do not process these archives as normal files
                # in next code.
                foreach my $part ( @$rar_parts_list ) {
                    my $part_sub_path = catfile( $sub_dir, $part );
                    $files_done->{ $part_sub_path } = 1;
                }

                if ( not $extract_err ) {
                    # remove rar archives from list
                    foreach my $part ( @$rar_parts_list ) {
                        print "Archive part '$part' processed.\n" if $ver >= 5;
                        my $part_path = catfile( $sub_dir, $part );
                        save_item_done( $done_list, $dconf, $part_path ) if $deep < $dconf->{done_list_deep};
                        if ( $dconf->{remove_done} ) {
                            my $part_path = catdir( $dir_name, $part );
                            $! = undef;
                            unless ( unlink($part_path) ) {
                                print "Command unlink '$part_path' failed: $! $^E\n" if $ver >= 1;
                            }
                        }
                    }
                }
            }
        }
    }


    # no rar files
    foreach my $name ( sort @items ) {
        my $file_sub_path = catfile( $sub_dir, $name );
        next if exists $done_list->{ $file_sub_path };
        next if exists $files_done->{ $file_sub_path };

        my $path = catdir( $dir_name, $name );
        # all files
        if ( -f $path ) {
            #print "$space$name ($path) " if $ver >= 3;
            do_for_norar_file( $dconf, $base_dir, $sub_dir, $name );
            save_item_done( $done_list, $dconf, $file_sub_path ) if $deep < $dconf->{done_list_deep};
        }
    }

    return 1 unless $sub_dir;


    # remove empty dirs
    if ( $dconf->{remove_done} ) {
        my @other_items = load_dir_content( $dir_name );
        if ( scalar(@other_items) == 0 ) {
            $! = undef;
            unless ( rmdir($dir_name) ) {
                print "Command rmdir '$dir_name' failed: $! $^E\n" if $ver >= 1;
            }
        }
    }

    return 1;
}


foreach my $dconf ( @$dirs_conf ) {
    unless ( -d $dconf->{src_dir} ) {
        print "Input directory '$dconf->{src_dir}' doesn't exists.\n" if $ver >= 1;
        next;
    }

    unless ( -d $dconf->{dest_dir} ) {
        print "Output directory '$dconf->{dest_dir}' doesn't exists.\n" if $ver >= 1;
        next;
    }

    my $done_list = undef;
    if ( -e $dconf->{done_list} ) {
        $done_list = retrieve( $dconf->{done_list} );
    } else {
        $done_list = {

        };
    }

    dumper( 'dconf', $dconf ) if $ver >= 5;
    unrar_dir(
        $done_list,
        $dconf,
        '', # $sub_dir
        0  # $deep
    );

    dumper( "done list for '$dconf->{name}':", $done_list ) if $ver >= 5;

}

$keypress_obj->cleanup_before_exit();