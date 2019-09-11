function compile_command_for_write_stats()

gotcha_cache=fullfile(fileparts(which('write_individual_stats_exec')),sprintf('%s_gotchas.txt','write_individual_stats_exec'));
include_files = {gotcha_cache};
compile_command__allpurpose('write_individual_stats_exec',include_files,'')

return