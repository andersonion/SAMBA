function err=bulk_CoV_report_gen(stats_dir,atlas_dir)
%function failed_stats_count=bulk_CoV_report_gen(stats_dir,atlas_dir)
% given a folder with stats.txt files (anywhere inside it) where they're 
% named in the standard way:
% (SPEC/RUN)_(atlas_id)_measured_in_space_stats.txt
%
% and an atlas directory (which is organized in the new standard way)
% run the cov QA generator on that stats file.
% WARNING: QA results are generated in a folder DIRECTLY next to stats files found!
%   IF you bury your stats files(or work on burried stats files) you will
%   have to dig out your QA results.
% 
% The expected usage is to have a folder with all your stats files of
% interest DIRECTLY inside it, with no subfolders separating them.
% That will create a single qa_lookups and reports folder to allow you to 
% browse studywide info. (Inside the stats dir.)
% You can use folders of (symbolic) links, or just copy stats to a common
% folder.
% 
%
% This function relies on naming conventions to do it's work.
% stats files should be named after their data of interest, and atlas_id.
% data of interest at CIVM is RUNNO, or specimen id. 
% There cannot be any underscores in the atlasID (sorry). 
% For most reliability, only letters and numbers in atlasid's
% ex, data=N012345, atlas_id=WHS, space=native_space
%     ->  N012345_WHS_measured_in_native_space_stats.txt
[~,atlas,~]=fileparts(atlas_dir);
stat_files=wildcardsearch(stats_dir,'*stats.txt',1,1);
if numel(stat_files)==1
    warning('%s\n%s\n%s\n\t%s\n%s'... 
        ,'Only one stat file found! This is not the ideal condition!'...
        ,'It is better to have them all in the same place to contain'...
        ,'the mass of lookup tables and pdf''s generated'...
        ,'(You can fake that using symbolic links.)'...
        ,'Ctrl+C to cancel (continue in 10 seconds)');
    pause(10);
end
err=0;
for i_s=1:numel(stat_files)
    %N57025_WHS4_measured_in_native_space_stats.txt
    [~,stat_name]=fileparts(stat_files{i_s});
    bits=strsplit(stat_name,'_measured');
    bits=strsplit(bits{1},'_');
    atlas_id=bits{end};
    id=strjoin(bits(1:end-1),'_');
    try
        % Former atlas pattern, updated for symmetric45um
        % a_p=fullfile(atlas_dir, 'labels',atlas_id, [atlas '_labels']);
        a_p=fullfile(atlas_dir, 'labels',atlas_id, [atlas '_' atlas_id '_labels']);
        % Full contrast list
        % output=generate_QA_for_coeffecient_of_variation(id,stat_files{i_s},'volume_mm3,dwi,fa,ad,rd,gfa,nqa,md',a_p);
        % Minimal contrast list
        output=generate_QA_for_coeffecient_of_variation(id,stat_files{i_s},'volume_mm3,dwi,fa',a_p);
    catch merr
        disp(merr);
        err=err+1;
    end
end
fprintf('%s complete\n',mfilename);
return;
