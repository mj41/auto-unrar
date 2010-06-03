return [
    {
        name => 'data',
        src_dir =>  catdir( $RealBin, '..', '..', 'auto-unrar-data', 'in'  ),
        dest_dir => catdir( $RealBin, '..', '..', 'auto-unrar-data', 'out' ),
        state_fpath =>  catfile( $RealBin, '..', '..', 'auto-unrar-data', 'unrar-data.db' ),
        exclude_list => catfile( $RealBin, '..', '..', 'auto-unrar-data', 'unrar-data-rsync-exclude.txt' ),
        minimum_free_space => '10000', # MB
        basedir_deep => 1,
        recursive => 1,
        remove_done => 1,
        move_non_rars => 1,
        min_dir_mtime => 1, # 5*60, # seconds
        save_ok_info => 1,
        save_err_info => 1,
    },
];
