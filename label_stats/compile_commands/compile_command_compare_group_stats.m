function compile_command_compare_group_stats()
% in testing needed nanmean and fdr_bh. Added the others just to avoid
% further hassle.
include_files={
    which('nanmean') ...
    fullfile(fileparts(which('compare_group_stats_exec')),'fdr_bh','fdr_bh.m') ...
    which('mattest') ...
    which('ttest2')
    };
compile_command__allpurpose('compare_group_stats_exec',include_files);

%{
% renamed v1 and v2 of the script in prep to remove v1.
% v2 is now plainly compare_group_stats_exec, and v1 is
compare_grou_stats_exec_v1
script_name = 'compare_group_stats';
version = 2;
if (version == 1)
    v_string = '';
elseif (version > 1)
    v_string = ['_v' num2str(version)];
end


source_dir='/cm/shared/workstation_code_dev/analysis/SAMBA/label_stats/';
source_filename = ['compare_group_stats_exec' v_string '.m'];
source_file = [source_dir source_filename];

include_files = {'/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/label_stats/fdr_bh/fdr_bh.m' ...
    '/cm/shared/apps/MATLAB/R2015b/toolbox/bioinfo/microarray/mattest.m' ...
    '/cm/shared/apps/MATLAB/R2015b/toolbox/stats/stats/ttest2.m'};


addpath([getenv('WORKSTATION_HOME') '/recon/CSv2']);
compile_command__allpurpose(source_file,include_files,'');
%}
return


%% The code below was the former full code used for compiling and copying, etc.
%  It has been replaced with the codified compile_command__allpurpose


matlab_path = '/cm/shared/apps/MATLAB/R2015b/';
master_dir = '/cm/shared/workstation_code_dev/analysis/SAMBA/label_stats_executables/';
main_dir = [master_dir script_name '_executable/'];

if ~exist(main_dir,'dir')
    mkdir(main_dir)
    eval(['!chmod a+rwx ' main_dir]);
end

ts=fix(clock);
compile_time=sprintf('%04i%02i%02i_%02i%02i%02i',ts(1:5));

my_dir = [main_dir compile_time '/']
mkdir(my_dir)
eval(['!chmod a+rwx ' my_dir]);

include_string =[];
for ff = 1:length(include_files)
    include_string = [include_string ' -a ' include_files{ff} ' '];
end

eval(['mcc -N -d  ' my_dir...
   ' -C -m '...
   ' -R -singleCompThread -R nodisplay -R nosplash -R nojvm '...
   ' ' include_string ' '...
   ' ' source_file ';']) 

cp_cmd_2 = ['cp  ' source_file ' ' my_dir];
system(cp_cmd_2)

for ff = 1:length(include_files)
    cp_cmd = ['cp ' include_files{ff} ' ' my_dir];
    system(cp_cmd);
end

first_run_cmd = [my_dir '/run_' source_filename];
first_run_cmd(end)=[];
first_run_cmd = [first_run_cmd 'sh ' matlab_path];
system(first_run_cmd);
eval(['!chmod a+rwx -R ' my_dir '/*'])
