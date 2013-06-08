UNRAR
=====

UnRar script for Debian(and other linux distributions..)

So first of all hello, 
This is a tutorial how to use https://github.com/mj41/auto-unrar this unrar script with the newest debian.
Remember not to get files from there since they are outdated and aren't working correctly.
It took me several hours to fix the errors so I wouldn't recommend finding them yourself xD.

----------------------------------------- Installing and configuration -----------------------------------------

1. Install perl or make sure you have perl
 - sudo apt-get install perl
 - perl -V
2. Make a folder for now called "unrar"
3. Download this : https://github.com/jorricks/UNRAR/archive/master.zip and unzip all the files in the folder to "unrar"
4. Make sure you have every file!!!!
5. Install "libfilesys-df-perl"
  - you can do this with the command "sudo apt-get install libfilesys-df-perl" in ssh
6. Install "libterm-readkey-perl"
  - you can do this with the command "sudo apt-get install libterm-readkey-perl" in ssh
7. in SSH type: "sudo pico /etc/apt/sources.list"
  - Where you see something like "deb http://http.us.debian.org/debian stable main"
  - Add non-free to it so it becomes "deb http://http.us.debian.org/debian stable main non-free"
8. install unrar non-free in ssh, "sudo apt-get install unrar"
9. Edit you config file "unrar-data-conf.pl" to your likings.
  - Name is for the program name, this doens't matter
  - src_dir is the place you have the rar's, edit "in" to your location example "/home/user/RAR/"
  - dest_dir is the place you want to unpacked files to go to, edit "out" to your location example "/home/user/UNRAR"
  - state_fpath is the place it saves the database, you don't need to touch this
  - exlude_list are the places it excludes from unraring, so you shouldn't really use this, unless you have folders which shouldn't be unrared
  - mimumum_free stands for it self, the minimum free disk space required, just leave this if you have enough space
  - basedir_deep this is if you want to include the subfolders, 1 for yes, 0 for no
  - recursive, I got no idea, leave a comment if you know please
  - remove_done, do you want the files revomed when they are unrared, 1 for yes, 0 for no
  - move_non_rars, do you want to include non_rars files to the other location, say you have a .txt file this will be coppied to, 1 for yes, 0 for no
  - min_dir_mtime, minimum time there should be between a search for new files???
  - save_ok_info, logging all the normal info, just leave it untouched..
  - save_err_info, logging all the error info, just leave it untouched..

----------------------------------------- RUNNING -----------------------------------------

13. Run the unrar2.pl file.
  - if you have any errors be sure to google and if it doesn't work the changes are high I won't know it either so try a forum..
  - google should give you the information, if you can't find it try a different search string.
  - Make sure you get no errors and you get the following
    - "No command selected. Option 'cmd' in mandatory. Use --help to see more info."
14. Create the run command
  - perl "absolute path to unrar2.pl" --conf="absolute path to config file" --cmd=unrar
  - perl /home/user/unrar/unrar2.pl --conf="/home/user/unrar/conf/unrar-data-conf.pl" --cmd=unrar
  

----------------------------------------- SCHEDULING -----------------------------------------
Since you use debian you can use scheduling.
Crontab is explained here: https://help.ubuntu.com/community/CronHowto , it is for all linux distributions.
15. Enter this in ssh: "sudo crontab -e"
16. Enter the following line at the end:
   - "when you want it" PATH=/usr/local/bin:/usr/bin:/usr/sbin:/usr/lib; perl "absolute path to unrar2.pl" --conf="absolute path to config" --cmd=unrar
   - so for instance if you want to run this job only once a day at 8:30 AM you'll need to set it this way:
   - 30 08 * * * PATH=/usr/local/bin:/usr/bin:/usr/sbin:/usr/lib; perl /home/user/unrar/unrar2.pl --conf="/home/user/unrar/conf/unrar-data-conf.pl" --cmd=unrar

If you have any questions, you can contact the original writer of this script with IRC here:
irc://irc.freenode.org/taptinder

If you have any questions regarding installing etc. feel free to send me a message at gmail:
thacthatha@gmail.com
Subject must be: "Help wanted, Unrar script" otherwise I'll probably not read it..

I do not take credit for the script, I edited just a couple things. The things I remember right away
- I changed SHA1 to SHA since it isn't supported in wheezy anymore
- I changed rar to unrar because the rar package wasn't available for all the architectures
- I changed the Filesys to Filesys::Df since this also wasn't supported anymore
So overal you must conclude I almost didn't do shit and you should give the original maker a big thanks :)!
