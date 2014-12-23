auto-unrar Debian HowTo
=======================

UnRar script for Debian (and other Linux distributions).

This is a tutorial how to use auto-unrar script ( https://github.com/mj41/auto-unrar ) with the newest Debian.

Installing and configuration
----------------------------

1. Install perl or make sure you have perl
 - sudo apt-get install perl
 - perl -V
2. Make a folder for now called "auto-unrar"
3. Download this : https://github.com/mj41/auto-unrar/archive/master.zip and unzip all the files in the folder to "auto-unrar"
4. Make sure you have every file!
5. Install "libfilesys-df-perl"
  - you can do this with the command "sudo apt-get install libfilesys-df-perl" in console
6. Install "libterm-readkey-perl"
  - you can do this with the command "sudo apt-get install libterm-readkey-perl" in console
7. Install unrar-nonfree
  - This is done with the following commands:
    wget https://launchpad.net/ubuntu/+archive/primary/+files/unrar-nonfree_5.0.10.orig.tar.gz
    tar -xvf unrar-nonfree_5.0.10.orig.tar.gz
    cd unrar
    sudo make
    sudo make install
    cd ..
    rm -rf unrar
    rm unrar-nonfree_5.0.10.orig.tar.gz 
  - To test if it works, 'unrar --help'
8. Edit you config file
  - mkdir -p conf-my
  - mkdir -p db
  - cp conf/videos-example.pl conf-my/my-unrar-config.pl
  - edit 'conf-my/my-unrar-config.pl' to your likings.
  - Name is for the program name, this doesn't matter
  - src_dir is the place you have the rar's, edit to your location example "/home/USER-NAME/rar-archives-in/"
  - dest_dir is the place you want to unpacked files to go to, edit your location example "/home/USER-NAME/uppacked/"
  - state_fpath is the place it saves the database, you don't need to touch this
  - exlude_list is the places where exclude list file for rsync is saved
  - mimumum_free stands for it self, the minimum free disk space required, just leave this if you have enough space
  - basedir_deep, recursive is described in your file - read it carefully
  - remove_done, do you want the files removed when they are unrared, 1 for yes, 0 for no
  - move_non_rars, do you want to include non_rars files to the other location, say you have a .txt file this will be coppied/moved to, 1 for yes, 0 for no
  - min_dir_mtime is also described in sample config file you copied
  - save_ok_info, logging all the normal info, just leave it untouched
  - save_err_info, logging all the error info, just leave it untouched

Running
-------

13. Run the bin/auto-unrar.pl file.
  - if you have any errors be sure to google and if it doesn't work the changes are high I won't know it either so try a forum..
  - google should give you the information, if you can't find it try a different search string.
  - Make sure you get no errors and you get the following
    - "No command selected. Option 'cmd' in mandatory. Use --help to see more info."
14. Create the run command
  - perl "absolute path to auto-unrar.pl" --conf="absolute path to config file" --cmd=unrar
  - perl /home/$USER/auto-unrar/bin/auto-unrar.pl --conf="/home/$USER/unrar/conf-my/my-unrar-config.pl" --cmd=unrar
  - You can add "--ver 10" option to raise verbose level to 10 (maximum) for debugging.

Scheduling
----------

Since you use Debian you can use scheduling.
Crontab is explained here: https://help.ubuntu.com/community/CronHowto , it is for all linux distributions.
15. Enter this in console: "sudo crontab -e"
16. Enter the following line at the end:
   - "when you want it" PATH=/usr/local/bin:/usr/bin:/usr/sbin:/usr/lib; perl "absolute path to auto-unrar.pl" --conf="absolute path to config" --cmd=unrar
   - so for instance if you want to run this job only once a day at 8:30 AM you'll need to set it this way:
   - 30 08 * * * PATH=/usr/local/bin:/usr/bin:/usr/sbin:/usr/lib; perl /home/USER-NAME/auto-unrar/bin/auto-unrar.pl --conf="/home/USER-NAME/auto-unrar/conf-my/my-unrar-config.pl" --cmd=unrar

If you have any questions, you can contact the original writer of this script with IRC here:
irc://irc.freenode.org/auto-unrar

If you have any questions regarding installing etc. feel free to send me a message at gmail:
thacthatha@gmail.com
Subject must be: "Help wanted, Unrar script" otherwise I'll probably not read it.
