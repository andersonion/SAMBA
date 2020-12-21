
use strict;
use warnings;
use Switch;
#
# WARNING vbm_write_stats_for_pm uses the switch module which causes all kinds of syntax trouble!
# WARNING it has been turned into a hidden function using dangerous eval tomfollery!
# WARNING talk to james about how this works and what should be done!
#
sub vbm_write_stats_for_pm {
    my ($PM,$Hf,$start_time,@jobs) = @_;
    my $PM_code;
    if (! defined $PM) {
        $PM = 0;
    } elsif ($PM =~ s/\.pm$//) {
        $PM = $PM;
    }
    # pm_code 74
    #my $real_time = vbm_write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
    switch ($PM) { # switch doesnt behave right when switch moduld begin block doesnt get to run
        case ("load_study_data_vbm") {$PM_code = 11;}
        case ("convert_all_to_nifti_vbm") {$PM_code = 12;} #testo
        case ("create_rd_from_e2_and_e3_vbm") {$PM_code = 13;}
        case ("mask_images_vbm") {$PM_code = 14;}
        case ("set_reference_space_vbm") {$PM_code = 15;}

        case ("create_rigid_reg_to_atlas_vbm"){$PM_code = 21;}

        case ("create_affine_reg_to_atlas_vbm"){$PM_code = 39;} ## Intend to use a pairwise registration based module for the affine reg, analoguous to the MDT creation.

        case ("pairwise_reg_vbm") {$PM_code = 41;}
        case ("calculate_mdt_warps_vbm") {$PM_code = 42;}
        case ("apply_mdt_warps_vbm") {$PM_code = 43;}
        case ("mdt_apply_mdt_warps_vbm") {$PM_code = 43;}
        case ("calculate_mdt_images_vbm") {$PM_code = 44;}
        case ("mask_for_mdt_vbm") {$PM_code = 45;}
        case ("calculate_jacobians_vbm") {$PM_code = 46;}
        case ("calculate_jacobians_mdtGroup_vbm") {$PM_code = 47;}


        case ("compare_reg_to_mdt_vbm") {$PM_code = 51;}
        case ("reg_apply_mdt_warps_vbm") {$PM_code = 52;}
        case ("calculate_jacobians_regGroup_vbm") {$PM_code = 53;}

        case ("mdt_create_affine_reg_to_atlas_vbm") {$PM_code = 61;}
        case ("mdt_reg_to_atlas_vbm") {$PM_code = 62;}
        case ("warp_atlas_labels_vbm") {$PM_code = 63;}
        case ("label_images_apply_mdt_warps_vbm") {$PM_code = 64;}
        case ("label_statistics_vbm") {$PM_code = 65;}

        case ("smooth_images_vbm") {$PM_code = 71;}
        case ("vbm_analysis_vbm") {$PM_code = 72;}

        case(/[0-9]{2}/) {$PM_code = $PM;}

#       case ("") {$PM_code = 19;}
#       case ("") {$PM_code = 19;}

        else  {$PM_code = 0;}
    }

    my $end_time = time;
    my $real_time = ($end_time - $start_time);
    my $pm_string = "${PM_code},0,0,${start_time},${real_time},0";
    my $stats_file = $Hf->get_value("stats_file");
    if ($stats_file ne "NO_KEY") {
        run_and_watch("echo \"${pm_string}\" >> ${stats_file}");
    }

    if  ($#jobs != -1) {
        my $stats =  get_slurm_job_stats($PM_code,@jobs);
        chomp($stats);
        if ($stats_file ne "NO_KEY") {
            `echo "$stats" >> ${stats_file}`;
        }
    }
    return($real_time);
};

1;
