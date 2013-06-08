my $name = 'mj-videos';
my $home_dir = '/home/USER-NAME';
return [
    {
        name => $name,
        # Directory where directories with rar (and other files) are.
        src_dir => catdir( $home_dir, 'videos-rars' ),
        # This describe organization of your 'src_dir'. E.g. for src_dir => '/home/mj/videos-rars' and
        # '/home/mj/videos-rars/john-maria-wedding/cd1/jmw.r01', ... use 1 (level 1),
        # but for
        # '/home/mj/videos-rars/year-2010/john-maria-wedding/cd1/jmw.r01', ... use 2 (level 2).
        # auto-unrar use this for many things, e.g. to find where to rollback, e.g. if extraction of
        # videos-rars/john-maria-wedding/cd2/jmw.r22' failed then rollback is called and
        # directory '/home/mj/videos-rars/john-maria-wedding/' content stay untouched (and nothing
        # is extracted).
        basedir_deep => 1,
        # Directory where all unpacked files/directories will be.
        dest_dir => catdir( $home_dir, 'videos' ),
        # Path to file where auto-unrar has state file.
        state_fpath  => catdir( $RealBin, '..', 'db', $name.'-data.pl' ),
        # Path where exclude list for rsync will be generated. You can rsync new videos to 'src_dir'.
        # After extraction (if option 'remove_done' is true) input rars are removed from 'src_dir'.
        # You can use exclude list for rsync to skip these already rsynced and extracted directories.
        exclude_list => catdir( $RealBin, '..', 'db', $name.'-rsync-exclude.txt' ),
        # Minimum space on your disc before extraction start.
        minimum_free_space => '2000', # MB
        # Recurse into directories (or not).
        recursive => 1,
        # Remove archives that was extracted ok. Also remove all remaining empty directories.
        remove_done => 1,
        # Move files that aren't rar archives from path in 'src_dir' to correspondig directory in 'dest_dir'
        # if extractiond of all archives there succeeded.
        move_non_rars => 1,
        # If there are changes in directory that are earlier than 'min_dir_mtime' then skip this dir
        # (probably rsync or some copying already running).
        min_dir_mtime => 1, # 5*60, # seconds
        # Save info about successfully extracted dirs.
        save_ok_info => 1,
        # Save info about dirs which extraction failed. Trying to extract again only if something inside
        # dirs changed.
        save_err_info => 1,
    },
];
