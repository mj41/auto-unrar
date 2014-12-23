auto-unrar
==========

Smart Perl script (for Linux) to auto unrar/extract a directory structure
containing many RAR archives.

Features
--------

* extract multipart archives
* handle all three multipart archives naming conventions
** .part1.rar, .part2.rar, ...
** .rar, .r00, .r01, ...
** .001, .002, ...
* duplicate directory structure tree
** respect basedir_deep configuration option
** see http://bit.ly/dafLxF ( docs/test-data/summary.txt )
* move/rename normal files (no rar archives)
* check minimum free space on device
* can delete archives if extracted ok
* save status to file
** so already extracted archives aren't extracted again
** trying extract again only if some change found
* keypress features during run ( p...pause, c...continue, q...quit )
* smart error handling
** maintain undo actions list for recovery to initial state
** sleep (increment time to sleep) and try again
** revert to initial state if error found during extraction of directory
* can be configured to run periodically (e.g. from cron) to incrementally extract RAR archives
** check if there is any change inside directory
* support for rsync integration
** generate rsync exclude list (basedir_deep configuration option is used)
** check time of last modification of base directories (recursively)
** respect minimum time since last change (let rsync finish his job)
* preserve mtime of files and directories where possible
* has own test suite
* tested on many big archives
* debug and verbose output support

Tested on Linux only. Also see ToDo list inside source code [bin/auto-unrar.pl](http://github.com/mj41/auto-unrar/blob/master/bin/auto-unrar.pl).

Install
-------

For Debian see [docs/debian-howto.md](https://github.com/mj41/auto-unrar/blob/master/docs/debian-howto.md). 
For Fedora see [docs/fedora-howto.md](https://github.com/mj41/auto-unrar/blob/master/docs/fedora-howto.md).

cd ~/
git clone git://github.com/mj41/auto-unrar.git auto-unrar
cd auto-unrar
mkdir -p temp conf-my db
cp conf/videos-example.pl conf-my/videos.pl
vim conf-my/videos.pl
cpanm Term::ReadKey
cpanm Filesys::Df

Run
---

cd ~/auto-unrar
perl bin/auto-unrar.pl --conf conf-my/videos.pl --cmd unrar

Press:
* P ... pause,
* C .. continue,
* Q .. quit.

Future development and donations
--------------------------------

Report bug or feature request on [github.com/mj41/auto-unrar/issues](https://github.com/mj41/auto-unrar/issues).


Donation
--------

Feel free to donate some money to support development on 
[pledgie.com/campaigns/9585](http://pledgie.com/campaigns/9585). Thank you.
