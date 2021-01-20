
use strict;
use warnings FATAL => qw(uninitialized);
# use Switch;
#
# Considering the "cost" of trying to use the switch module, and that it is literally identical to if/else chains, switch is being optimized out. Fomer wraning code remains.
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
    } else {
        $PM =~ s/[.]pm$//;
    }


    # pm_code 74
    #my $real_time = vbm_write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
=item Original switch implemntation.
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
        #case ("") {$PM_code = 19;}
        #case ("") {$PM_code = 19;}
=cut
    if($PM eq "load_study_data_vbm") {$PM_code = 11;}
    elsif($PM eq "convert_all_to_nifti_vbm") {$PM_code = 12;} #testo
    elsif($PM eq "create_rd_from_e2_and_e3_vbm") {$PM_code = 13;}
    elsif($PM eq "mask_images_vbm") {$PM_code = 14;}
    elsif($PM eq "set_reference_space_vbm") {$PM_code = 15;}

    elsif($PM eq "create_rigid_reg_to_atlas_vbm"){$PM_code = 21;}

    elsif($PM eq "create_affine_reg_to_atlas_vbm"){$PM_code = 39;} ## Intend to use a pairwise registration based module for the affine reg, analoguous to the MDT creation.

    elsif($PM eq "pairwise_reg_vbm") {$PM_code = 41;}
    elsif($PM eq "calculate_mdt_warps_vbm") {$PM_code = 42;}
    elsif($PM eq "apply_mdt_warps_vbm") {$PM_code = 43;}
    elsif($PM eq "mdt_apply_mdt_warps_vbm") {$PM_code = 43;}
    elsif($PM eq "calculate_mdt_images_vbm") {$PM_code = 44;}
    elsif($PM eq "mask_for_mdt_vbm") {$PM_code = 45;}
    elsif($PM eq "calculate_jacobians_vbm") {$PM_code = 46;}
    elsif($PM eq "calculate_jacobians_mdtGroup_vbm") {$PM_code = 47;}


    elsif($PM eq "compare_reg_to_mdt_vbm") {$PM_code = 51;}
    elsif($PM eq "reg_apply_mdt_warps_vbm") {$PM_code = 52;}
    elsif($PM eq "calculate_jacobians_regGroup_vbm") {$PM_code = 53;}

    elsif($PM eq "mdt_create_affine_reg_to_atlas_vbm") {$PM_code = 61;}
    elsif($PM eq "mdt_reg_to_atlas_vbm") {$PM_code = 62;}
    elsif($PM eq "warp_atlas_labels_vbm") {$PM_code = 63;}
    elsif($PM eq "label_images_apply_mdt_warps_vbm") {$PM_code = 64;}
    elsif($PM eq "label_statistics_vbm") {$PM_code = 65;}

    elsif($PM eq "smooth_images_vbm") {$PM_code = 71;}
    elsif($PM eq "vbm_analysis_vbm") {$PM_code = 72;}

    elsif($PM =~ /[0-9]{2}/) {$PM_code = $PM;}
    else  {$PM_code = 0;}

    my $end_time = time;
    my $real_time = ($end_time - $start_time);
    my $pm_string = "${PM_code},0,0,${start_time},${real_time},0";
    my ($write_out,$stats_file) = $Hf->get_value_check("stats_file");
    if ($write_out) {
        append_file($pm_string."\n");
        #run_and_watch("echo \"${pm_string}\" >> ${stats_file}");
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
