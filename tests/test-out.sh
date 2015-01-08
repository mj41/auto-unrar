#!/bin/bash

set -e

if [ ! -f 'bin/auto-unrar.pl' ]; then
	echo "Please change dir to auto-unrar directory.";
	exit 1
fi

OUTD='docs/test-data'
rm -rf "$OUTD"
mkdir -p "$OUTD"

rm -rf temp/test-data
mkdir -p temp/test-data/in
mkdir -p temp/test-data/out

rsync -avr tests/data/ temp/test-data/in/

echo "# Configuration file (source conf/test-unrar.pl):" > $OUTD/01-config-file.txt
echo "" >> $OUTD/01-config-file.txt
cat conf/test-unrar.pl >> $OUTD/01-config-file.txt

# before

echo "# Input tree of 'src_dir' (temp/test-data/in/) before auto-unrar run:" > $OUTD/02-in-tree-before.txt
echo "" >> $OUTD/02-in-tree-before.txt
tree temp/test-data/in/ >> $OUTD/02-in-tree-before.txt

echo "# Output tree of 'src_dir' (temp/test-data/out/) before auto-unrar run:" > $OUTD/03-out-tree-before.txt
echo "" >> $OUTD/03-out-tree-before.txt
tree temp/test-data/out/ >> $OUTD/03-out-tree-before.txt

echo "# State file (temp/test-data/state.pl) before auto-unrar run:" > $OUTD/04-state-before.txt
echo "" >> $OUTD/04-state-before.txt
echo "" >> $OUTD/04-state-before.txt

echo "# Rsync exclude file (temp/test-data/rsync-exclude-list.txt) before auto-unrar run:" > $OUTD/05-exclude-list-before.txt
echo "" >> $OUTD/05-exclude-list-before.txt
echo "" >> $OUTD/05-exclude-list-before.txt

# run

perl bin/auto-unrar.pl --conf conf/test-unrar.pl --cmd unrar --ver 2 2>&1 | tee $OUTD/06-run-unrar.txt

# after

echo "# Input tree of 'src_dir' (temp/test-data/in/) after auto-unrar run:" > $OUTD/07-in-tree-after.txt
echo "" >> $OUTD/07-in-tree-after.txt
tree temp/test-data/in/ >> $OUTD/07-in-tree-after.txt

echo "# Output tree of 'src_dir' (temp/test-data/out/) after auto-unrar run:" > $OUTD/08-out-tree-after.txt
echo "" >> $OUTD/08-out-tree-after.txt
tree temp/test-data/out/ >> $OUTD/08-out-tree-after.txt

echo "# State file (temp/test-data/state.pl) after auto-unrar run:" > $OUTD/09-state-after.txt
echo "" >> $OUTD/09-state-after.txt
cat temp/test-data/state.pl >> $OUTD/09-state-after.txt

echo "# Rsync exclude file (temp/test-data/rsync-exclude-list.txt) after auto-unrar run:" > $OUTD/10-exclude-list-after.txt
echo "" >> $OUTD/10-exclude-list-after.txt
cat temp/test-data/rsync-exclude-list.txt >> $OUTD/10-exclude-list-after.txt

# diffs
diff --side-by-side $OUTD/02-in-tree-before.txt $OUTD/07-in-tree-after.txt > $OUTD/11-in-tree-diff.txt || true
diff --side-by-side $OUTD/03-out-tree-before.txt $OUTD/08-out-tree-after.txt > $OUTD/12-out-tree-diff.txt || true
