######## RAR::UnrarMJ library  ########
#Author  : Michal Jurosz
#Email   : auto-unrar@mj41.cz
#Version Date: 21-10-2009
#License :GNU General Public License (GPL)
#Webpage : https://mj41.cz/wiki/auto-unrar

# Based on
######## RAR::Unrar library  ########
#Author  : Nikos Vaggalis
#Email   : nikos.vaggalis@gmail.com
#Version Date: 29-06-2009
#License :GNU General Public License (GPL)
#Webpage : https://sourceforge.net/projects/unrarextractrec/
#########

package RAR::UnrarMJ;

use 5.010000;
use strict;
use base qw(Exporter);
use Win32::API;
use Exporter;
use Carp qw(croak);

use constant COMMENTS_BUFFER_SIZE => 16384;

our @EXPORT_OK = qw(list_files_in_archive process_file);

our $VERSION = '1.02';

#unrar.dll internal functions
our (
    $RAROpenArchiveEx, $RARCloseArchive, $RAROpenArchive, $RARReadHeader,
    $RARReadHeaderEx,  $RARProcessFile,  $RARSetPassword, %donotprocess
);

################ PRIVATE METHODS ################

sub declare_win32_functions {
    $RAROpenArchiveEx =
      new Win32::API( 'unrar.dll', 'RAROpenArchiveEx', 'P', 'N' );
    $RARCloseArchive =
      new Win32::API( 'unrar.dll', 'RARCloseArchive', 'N', 'N' );
    $RAROpenArchive = new Win32::API( 'unrar.dll', 'RAROpenArchive', 'P', 'N' );
    $RARReadHeader = new Win32::API( 'unrar.dll', 'RARReadHeader', 'NP', 'N' );
    $RARReadHeaderEx =
      new Win32::API( 'unrar.dll', 'RARReadHeaderEx', 'NP', 'N' );
    $RARProcessFile =
      new Win32::API( 'unrar.dll', 'RARProcessFile', 'NNPP', 'N' );
    $RARSetPassword =
      new Win32::API( 'unrar.dll', 'RARSetPassword', 'NP', 'N' );
    return 1;
}

sub extract_headers {

    my ( $file, $password, $print ) = @_;
    $print = 1 unless defined $print;

    my $CmtBuf = pack( 'x' . COMMENTS_BUFFER_SIZE );
    my $continue;

    my $RAROpenArchiveDataEx = pack( 'ppLLPLLLLx32',
        $file, undef, 2, 0, $CmtBuf, COMMENTS_BUFFER_SIZE, 0, 0, 0 );
    my $RAROpenArchiveData = pack( 'pLLpLLL', $file, 2, 0, undef, 0, 0, 0 );
    my $RARHeaderData = pack( 'x260x260LLLLLLLLLLpLL',
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, undef, 0, 0 );

    my $handle1 = $RAROpenArchiveEx->Call($RAROpenArchiveDataEx)
      || croak "RAROpenArchiveEx failed";

    my (
        $arcname1, undef,    undef,     undef, $CmtBuf1,
        undef,     $CmtSize, $CmtState, $flagsEX
      )
      = unpack( 'ppLLP' . COMMENTS_BUFFER_SIZE . 'LLLLL',
        $RAROpenArchiveDataEx );

    !$RARCloseArchive->Call($handle1) || croak "RARCloseArchive failed";

    my $handle2 = $RAROpenArchive->Call($RAROpenArchiveData)
      || croak "RAROpenArchive failed";

    $flagsEX & 128
      || !$RARReadHeader->Call( $handle2, $RARHeaderData )
      || croak "RARCloseArchive failed";

    my ( $arcname2, $filename, $flags, $packsize ) =
      unpack( 'A260A260LL', $RARHeaderData );

    $CmtBuf1 = unpack( 'A' . $CmtSize, $CmtBuf1 );
    printf( "\nComments :%s\n", $CmtBuf1 ) if $print >= 1;

    printf( "\nArchive %s\n", $arcname2 ) if $print >= 1;
    printf( "\nPassword:\t%s",     ( $flags & 4 )     ? "yes"     : "no" ) if $print >= 1;

    printf( "\nVolume:\t\t%s",     ( $flagsEX & 1 )   ? "yes"     : "no" ) if $print >= 1;
    printf( "\nComment:\t%s",      ( $flagsEX & 2 )   ? "yes"     : "no" ) if $print >= 1;
    printf( "\nLocked:\t\t%s",     ( $flagsEX & 4 )   ? "yes"     : "no" ) if $print >= 1;
    printf( "\nSolid:\t\t%s",      ( $flagsEX & 8 )   ? "yes"     : "no" ) if $print >= 1;
    printf( "\nNew naming:\t%s",   ( $flagsEX & 16 )  ? "yes"     : "no" ) if $print >= 1;
    printf( "\nAuthenticity:\t%s", ( $flagsEX & 32 )  ? "yes"     : "no" ) if $print >= 1;
    printf( "\nRecovery:\t%s",     ( $flagsEX & 64 )  ? "yes"     : "no" ) if $print >= 1;
    printf( "\nEncr.headers:\t%s", ( $flagsEX & 128 ) ? "==yes==" : "no" ) if $print >= 1;
    printf( "\nFirst volume:\t%s\n\n",
        ( $flagsEX & 256 ) ? "yes" : "no or older than 3.0" ) if $print >= 1;

    if ( !( $flagsEX & 128 ) && !( $flagsEX & 256 ) && ( $flagsEX & 1 ) ) {
        $continue = "no";
    }
    elsif ( exists $donotprocess{$file} ) {
        $continue = "no";
    }

    !$RARCloseArchive->Call($handle2) || croak "RARCloseArchive failed";
    return ( $flagsEX & 128, $flags & 4, $continue );
}

sub unpack_flags {
    my ( $packed_flags ) = @_;

    my $unpacked_flags = {
        'Volume'        => ( $packed_flags &   1 ) ? 1 : 0,
        'Comment'       => ( $packed_flags &   2 ) ? 1 : 0,
        'Locked'        => ( $packed_flags &   4 ) ? 1 : 0,
        'Solid'         => ( $packed_flags &   8 ) ? 1 : 0,
        'NewNaming'     => ( $packed_flags &  16 ) ? 1 : 0,
        'Authenticity'  => ( $packed_flags &  32 ) ? 1 : 0,
        'Recovery'      => ( $packed_flags &  64 ) ? 1 : 0,
        'EncHeaders'    => ( $packed_flags & 128 ) ? 1 : 0,
        'FirstVolume'   => ( $packed_flags & 256 ) ? 1 : 0,
    };
    return $unpacked_flags;
}

################ PUBLIC METHODS ################

sub list_files_in_archive {
    my ( $file, $password, $print ) = @_;
    $print = 1 unless defined $print;
    my ( $blockencrypted, $needpassword, $continue, $print ) = extract_headers($file,$password,$print);

    my $blockencryptedflag;
    my $errorcode = undef;

    my $RAROpenArchiveDataEx_for_extracting =
      pack( 'ppLLpLLLLx32', $file, undef, 2, 0, undef, 0, 0, 0, 0 );
    my $handle = $RAROpenArchiveEx->Call($RAROpenArchiveDataEx_for_extracting)
      || croak "RAROpenArchiveEx failed";
    my $RARHeaderData = pack( 'x260x260LLLLLLLLLLpLL',
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, undef, 0, 0, 0 );

    if ($blockencrypted) {

        if ($password) {
            $RARSetPassword->Call( $handle, $password );
        }
        else {
            !$RARCloseArchive->Call($handle) || croak "$RARCloseArchive failed";
            return $errorcode = "requires password";
        }
    }

    my @file_info = ();
    while ( ( $RARReadHeader->Call( $handle, $RARHeaderData ) ) == 0 ) {
        $blockencryptedflag = "yes";
        my $processresult = $RARProcessFile->Call( $handle, 0, undef, undef );
        if ( $processresult != 0 ) {
            $errorcode =
              "Error from dll - (Check dll documentation): " . $processresult;

#probably wrong password but check unrar.dll documentation for error description
            last;
        }
        else {
            my @files = unpack( 'A260A260LLLLLLLLLLpLL', $RARHeaderData );
            print "File\t\t\t\t\tSize\n" if $print;
            print "-------------------------------------------\n" if $print;
            print "$files[0]\\$files[1]\t\t$files[4]\n\n" if $print;

            #if ( $blockencrypted ) {
            #    $donotprocess{ $files[0] } = 1;

            #} else {
                # struct RARHeaderData
                # {
                #   char ArcName[260];
                #   char FileName[260];
                #   unsigned int Flags;
                #   unsigned int PackSize;
                #   unsigned int UnpSize;
                #   unsigned int HostOS;
                #   unsigned int FileCRC;
                #   unsigned int FileTime;
                #   unsigned int UnpVer;
                #   unsigned int Method;
                #   unsigned int FileAttr;
                #   char *CmtBuf;
                #   unsigned int CmtBufSize;
                #   unsigned int CmtSize;
                #   unsigned int CmtState;
                # };
                my $packed_flags = $files[2];
                my $unpacked_flags = unpack_flags( $packed_flags );

                push @file_info, {
                    ArcName     => $files[0],
                    FileName    => $files[1],
                    Flags       => $unpacked_flags,
                    PackSize    => $files[3],
                    UnpSize     => $files[4],
                    HostOS      => $files[5],
                    FileCRC     => $files[6],
                    FileTime    => $files[7],
                    UnpVer      => $files[8],
                    Method      => $files[9],
                    FileAttr    => $files[10],
                    CmtBuf      => $files[11],
                    CmtBufSize  => $files[12],
                    CmtSize     => $files[13],
                    CmtState    => $files[14],
                };
           # }
        }
    }

    if ( $blockencrypted && ( !defined($blockencryptedflag) ) ) {
        $errorcode = "headers encrypted and password not correct";
    }

    !$RARCloseArchive->Call($handle) || croak "$RARCloseArchive failed";
    return $errorcode if $errorcode;
    return @file_info;

}

sub process_file {
    my ( $file, $password, $directory ) = @_;
    my ( $blockencrypted, $needpassword, $continue ) = extract_headers( $file, $password, 0 );
    my $errorcode;

    return ( $errorcode = "multipart" ) if ($continue);

    unless ( defined $directory ) {
        ( $directory = $file ) =~ s/\.rar//i;
    }

    my $blockencryptedflag;

    my $RAROpenArchiveDataEx_for_extracting =
      pack( 'ppLLpLLLLx32', $file, undef, 1, 0, undef, 0, 0, 0, 0 );
    my $RARHeaderData = pack( 'x260x260LLLLLLLLLLpLL',
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, undef, 0, 0 );

    my $handle = $RAROpenArchiveEx->Call($RAROpenArchiveDataEx_for_extracting)
      || croak "RAROpenArchiveEx failed";

    if ( $blockencrypted || $needpassword ) {

        if ($password) {
            $RARSetPassword->Call( $handle, $password );
        }
        else {
            !$RARCloseArchive->Call($handle) || croak "$RARCloseArchive failed";
            return $errorcode = "requires password";
        }
    }

    while ( ( $RARReadHeader->Call( $handle, $RARHeaderData ) ) == 0 ) {
        $blockencryptedflag = "yes";
        my $processresult =
          $RARProcessFile->Call( $handle, 2, $directory, undef );
        if ( $processresult != 0 ) {
            $errorcode =
              "Error from dll - (Check dll documentation): " . $processresult;
			# probably wrong password but check unrar.dll documentation for error description
            last;
        }

    }



    if ( $blockencrypted && ( !defined($blockencryptedflag) ) ) {
        $errorcode = "headers encrypted and password not correct";
    }
    elsif ($blockencrypted) {
        list_files_in_archive( $file, $password );
    }

    !$RARCloseArchive->Call($handle) || croak "RRARCloseArchive failed";
    return $errorcode;
}

declare_win32_functions();

1;

__END__

=head1 NAME

RAR::Unrar - is a procedural module that provides manipulation (extraction and listing of embedded information) of compressed RAR format archives by interfacing with the unrar.dll dynamic library for Windows.

=head1 SYNOPSIS

    use RAR::Unrar qw(list_files_in_archive process_file);

    #usage
    list_files_in_archive($file,$password);
    process_file($file,$password);

    #if RAR archive in the same directory as the caller
    list_files_in_archive("myfile.rar","mypassword");
    process_file("myfile.rar","mypassword");

    #absolute path if RAR archive not in the same directory as the caller
    list_files_in_archive("c:\mydirectory\myfile.rar","mypassword");
    process_file("c:\mydirectory\myfile.rar","mypassword");


=head1 DESCRIPTION

RAR::Unrar is a procedural module that provides manipulation (extraction and listing of embedded information) of compressed RAR format archives by interfacing with the unrar.dll dynamic library for Windows.

It uses two functions : list_files_in_archive and process file

The first one lists details embedded into the archive (files bundled into the .rar archive,archive's comments and header info) and the latter extracts the files from the archive.

Both take two parameters;the first is the file name and the second is the password required by the archive.
If no password is required then just pass undef or the empty string as the second parameter

Both procedures return undef if successfull, and an error description if something went wrong

    $result=process_file($file,$password);
    print "There was an error : $result" if defined($result);

=head1 PREREQUISITES

Must have unrar.dll in %SystemRoot%\System32.

Get UnRAR dynamic library for Windows software developers at L<http://www.rarlab.com/rar/UnRARDLL.exe >

This package includes the dll,samples,dll internals and error description

=head1 TEST AFTER INSTALLATION

After module is installed run test\mytest.pl.
If all is well then you should see two files in the directory :

    test no pass succedeed.txt
    test with pass succedeed.txt

=head2 EXPORT

None by default.

=head1 AUTHOR

Nikos Vaggalis <F<nikos.vaggalis@gmail.com>>


=cut
