function compile_command_for_write_stats()
script_name = 'write_individual_stats';
version = 2;

if (version == 1)
    v_string = '';
elseif (version > 1)
    v_string = ['_v' num2str(version)];
end

source_dir='/cm/shared/workstation_code_dev/analysis/SAMBA/label_stats/';
source_filename = ['write_individual_stats_exec' v_string '.m'];
source_file = [source_dir source_filename]

include_string =[];
include_files = {};%'/cm/shared/workstation_code_dev/shared/civm_matlab_common_utils/GzipRead.java' '/cm/shared/workstation_code_dev/shared/civm_matlab_common_utils/GzipRead.class'};

addpath([getenv('WORKSTATION_HOME') '/recon/CSv2']);
compile_command__allpurpose(source_file,include_files,'');

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

compile_dir = [main_dir compile_time '/']
mkdir(compile_dir)
eval(['!chmod a+rwx ' compile_dir]);

for ff = 1:length(include_files)
    include_string = [include_string ' -a ' include_files{ff} ' '];
end

eval(['mcc -N -d  ' compile_dir...
   ' -C -m '...
   ' -R -singleCompThread -R nodisplay -R nosplash -R nojvm '...
   ' ' include_string ' '...
   ' ' source_file ';']) 

cp_cmd_2 = ['cp  ' source_file ' ' compile_dir];
system(cp_cmd_2)

for ff = 1:length(include_files)
    cp_cmd = ['cp ' include_files{ff} ' ' compile_dir];
    system(cp_cmd);
end

first_run_cmd = [compile_dir '/run_' source_filename];
first_run_cmd(end)=[];
first_run_cmd = [first_run_cmd 'sh ' matlab_path];
system(first_run_cmd);
eval(['!chmod a+rwx -R ' compile_dir '/*'])

matlab_execs_dir = fullfile(getenv('WORKSTATION_HOME'),'matlab_execs');
exec_name=[ script_name '_executable'];
this_exec_base_dir=fullfile(matlab_execs_dir,exec_name);
latest_path_link = fullfile(this_exec_base_dir,'latest');
%% link to latest
if exist(latest_path_link,'dir')
    rm_ln_cmd = sprintf('unlink %s',latest_path_link);
    system(rm_ln_cmd)
end
ln_cmd = sprintf('ln -s %s %s',compile_dir,latest_path_link);
system(ln_cmd);
