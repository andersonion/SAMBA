%compile mev
script_name = 'study_stats_by_contrast';
version = 1;

if (version == 1)
    v_string = '';
elseif (version > 1)
    v_string = ['_v' num2str(version)];
end


matlab_path = '/cm/shared/apps/MATLAB/R2015b/';
master_dir = '/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/label_stats_executables/';
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

source_dir='/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/label_stats/';
source_filename = ['study_stats_by_contrast_exec' v_string '.m'];
source_file = [source_dir source_filename]

include_string =[];
include_files = {};

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
