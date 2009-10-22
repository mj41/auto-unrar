# not exists .part .rar has >0 filesize
# move from dirs, rename
# create crc database

use strict;
use warnings;

use Carp qw(carp croak verbose);
use FindBin qw($RealBin);
use File::Spec::Functions qw/:ALL splitpath/;
use File::Path;
use File::Copy;
use Data::Dumper;

use lib 'lib';
use App::KeyPress;
use RAR::UnrarMJ qw(list_files_in_archive process_file);
use YAML::Any qw/LoadFile/;

my $ver = $ARGV[0];
$ver = 2 unless defined $ver;


my $dest_directory = catdir( $RealBin, '..', 'extracted' );
$dest_directory = rel2abs( $dest_directory ) . '\\';
print "Destination directory: '$dest_directory'.\n" if $ver >= 5;

my $extracted_ok_dir = catdir( $RealBin, '..', 'extracted-arch' );
$extracted_ok_dir = rel2abs( $extracted_ok_dir ) . '\\';
print "Extracted done ok directory for archives: '$extracted_ok_dir'.\n" if $ver >= 5;

my $dir_to_extract = catdir( $RealBin, '..', 'extract' ) . '\\';
my $items = {
    $dir_to_extract => { recursive => 1, },
};

croak "Dir '$dir_to_extract' not found." unless -d $dir_to_extract;
croak "Dir '$dest_directory' not found." unless -d $dest_directory;
croak "Dir '$extracted_ok_dir' not found." unless -d $extracted_ok_dir;


my $keypress_obj = App::KeyPress->new(
    $ver,
    0 # $debug
);


sub my_croak {
    my ( $err_msg ) = @_;
    $keypress_obj->cleanup_before_exit();
    croak $err_msg;
}


my $pass_conf = undef;
my $pass_conf_fpath = catfile( $RealBin, 'unrar-passwords.yml' );
if ( -f $pass_conf_fpath ) {
    ( $pass_conf ) = YAML::Any::LoadFile( $pass_conf_fpath );
    my_croak( "Password configuration loaded from '$pass_conf_fpath' is empty.\n") unless $pass_conf;
    print Dumper( $pass_conf ) if $ver >= 5;
}



sub get_passwords {
    my ( $file ) = @_;
    return $pass_conf->{all};
}


sub header {
    my ( $file ) = @_;
    print "==================================================================================================================\n";
    print "File: $file\n";
}



sub process_archive_file {
    my ( $conf, $base_dir, $sub_dir, $file_name ) = @_;

    my $file_path = $base_dir . $sub_dir . $file_name;

    my $dest_directory = $conf->{dest_directory} . $sub_dir . '\\';
    mkpath( $dest_directory, { mode => 0777, } ) unless -d $dest_directory;

    my ( $blockencrypted, $needpassword, $continue ) = RAR::UnrarMJ::extract_headers($file_path,undef,0);

    my $archive = $file_path;
    my $password = undef;

    if ( !$continue && $ver >= 4 ) {
        header($archive);
        print "First part or no multi-part archive.\n";
    }

    if ( !$continue ) {
        print "Archive file '$archive'\n" if $ver >= 1;
        my @arch_info;


        my $header_extracted_ok = 0;
        if ( $blockencrypted ) {
             my $all_passwords = get_passwords( $archive );
             foreach my $t_pass ( @$all_passwords ) {
                print "  ... extracting header with password '$t_pass'\n" if $ver >= 1;
                print "  " if $ver >= 1;
                @arch_info = RAR::UnrarMJ::list_files_in_archive( $archive, $t_pass, 0 );
                if ( ref $arch_info[0] eq 'HASH' ) {
                    $password = $t_pass;
                    last;
                }
                print "  ... password is not valid.\n" if $ver >= 1;
            }
            if ( $password ) {
                $header_extracted_ok = 1;
                print "  ... done ok. Valid password is '$password'.\n" if $ver >= 1;
            } else {
                print "  ... failed. Valid password not found.\n" if $ver >= 1;
                return 1;
            }

        } else {
            print "  ... extracting header\n" if $ver >= 1;
            print "  " if $ver >= 1;
            @arch_info = RAR::UnrarMJ::list_files_in_archive( $archive, $password, 0 );
            if ( ref $arch_info[0] eq 'HASH' ) {
                $header_extracted_ok = 1;
                print "... done ok.\n" if $ver >= 1;
            } else {
                print "... failed, error '$arch_info[0]'.\n" if $ver >= 1;
            }
        }

        if ( $ver >= 4 ) {
            print Dumper( \@arch_info );
        }


        my %archives = ();
        foreach my $item_num ( 0..$#arch_info ) {
            my $item_info = $arch_info[ $item_num ];
            next unless $item_info;
            #print "  $item_info->{ArcName}\n";
            $archives{ $item_info->{ArcName} } = 1;
        }


        #print "skipping -> debug\n"; return 1;

        my $extracted_ok = 0;
        if ( !$blockencrypted && $needpassword ) {
             my $all_passwords = get_passwords( $archive );
             foreach my $t_pass ( @$all_passwords ) {
                print "  ... extracting with password '$t_pass'\n" if $ver >= 1;
                print "  " if $ver >= 1;
                my $err_msg = RAR::UnrarMJ::process_file( $archive, $t_pass, $dest_directory );
                unless ( $err_msg ) {
                    $password = $t_pass;
                    last;
                }
                print "... password is not valid.\n" if $ver >= 1;
            }
            if ( $password ) {
                $extracted_ok = 1;
                print "  ... done ok. Valid password is '$password'.\n" if $ver >= 1;
            } else {
                print "  ... failed. Valid password not found.\n" if $ver >= 1;
                return 1;
            }

        } else {
            print "  ... extracting content\n" if $ver >= 1;
            print "  " if $ver >= 1;
            my $error_msg = process_file( $archive, $password, $dest_directory );
            if ( defined $error_msg ) {
                print "... failed, error '$error_msg'.\n" if $ver >= 1;
            } else {
                $extracted_ok = 1;
                print "... done ok.\n" if $ver >= 1;
            }
        }
        print "\n" if $ver >= 1;

        if ( $extracted_ok ) {
            my $done_dir = $conf->{extracted_ok_dir} . $sub_dir;
            mkpath( $done_dir, { mode => 0777, } ) unless -d $done_dir;
            foreach my $archive_fpath ( keys %archives ) {
                unless ( move($archive_fpath,$done_dir.'\\') ) {
                    print "Can't move '$archive_fpath' to '$done_dir'.\n" if $ver >= 1;
                }
            }
        }

        return 1;
    }

    return 1;
}


sub do_for_file {
    my ( $type, $conf, $base_dir, $sub_dir, $file_name, $no_status ) = @_;

    my $file_path = $base_dir . $sub_dir . $file_name;

    if ( my ( $a_num ) = $file_name =~ / \. ( ?: rar | r(\d+) | (\d{3}) ) $ /ix ) {
        return 1 unless $type eq 'rar';

        if ( (not defined $a_num) || $a_num == 0 ) {
            print " - OK\n" if !$no_status && $ver >= 3;
            return process_archive_file( $conf, $base_dir, $sub_dir, $file_name );
        }
    }

    return 1 unless $type eq 'norar';

    my $dest_directory = $conf->{dest_directory} . $sub_dir . '\\';
    mkpath( $dest_directory, { mode => 0777, } ) unless -d $dest_directory;

    my $new_file_path = $dest_directory . $file_name;
    if ( -e $new_file_path ) {
        my $num = 2;
        my $new_file_path_num;
        do {
            $new_file_path_num = $new_file_path . '.' . $num;
            $num++;
        } while ( -e $new_file_path_num );
        $new_file_path = $new_file_path_num;
    }
    unless ( move($file_path,$new_file_path) ) {
        print "Can't move '$file_path' to '$new_file_path'.\n" if $ver >= 1;
    }
    print " - SKIP\n" if !$no_status && $ver >= 3;
    return 1;
}


sub do_for_dir {
  my ( $dir_path, $dir_name ) = @_;
  return 1;
}



sub load_dir_content {
    my ( $dir_name ) = @_;

    if ( not opendir(DIR, $dir_name) ) {
        print STDERR "Directory '$dir_name' not open for read.\n" ;
        return undef;
    }
    my @all_items = readdir(DIR);
    close(DIR);

    my @items = ();
    foreach my $name ( @all_items ) {
        if ($name =~ /^\.$/) { next; }
        if ($name =~ /^\..$/) { next; }
        if ($name =~ /^\s*$/) { next; }
        push @items, $name;
    }

    return @items;
}


sub process_dirs {
    my ( $conf, $base_dir, $sub_dir, $space ) = @_;
    $base_dir ||= '.\\';
    $sub_dir ||= '';
    $space ||= '';

    my $dir_name = $base_dir . $sub_dir;
    my @items = load_dir_content( $dir_name );

    my ( $name, $path, $file_out_name, $file_in_name );

    # dirs
    my $new_sub_dir;
    foreach $name (sort @items) {
        $new_sub_dir = $sub_dir . $name . '\\';
        $path = $base_dir . $new_sub_dir;

        # directories
        if ( -d $path ) {
            print "$space$name\n" if $ver >= 3;
            do_for_dir($path, $name);
            if ( $conf->{recursive} ) {
                if (not &process_dirs( $conf, $base_dir, $new_sub_dir, $space.'  ') ) {
                    return 0;
                }
            }
        }
    }


    # rar
    foreach $name ( sort @items ) {
        $path = $dir_name . $name;
        #files
        if ( -f $path ) {
            print "$space$name ($path) " if $ver >= 3;
            do_for_file( 'rar', $conf, $base_dir, $sub_dir, $name );
            $keypress_obj->process_keypress();
        }
    }


    # norar
    foreach $name ( sort @items ) {
        $path = $dir_name . $name;
        #files
        if ( -f $path ) {
            print "$space$name ($path) " if $ver >= 3;
            do_for_file( 'norar', $conf, $base_dir, $sub_dir, $name );
            $keypress_obj->process_keypress();
        }
    }


    # remove empty dirs
    my @other_items = load_dir_content( $dir_name );
    #print  "--- $dir_name " . scalar(@other_items) . "\n";
    if ( scalar(@other_items) == 0 ) {
        #print "trying rmdir: '$dir_name'\n";
        #chmod( 0777, $dir_name );
        $! = undef;
        unless ( rmdir($dir_name) ) {
            print "rmdir '$dir_name' failed: $!\n";
        }
    }

    return 1;
}




foreach my $item ( keys %$items ) {
    my $item_conf = $items->{$item};

    $item_conf->{dest_directory} = $dest_directory;
    $item_conf->{extracted_ok_dir} = $extracted_ok_dir;
    if ( -d $item ) {
        process_dirs( $item_conf, $item, '', '' );

    } elsif ( -f $item ) {
        my ( $volume, $directory, $file_name ) = File::Spec->splitpath( $item );
        do_for_file( $item_conf, $item, '', $file_name, 1 );

    } else {
        print "No file or directory '$item'.\n" if $ver >= 1;
    }
}

$keypress_obj->cleanup_before_exit();
