

pipe_start=fullfile(getenv('WKS_SHARED'),'pipeline_utilities','startup.m');
run(pipe_start);
atlas_dir=fullfile('l:','workstation','data','atlas','symmetric45um');
%stats_dir=fullfile('\\piper\piperspace\18.gaj.42_packs_BXD89');
stats_dir=fullfile('\\piper\piperspace\18.gaj.42_packs_BXD89\stats');
% err=bulk_CoV_report_gen(stats_dir,atlas_dir)
err=bulk_CoV_report_gen(stats_dir,atlas_dir);
% [CoV_array,stats_table] = calculate_coeffecient_of_variation( stats_table,field, delta )