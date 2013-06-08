my $base_dir = catdir( $RealBin, '..', 'temp', 'test-data' );
return [
    {
        name => 'data',
        src_dir      => catdir( $base_dir, 'in'  ),
        dest_dir     => catdir( $base_dir, 'out' ),
        state_fpath  => catfile( $base_dir, 'unrar-data.pl' ),
        exclude_list => catfile( $base_dir, 'unrar-data-rsync-exclude.txt' ),
        minimum_free_space => '100', # MB
        basedir_deep => 1,
        recursive => 1,
        remove_done => 1,
        move_non_rars => 1,
        min_dir_mtime => 1, # 5*60, # seconds
        save_ok_info => 1,
        save_err_info => 1,
    },
];
