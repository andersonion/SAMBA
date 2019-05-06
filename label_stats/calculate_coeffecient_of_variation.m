function [ CoV_array ] = calculate_coeffecient_of_variation( individual_stat_file,field, delta )
%CALCULATE_COEFFECIENT_OF_VARIATION Smartly calculate CoV between L/R ROIs
%   Input an individual stat file as produced by VBA, etc pipeline
%   Define the field (vol, fa, etc) on which to work
%   Use a difference constant 'delta' to map L-R pairs
%individual_stat_file='/cm/shared/CIVMdata/atlas/xmas2015rat_symmetric_cropped/xmas2015rat_symmetric_cropped_xmas2015rat_symmetric_cropped_labels_in_native_space_stats.txt';
%individual_stat_file='/civmnas4/rja20/data_from_glusterspace/VBM_17gaj40_chass_symmetric2_CAST-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n8_i6/stats_by_region/labels/pre_rigid_native_space/CAST_symmetric_R/stats/individual_label_statistics/N54823_CAST_symmetric_R_labels_in_native_space_stats.txt';
isf=individual_stat_file;
%field='volume_mm3';
%delta=1;

do_process=1;
if exist(isf, 'file')
    % this line fails when we have header lines... like in the old days : (
    master_T = readtable( isf,'ReadVariableNames',1,'HeaderLines',0,'Delimiter','\t');
    % so we'll read the table twice.... once the new way, and once the old
    % way, if the old way has more columns, we'll use that. 
    master_T_o = readtable( isf,'ReadVariableNames',1,'HeaderLines',4,'Delimiter','\t');
    if size(master_T,2)<size(master_T_o,2)
        warning('OLD data detected! This is probably fine, just wanted to leave a mess in your console :D !');
        master_T=master_T_o;
    end
    clear master_T_o;
else
    CoV_array=0;
    do_process=0;
end
if do_process
    existing_fields = master_T.Properties.VariableNames;
    explicit_ROIs=1;
    if ismember('ROI',existing_fields)
        raw_array=master_T.ROI;
    else
        explicit_ROIs=0;
    end
    if exist('field','var')
        if ismember(field,existing_fields)
            c_field=field;
        elseif ismember([field '_mean'],existing_fields)
            c_field=[field '_mean'];
        elseif str2num(field) <= numel(existing_fields)
            c_field=field{str2num(field)};
        else
            disp(['Error: field "' field '" not found in input file. Dying now.'])
            return;
        end
    else
        c_field=existing_fields{2};
    end
    
    raw_array=[raw_array,master_T.(c_field)]';
    
    
    n_ROIs=size(raw_array,2);
    odd_or_even=mod(n_ROIs,2);
    
    % If odd, assume the first entry is whole-brain exterior '0'
    if ((odd_or_even) || ~raw_array(1,1))
        try
            raw_array(:,((raw_array(1,:)==0)))=[];
        catch
        end
        n_ROIs=size(raw_array,2);
        odd_or_even=0;
    end
    
    if ~explicit_ROIs
        raw_array(1,:)=1:1:n_ROIs;
    end
    
    all_ROIs = raw_array(1,:);
    if ~exist('delta','var')
        delta=all_ROIs(n_ROIs)-all_ROIs(round(n_ROIs/2));
    end
    
    
    field_data=raw_array(2,:);
    processed_ROIs=[];
    
    intermediate_array=[];
    for rr=1:numel(all_ROIs);
        c_ROI=all_ROIs(1,rr);
        if ~ismember(c_ROI,processed_ROIs)
            c_ROI_L=c_ROI;
            c_ROI_R=c_ROI+delta;
            if ~ismember(c_ROI_R,processed_ROIs) &&  ismember(c_ROI_R,all_ROIs)
                i_cRR=find(all_ROIs==c_ROI_R);
                intermediate_array=[intermediate_array; c_ROI_L, field_data(rr),field_data(i_cRR)];
                processed_ROIs=[processed_ROIs c_ROI_L c_ROI_R];
            end
        end
    end
    intermediate_array=intermediate_array';
    CoV_array=zeros([2,size(intermediate_array,2)]);
    
    CoV_array(1,:)=intermediate_array(1,:);
    CoV_array(2,:)=std(intermediate_array(2:3,:),0,1)./mean(intermediate_array(2:3,:),1); % It is important that the second std option be set to 0 to match what Nian did in Excel.
    
end
%end

