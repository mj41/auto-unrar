package Archive::Rar::Passthrough;

require 5.004;

use strict;

use vars qw/$VERSION/;
$VERSION = '2.00_02';

use ExtUtils::MakeMaker;
use Config ();
use File::Spec;
use Carp qw/croak/;
use IPC::Run ();
use IPC::Cmd ();

BEGIN {
  if (not IPC::Cmd->can_capture_buffer()) {
    die "IPC::Cmd needs to be able to capture buffers for Archive::Rar::Passthrough to work. However, it doesn't. Check the IPC::Cmd documentation for details";
  }
}

my $IsWindows = ($^O =~ /win32/i ? 1 : 0);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;

  my $self = {
    rar    => 'rar',
    stdout => '',
    stderr => '',
    ( ref($proto) ? %$proto : () ),
  };
  $self->{rar} = $args{rar} if exists $args{rar}; 

  bless $self => $class;
  return() if not $self->{rar} = $self->_findbin();
  
  return $self;
}

sub get_binary { $_[0]->{rar} }
sub set_binary { $_[0]->{rar} = $_[1] if defined $_[1]; 1; }

sub get_stdout { $_[0]->{stdout} }
sub get_stderr { $_[0]->{stderr} }
sub clear_buffers { $_[0]->{stderr} = $_[0]->{stdout} = ''; 1; }

# searches the rar binary.
sub _findbin {
  my $self = shift;
  my $bin = $self->get_binary();
  
  my $cmd = _module_install_can_run($bin);
  
  return $cmd if defined $cmd;

  # From Archive::Rar, (c) Jean-Marc Boulade
  # modified by Steffen Mueller
  if ( $IsWindows ) {
    require Win32::TieRegistry;
    my %RegHash;
    Win32::TieRegistry->import( TiedHash => \%RegHash );
    
    my $path;

    # try to find the installation path
    $path = $RegHash{'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\WinRAR.exe\\path'};
    if (defined $path and not ref($path)) {
      $path =~ s/\\/\//g;
      $cmd = File::Spec->catfile($path, 'rar.exe');
      return $cmd if -e $cmd;
    }

    # or then via the uninstaller
    $path = $RegHash{'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\WinRAR archiver\\UninstallString'};
    if (defined $path and not ref($path)) {
      $path =~ s/\\/\//g;
      $path =~ s/\/uninstall.exe$//i;
      $cmd = File::Spec->catfile($path, 'rar.exe');
      return $cmd if -e $cmd;
    }

    # try the normal path
    # yuck!
    $cmd = 'c:/program files/winrar/rar.exe';
    return $cmd if -e $cmd;

    # direct execution
    # Update: Don't try. _module_install_can_run does this better.
    #$cmd = 'rar';
    #return $cmd if $self->TestExe($cmd);

    # last resort
    return _module_install_can_run('rar32');
  }

  return();
}


# lifted and modified from Module::Install::Can ((c) Brian Ingerson, Audrey Tang, Adam Kennedy, et al)
sub _module_install_can_run {
  my $cmd = shift;
  my $_cmd = $cmd;
  
  return $_cmd
    if -x $_cmd or $_cmd = MM->maybe_command($_cmd);

  for my $dir ((split /$Config::Config{path_sep}/, $ENV{PATH}), '.') {
    my $abs = File::Spec->catfile($dir, $cmd);
    return $abs
      if -x $abs or $abs = MM->maybe_command($abs);
  }

  return;
}




{
  my %Errors = (
   255 => 'User stopped the process',
   9   => 'Create file error',
   8   => 'Not enough memory for operation',
   7   => 'Command line option error',
   6   => 'Open file error',
   5   => 'Write to disk error',
   4   => 'Attempt to modify an archive previously locked by the \'k\' command',
   3   => 'A CRC error occurred when unpacking',
   2   => 'A fatal error occurred',
   1   => 'Non-fatal error(s) occurred',
  );

  sub explain_error {
    my $self = shift;
    my $error = shift;
    return 'Unknown error' if not $error and not exists($Errors{$error});
    return $Errors{$error};
  }
}


sub run {
  my $self = shift;

  my %args = @_;

  my $rar = $self->get_binary();
  
  my $cmd = $args{command};
  croak("You need to specify a rar *command* as argument to " . __PACKAGE__ . "->run()")
    if not defined $cmd;

  my $archive  = $args{archive};
  croak("You need to specify a rar *archive* as argument to " . __PACKAGE__ . "->run()")
    if not defined $archive;

  my $switches = $args{switches} || ['-y'];
  croak("The 'switches' argument to " . __PACKAGE__ . "->run() must be an array reference")
    if not ref($switches) eq 'ARRAY';
  
  my $files = $args{files} || [];
  croak("The 'files' argument to " . __PACKAGE__ . "->run() must be an array reference")
    if not ref($files) eq 'ARRAY';

  my $filelist_files = $args{filelist_files} || [];
  croak("The 'files' argument to " . __PACKAGE__ . "->run() must be an array reference")
    if not ref($filelist_files) eq 'ARRAY';

  #Usage:     rar <command> -<switch 1> -<switch N> <archive> <files...>
  #             <@listfiles...> <path_to_extract\>
  my $command = [
    $rar, $cmd, @$switches, $archive, @$files,
    @$filelist_files, (defined($args{path}) ? $args{path}: ())
  ];

  my ($ok, $errorcode, undef, $out_buffer, $err_buffer) = IPC::Cmd::run(command => $command);
  $self->{stdout} = join "\n", @{$out_buffer || []};
  $self->{stderr} = join "\n", @{$err_buffer || []};

  return($ok ? 0 : $errorcode);
}


1;

__END__

=head1 NAME

Archive::Rar::Passthrough - Thinnest possible wrapper around 'rar'

=head1 SYNOPSIS

 use Archive::Rar::Passthrough;
 my $rar = Archive::Rar::Passthrough->new();
 
 if (not $rar) {
   print "Could not find your 'rar' command'.\n";
 }
 
 my $errorcode = $rar->run(
   command => 'a',
   switches => ['-cl'], # optional
   archive => 'my.rar',
   filelist_files => [ 'some_text_file_with_file_names' ],
   files => ['file1.txt', 'file2.txt'],
   path => 'some_path_for_extraction', # optional
 );
 
 if ($errorcode) {
   print "There was an error running 'rar': " . $rar->explain_error($retval) . "\n";
   my $output = $rar->get_stdout();
   my $errors = $rar->get_stderr();
   print "The 'rar' command said (if anything):\n" . $output
         . "\nAnd spammed on STDERR:\n" . $errors . "\n";
 }

=head1 DESCRIPTION

This module is a very, very thin wrapper around running the C<rar> command.
If you have ever dealed with running external programs with command line parameters
from your code portably, you most certainly know that it is a lot of pain.
This module uses C<IPC::Cmd> to run C<rar>, so it should be reasonably portable.

Unlike L<Archive::Rar>, this just takes a small bit of the pain out of running rar
directly. You still have to know the interface. But it should not be necessary
to escape your file names of the contain funny characters. Note that Archive::Rar
does not currently help you with this.

The module tries to locate the rar command (from PATH or from regedit for Win32).
You may specify the 'rar' instance to use with the C<rar> parameter to the
constructor:

  my $rar = Archive::Rar::Passthrough->new(rar => 'path/to/rar');

The constructor returns the empty list (i.e. false) instead of an object
if the rar binary was not found.

The object returned from C<new()> has very little state. It does not remember things
like the previous archive it worked on. It only knows what 'rar' binary to use
and the output (STDOUT and STDERR) of the previous invocation 'rar'.

=head1 METHODS

=head2 new

The constructor returns a new C<Archive::Rar::Passthrough> object if
it found a rar binary to use. Takes a single named, optional parameter:
C<rar => 'path/to/rar'>.

You can also use C<$obj->new()> to clone an C<Archive::Rar::Passthrough> object.

=head2 run

Runs the C<rar> binary. Takes named arguments which correspond to the C<rar> usage: (from RAR 3.70)

  Usage:     rar <command> -<switch 1> -<switch N> <archive> <files...>
                 <@listfiles...> <path_to_extract\>

Mandatory arguments:

  command: string indicating the command (example 'e' for extraction)
  archive: string indicating the RAR archive file to operate on

Optional arguments:

  switches: array reference to array of command line options.
            Defaults to ['-y'].
  files: list of files to add/whatever. Array reference
  filelist_files: list of files to use as file list input.
                  Array reference
  path: path to extract to

Please note that by default, the C<-y> switch is passed to C<rar>. That means all
interactive questions from C<rar> are answered with I<yes> as there is no way to
for the user to communicate with C<rar>. However, this also means that files will
be overwritten by default!

=head2 explain_error

Given an error code / number as return by the C<run()> method, this
method will return an explanation of the error. It's the same text as
that in the L<RAR RETURN CODES> section below.

=head2 get_binary

Returns the path of the rar binary that's being used.

=head2 set_binary

Set the path of the rar binary to use.

=head2 get_stdout

Returns the output (STDOUT) of the previous invocation of C<rar>.

=head2 get_stderr

Returns the error output (STDERR) of the previous invocation of C<rar>.

=head2 clear_buffers

Clears the STDOUT and STDERR buffers of the object.
You really only need to call this if you're paranoid about memery usage.

=head1 RAR RETURN CODES

The C<run()> method returns a numerical code indicating the success or failure type
of the command. Quoting the documentation of RAR 3.70 beta 1:

 RAR exits with a zero code (0) in case of successful operation. The exit
 code of non-zero means the operation was cancelled due to an error:
 
 255   USER BREAK       User stopped the process
   9   CREATE ERROR     Create file error
   8   MEMORY ERROR     Not enough memory for operation
   7   USER ERROR       Command line option error
   6   OPEN ERROR       Open file error
   5   WRITE ERROR      Write to disk error
   4   LOCKED ARCHIVE   Attempt to modify an archive previously locked
                        by the 'k' command
   3   CRC ERROR        A CRC error occurred when unpacking
   2   FATAL ERROR      A fatal error occurred
   1   WARNING          Non fatal error(s) occurred
   0   SUCCESS          Successful operation

There may be other codes in future versions of 'rar'. Error C<9> - I<CREATE ERROR>, for example,
was not present in version 2.80.

The explanations above can be accessed by your code through the C<explain_error($errno)> method.

=head1 AUTHORS

Steffen Mueller E<lt>smueller@cpan.orgE<gt>

The code for finding a rar instance in the Windows registry stems from
Archive::Rar, written by jean-marc boulade E<lt>jmbperl@hotmail.comE<gt>.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008 Steffen Mueller.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

The code for testing an executable is from Module::Install::Can.
It is carries: Copyright 2002, 2003, 2004, 2005, 2006 by Brian Ingerson, Audrey Tang, Adam Kennedy.

The code for determination of the rar binary from the Windows registry
is copyright (c) 2002-2006 jean-marc boulade.

Both of these contributions carry the same license that is stated above.

=head1 RAR DOCUMENTATION

This is the help message of the rar command as found on my computer.
Your milage may vary!

  RAR 3.70 beta 1   Copyright (c) 1993-2007 Alexander Roshal   8 Jan 2007
  Shareware version         Type RAR -? for help

  Usage:     rar <command> -<switch 1> -<switch N> <archive> <files...>
                 <@listfiles...> <path_to_extract\>

  <Commands>
    a             Add files to archive
    c             Add archive comment
    cf            Add files comment
    ch            Change archive parameters
    cw            Write archive comment to file
    d             Delete files from archive
    e             Extract files to current directory
    f             Freshen files in archive
    i[par]=<str>  Find string in archives
    k             Lock archive
    l[t,b]        List archive [technical, bare]
    m[f]          Move to archive [files only]
    p             Print file to stdout
    r             Repair archive
    rc            Reconstruct missing volumes
    rn            Rename archived files
    rr[N]         Add data recovery record
    rv[N]         Create recovery volumes
    s[name|-]     Convert archive to or from SFX
    t             Test archive files
    u             Update files in archive
    v[t,b]        Verbosely list archive [technical,bare]
    x             Extract files with full path

  <Switches>
    -             Stop switches scanning
    ad            Append archive name to destination path
    ag[format]    Generate archive name using the current date
    ap<path>      Set path inside archive
    as            Synchronize archive contents
    av            Put authenticity verification (registered versions only)
    av-           Disable authenticity verification check
    c-            Disable comments show
    cfg-          Disable read configuration
    cl            Convert names to lower case
    cu            Convert names to upper case
    df            Delete files after archiving
    dh            Open shared files
    ds            Disable name sort for solid archive
    e[+]<attr>    Set file exclude and include attributes
    ed            Do not add empty directories
    en            Do not put 'end of archive' block
    ep            Exclude paths from names
    ep1           Exclude base directory from names
    ep3           Expand paths to full including the drive letter
    f             Freshen files
    hp[password]  Encrypt both file data and headers
    id[c,d,p,q]   Disable messages
    ierr          Send all messages to stderr
    ilog[name]    Log errors to file (registered versions only)
    inul          Disable all messages
    isnd          Enable sound
    k             Lock archive
    kb            Keep broken extracted files
    m<0..5>       Set compression level (0-store...3-default...5-maximal)
    mc<par>       Set advanced compression parameters
    md<size>      Dictionary size in KB (64,128,256,512,1024,2048,4096 or A-G)
    ms[ext;ext]   Specify file types to store
    n<file>       Include only specified file
    n@            Read file names to include from stdin
    n@<list>      Include files in specified list file
    o+            Overwrite existing files
    o-            Do not overwrite existing files
    ol            Save symbolic links as the link instead of the file
    or            Rename files automatically
    ow            Save or restore file owner and group
    p[password]   Set password
    p-            Do not query password
    r             Recurse subdirectories
    r0            Recurse subdirectories for wildcard names only
    rr[N]         Add data recovery record
    rv[N]         Create recovery volumes
    s[<N>,v[-],e] Create solid archive
    s-            Disable solid archiving
    sc<chr><obj>  Specify the character set
    sfx[name]     Create SFX archive
    si[name]      Read data from standard input (stdin)
    sl<size>      Process files with size less than specified
    sm<size>      Process files with size more than specified
    t             Test files after archiving
    ta<date>      Process files modified after <date> in YYYYMMDDHHMMSS format
    tb<date>      Process files modified before <date> in YYYYMMDDHHMMSS format
    tk            Keep original archive time
    tl            Set archive time to latest file
    tn<time>      Process files newer than <time>
    to<time>      Process files older than <time>
    ts<m,c,a>[N]  Save or restore file time (modification, creation, access)
    u             Update files
    v             Create volumes with size autodetection or list all volumes
    v<size>[k,b]  Create volumes with size=<size>*1000 [*1024, *1]
    ver[n]        File version control
    vn            Use the old style volume naming scheme
    vp            Pause before each volume
    w<path>       Assign work directory
    x<file>       Exclude specified file
    x@            Read file names to exclude from stdin
    x@<list>      Exclude files in specified list file
    y             Assume Yes on all queries
    z[file]       Read archive comment from file

=cut
