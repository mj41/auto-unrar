How to test unrar of test/data
==============================

Prepare clean temp dir
----------------------

    cd auto-unrar
    rm -rf temp/test-data
    mkdir -p temp/test-data/in
    mkdir -p temp/test-data/out
    rsync -avr tests/data/ temp/test-data/in/

Run test
--------

    perl bin/auto-unrar.pl --conf conf/test-unrar.pl --ver 10 --cmd unrar
    tree temp/test-data/in
    tree temp/test-data/out
