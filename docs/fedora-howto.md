auto-unrar Fedora HowTo
=======================

This is a tutorial how to use [github.com/mj41/auto-unrar](https://github.com/mj41/auto-unrar) script with the newest Fedora.

Installing and configuration
----------------------------

Install dependencies:

    su -c'yum install -y git perl-Term-ReadKey perl-Filesys-Df'
	su -c'yum localinstall --nogpgcheck http://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm'
	su -c'yum install -y unrar'

Download

    cd ~/
    git clone git://github.com/mj41/auto-unrar.git auto-unrar
    cd auto-unrar

Configure

    mkdir -p temp conf-my db
    cp conf/videos-example.pl conf-my/videos.pl
    gedit conf-my/videos.pl

And run auto-unrar scrip.

    perl bin/auto-unrar.pl --conf conf-my/videos.pl --cmd unrar
