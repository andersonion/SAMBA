function [] = surfstat_for_vbm_pipeline_exec(contrast,average_mask,inputs_directory,results_directory,group_1_name,group_2_name,group_1_filenames,group_2_filenames)

% clear all, close all, clc
% test=0;
% if (test)
%     %% test inputs
%     contrast = 'fa';
%     average_mask = '/Users/rja20/data/VBM/Surfstat_test/MDT_mask_e3.nii';
%     inputs_directory ='/Users/rja20/data/VBM/Surfstat_test/';
%     results_directory ='/Users/rja20/data/VBM/Surfstat_test/Results/';
%
%     group_1_name = 'control';
%     group_2_name = 'phantom';
%
%     group_1_filenames= '/Control/S64944_fa_to_MDT.nii,/Control/S64953_fa_to_MDT.nii,/Control/S64959_fa_to_MDT.nii,Control/S64962_fa_to_MDT.nii,Control/S64968_fa_to_MDT.nii,/Control/S64974_fa_to_MDT.nii';%SurfStatListDir([control_dir '*' contrast '*.nii']);
%
%     group_2_filenames='/Phantom/W64944_fa_to_MDT.nii,/Phantom/W64953_fa_to_MDT.nii,/Phantom/W64959_fa_to_MDT.nii,Phantom/W64962_fa_to_MDT.nii,Phantom/W64968_fa_to_MDT.nii,/Phantom/W64974_fa_to_MDT.nii';%SurfStatListDir([tx_dir '*' contrast '*.nii']);
% end
%% variables hardcoded for now
%%
% fa_thresh=0.27;%for fa includes all brain
% fa_mask_filename = [results_directory '/fa_mask_0p27.mat'];

%%
g1_filenames = strsplit(group_1_filenames,',');
g1_filenames=g1_filenames';
g2_filenames = strsplit(group_2_filenames,',');
g2_filenames =g2_filenames';
for n1 = 1:length(g1_filenames)
    group_1_files{n1}= [inputs_directory g1_filenames{n1}];
end
group_1_files=group_1_files';

for n2 = 1:length(g2_filenames)
    group_2_files{n2}= [inputs_directory g2_filenames{n2}];
end
group_2_files=group_2_files';
%path to directory
%define treatment matrix

%set these variables
path = results_directory; %base directory
if ~isdeployed
    addpath('/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/surfstat/');
    %mask='/Volumes/cretespace/CVN/cvn_dbm_cluster/median_images/MDT_maskE3.nii';#
end

%% SPM starts here

filenames=[group_1_files; group_2_files];
dof=length(filenames)-2;

%set up layout and read single slices
%1 = group_1, 0 = group_2,
naughts=4-rem(length(filenames),4);%find how many zeros we need to add to layout
%control_var=cat(2,ones(1,length(group_1_files)),zeros(1,length(group_2_files)));
%%% 4 March 2016: YUGE bug fixed, changing line above to line below. What
%%% was needed here was group numbers (i.e. "1" and "2"), not a binary
%%% vector indicating which images are controls (i.e. "1"=control,
%%% "2"=treated). Below, the line "Group = term..." needs the values
%%% assigned here to be ASCENDING, otherwise a clusterflub of a reassigment
%%% of images to control or treated will occur (or even worse, partial reassignment in
%%% the case of unequal number of subjects). Also fixed the "layout = ..."
%%% line to match.
control_var=cat(2,ones(1,length(group_1_files)),2*ones(1,length(group_2_files)));
%layout = reshape( [find(control_var) zeros(1,naughts+4) find(1-control_var)], [], 4);%make a layout for viewing
layout = reshape( [find(2-control_var) zeros(1,naughts+4) find(control_var-1)], [], 4);%make a layout for viewing


[wmav volwmav]=SurfStatAvVol({average_mask; average_mask});% read average mask
%[wmav, volwmav]=SurfStatAvVol(group_1_files);% read average mask



[ Y0, vol0 ] = SurfStatReadVol( filenames, [], { [], [], 2 } );% read all volumes at 2mm slice
figure(1); SurfStatViews( Y0, vol0, 0, layout );

mytitle=char([char(contrast) ' for ' num2str(length(group_1_files)) ' ' group_1_name ' (left) and ' num2str(length(group_2_files)) ' ' group_2_name ' (right)']);

title(mytitle,'FontSize',18);


mask=wmav>0;
% switch contrast
%     case {'fa'} %jac , fa ad and is reduced by treatment
%         %define mask based on fa
%         myfamask=wmav > fa_thresh;
%         save(fa_mask_filename,'myfamask')
%         mask=myfamask;
%     case {'dwi','e1','e3','e2', 'rd','adc'} %rd is increased by treatment
%         %if DTI but not fa load mask
%         load(fa_mask_filename)
%         mask=myfamask;
%     case{'jac'}
%         thresh=0.02;
%         mask=wmav > thresh;
% end



%read data above mask treshold and do stats
[ Y, vol ] = SurfStatReadVol( filenames, mask);


Group = term( var2fac( control_var', { group_1_name ; group_2_name } ) );
slm = SurfStatLinMod( Y, Group, vol );

%hypothesis

for direction = (0:1)
    if (direction)  % Up until 26 January 2016, we had code which would flip the sign if your input contrast was 'jac'
        % IT IS IMPORTANT to note that the default behaviour was to call
        % contrast 'jac_from_mdt', and would not trigger this condition.
        % We should no longer need to flip sign apart from changing
        % direction.  Also note that the data for the VBA manuscript and
        % poster featured this bug, i.e. 'jac' contrasts were group_2 -
        % group_1
        slm = SurfStatT( slm, Group.(group_1_name) - Group.(group_2_name) );
        suffix = ['_' group_1_name '_gt_' group_2_name];
    else
        slm = SurfStatT( slm, Group.(group_2_name) - Group.(group_1_name) );
        suffix = ['_' group_2_name '_gt_' group_1_name];
    end
    
    title('Q-value < 0.05','FontSize',18);
    qval=SurfStatQ( slm);
    
    %save volumes
    p_uncorr=1-tcdf(slm.t, dof); %for one tailed test
    
    pv_unc_name = [results_directory contrast '_pvalunc' suffix '.nii'];
    SurfStatWriteVol(pv_unc_name,p_uncorr,vol);
    SurfStatWriteVol([results_directory contrast '_pval2' suffix '.nii'],qval.P,vol); %Test/debug
    %SurfStatWriteVol([out_tx_dir contrast '_pval' suffix '.nii'],pval.P,vol);
    SurfStatWriteVol([results_directory contrast '_qval' suffix '.nii'],qval.Q,vol);
    SurfStatWriteVol([results_directory contrast '_effect' suffix '.nii'],slm.ef,vol);
    SurfStatWriteVol([results_directory contrast '_tstat' suffix '.nii'],slm.t,vol);
    
    
    figure(3); SurfStatView1( slm.t, vol );
    title( 'T-statistic' ,'FontSize',18);
    
    %save figures
    h = get(0,'children');
    h = sort(h);
    for i=1:length(h)
        saveas(h(i), [results_directory contrast '_figure_' num2str(i) suffix], 'fig');
    end
end
%exit % need to switch back to exit after debugging
end
