function compile_command_for_write_stats()

gotcha_cache=fullfile(fileparts(which('write_individual_stats_exec')),sprintf('%s_gotchas.txt','write_individual_stats_exec'));

include_files = {gotcha_cache
    '/cm/shared/workstation_code_dev/shared/mathworks/wildcardsearch/regexpdir.m'

};
compile_command__allpurpose('write_individual_stats_exec',include_files,'')

return