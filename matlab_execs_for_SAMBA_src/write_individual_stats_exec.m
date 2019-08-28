function write_individual_stats_exec_v3(runno,label_file,contrast_list,image_dir,output_dir,space,atlas_id,varargin)
% New inputs:
% runno: run number of interest
% label_file: Full path to labels
% contrast_list: comma-delimited (no spaces) string of contrasts
% image_dir: Directory containing all the contrast images
% output_dir
% space: 'native','rigid','affine','mdt', or atlas'; used in header
% atlas_id: used in header; may be used for pulling label names in the future.
% Following two are optional, and their order doesn't matter.
% lookup_table: a lookup table to load to keep our names/details straight
% first_contrast_mask: use first contrast to omit bits s
%
% A header is written at the top of the file listing on their own line:
%   --contrasts for which label stats have been calculated (this is to
%       faciliate checking for previous work, in case a new contrast is to be
%       added to the file.
%   --runno
%   --atlas from which the labels were derived
%   --space (native, rigid, affine, MDT, or atlas); Note that for MDT or
%       atlas spaces, all the volumes should/will be the same for all
%       runnos
%
%% 12 March 2019 update:
% Due to memory contraints introduced by processing the CCF3/ABA
% "quagmires" (raw master label sets) which require they are double
% datatype, the code was slightly edited such that it does not have to hold
% in memory the indices of the 0 label that are also 0 in a "nullable"
% contrast.  Typically this contrast is DWI, which is essentially
% guaranteed to only have zero elements where the whole data set should be
% masked.
%
%%

start_of_script=tic;

expected_output_subfolder='individual_label_statistics';
if numel(varargin)>0
    error_msg='';
    if (str2num(varargin{1})==1 | str2num(varargin{1})==0)
        use_first_contrast_to_mask=str2num(varargin{1});
    elseif exist(varargin{1},'file')
        lookup_table_path=varargin{1};
    else
        error_msg = [error_msg 'First optional input ''' varargin{1} ''' is invalid (must be either logical (0/1) or an existing lookup table.'];
    end
    
    if numel(varargin)>1
        if (~exist('use_first_contrast_to_mask','var') && (str2num(varargin{2})==1 | str2num(varargin{2})==0))
            use_first_contrast_to_mask=str2num(varargin{2});
        elseif (~exist('lookup_table_path','var') && exist(varargin{2},'file' ))
            lookup_table_path=varargin{1};
        else
            error_msg = [error_msg sprintf('\n') 'Second optional input ''' varargin{2} ''' is invalid (must be either logical (0/1) or an existing lookup table.'];
        end
    end
    
    if ~strcmp(error_msg,'')
        error(error_msg);
    end
end



if ~isdeployed
    if exist('iambj','var')
        % Default test variables:
        is_atlas=0;
        if ~exist('runno','var')
            %runno='N57008';
            %runno='N57009';
            %runno='N57010';
            %runno='N57020';
            %runno='chass_symmetric3_RAS';
            %runno='N56456';
            runno='N54794';
        end
        
        if is_atlas
            atlas_dir=['/cm/shared/CIVMdata/atlas/' runno '/'];
        end
        
        if ~exist('label_file','var')
            if is_atlas
                label_file=[atlas_dir runno '_labels.nii.gz'];
            else
                %label_file=['/mnt/civmbigdata/civmBigDataVol/jjc29/VBM_18gaj42_chass_symmetric3_BXD62-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n4_i6/stats_by_region/labels/pre_rigid_native_space/C57_BXD62/' runno '_WHS_labels.nii.gz'];
                %label_file=['/civmnas4/rja20/SingleSegmentation_16gaj38_chass_symmetric3_RAS_N56456-work/dwi/fa/faMDT_NoNameYet_n1/stats_by_region/labels/pre_rigid_native_space/CCF3//N56456_CCF3_mess.nii.gz'];
                label_file=['/civmnas4/rja20/VBM_17gaj40_chass_symmetric2_C57f-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n4_i6/stats_by_region/labels/pre_rigid_native_space/CCF3//N54794_CCF3_mess.nii.gz'];
            end
        end
        
        if ~exist('contrast_list','var')
            if is_atlas
                contrast_list='DWI,FA,MD,MO,T2';
            else
                contrast_list='dwi,fa,adc,b0';
                %contrast_list='dwi,fa,iso';%,gfa,nqa,qa,b0avg,ad,rd,md';
            end
        end
        
        if ~exist('image_dir','var')
            if is_atlas
                image_dir=atlas_dir;
            else
                %image_dir='/mnt/civmbigdata/civmBigDataVol/jjc29/VBM_18gaj42_chass_symmetric3_BXD62-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n4_i6/stats_by_region/labels/pre_rigid_native_space/images/';
                %image_dir='/civmnas4/rja20/SingleSegmentation_16gaj38_chass_symmetric3_RAS_N56456-work/dwi/fa/faMDT_NoNameYet_n1/stats_by_region/labels/pre_rigid_native_space/images/';
                image_dir='/civmnas4/rja20/VBM_17gaj40_chass_symmetric2_C57f-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n4_i6/stats_by_region/labels/pre_rigid_native_space/images/';
            end
        end
        if ~exist('output_dir','var')
            if is_atlas
                output_dir=atlas_dir;
            else
                output_dir='~/';%'/civmnas4/rja20/';
            end
        end
        
        if ~exist('space','var')
            space='rigid';
        end
        
        if ~exist('atlas_id','var')
            if is_atlas
                atlas_id=runno;
            else
                %atlas_id='chass_symmetric3_RAS';
                atlas_id='CCF3';
            end
        end
        
        if ~exist('lookup_table_path','var')
            if is_atlas
                lookup_table_path=[atlas_dir '/' runno '_labels_lookup.txt'];
            else
                %lookup_table_path='/cm/shared/CIVMdata/atlas/C57/C57_labels_lookup.txt';
                %lookup_table_path='/civmnas4/rja20/SingleSegmentation_16gaj38_chass_symmetric3_RAS_N56456-work/dwi/fa/faMDT_NoNameYet_n1/stats_by_region/labels/pre_rigid_native_space/CCF3/CCF3_quagmire_lookup.txt';
                lookup_table_path='/civmnas4/rja20/VBM_17gaj40_chass_symmetric2_C57f-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n4_i6/stats_by_region/labels/pre_rigid_native_space/CCF3/N54794_CCF3_mess_lookup.txt';
            end
        end
        
        if ~exist('use_first_contrast_to_mask','var')
            use_first_contrast_to_mask=1;
        end
        
    else
        if (exist(output_dir,'dir') && (~exist('space','var') || ~exist('atlas_id','var')))
            %output_dir='/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/chass_symmetric2/stats/';
            folder_cell = strsplit(strjoin(strsplit(output_dir,'//'),'/'),'/');
            folder_cell=folder_cell(~cellfun('isempty',folder_cell));
            if strcmp(folder_cell{end},expected_output_subfolder)
                folder_cell(end)=[];
                folder_cell(end)=[];
            end
            
            default_atlas_id = folder_cell{end};
            
            def_space_string = folder_cell{end-1};
            
            dss_cell=strsplit(def_space_string,'_');
            dss_cell(end)=[];
            dss_cell(end)=[];
            raw_default_space = strjoin(dss_cell,'_');
            
            switch raw_default_space
                case 'pre_rigid'
                    default_space = 'native';
                case 'post_rigid'
                    default_space = 'rigid';
                case 'pre_affine'
                    default_space = 'rigid';
                case 'post_affine'
                    default_space = 'affine';
                case 'mdt'
                    default_space = 'mdt';
                case 'MDT'
                    default_space = 'MDT';
                case 'atlas'
                    default_space = 'atlas';
                otherwise
                    default_space = 'native';
            end
        end
        
        
        if ~exist('space','var')
            space=default_space;
        end
        
        if ~exist('atlas_id','var')
            if exist('default_atlas_id','var')
                atlas_id=default_atlas_id;
            else
                atlas_id='chass_symmetric3_RAS';
            end
        end
        
        if ~exist('use_first_contrast_to_mask','var')
            use_first_contrast_to_mask=0;
        end
    end
end

contrasts = strsplit(contrast_list,',');

output_name=[runno '_' atlas_id '_measured_in_' space '_space'];
output_stats = [output_dir output_name '_stats.txt'];

previous_work=zeros(size(contrasts));
if exist(output_stats,'file')
    
    working_table = readtable(output_stats,'Delimiter','\t');
    if ~strcmp(working_table.Properties.VariableNames{1},'ROI')
        % We used to write several lines of header info, but that is replaced
        % with writetable, with no headers.
        working_table = readtable(output_stats,'HeaderLines',4,'Delimiter','\t');
    end
    
    contrast_list2=working_table.Properties.VariableNames;
else
    contrast_list2={'ROI' 'voxels' 'volume_mm3'};
end

contrasts_to_process=0;
for ii=1:length(contrasts)
    contrast = contrasts{ii};
    previous_work(ii) = ~isempty(find(strcmp([contrast '_mean' ],contrast_list2),1)) ;
    if ~previous_work(ii)
        contrast_list2{length(contrast_list2)+1} = [contrast '_mean'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_std'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_min'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_max'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_CoV'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_nulls'];
        contrasts_to_process=contrasts_to_process+1;
    end
end

fprintf('Header on output \n>\t%s\n',strjoin(contrast_list2,','));

if contrasts_to_process > 0
    if use_first_contrast_to_mask
        contrast = contrasts{1};
        % contrast_stats=zeros(size(volume_mm3));
        filenii_i=[image_dir runno '_' contrast '.nii']; % Does not yet support '_RAS' suffix, etc yet.
        if ~exist(filenii_i,'file')
            filenii_i = [filenii_i '.gz'];
        end
        fprintf('Loading first contrast, and using it to infer a mask for the first ROI (usually 0): %s\n',filenii_i);
        imnii_i=load_niigz(filenii_i);
        %imnii_i.img=imnii_i.img(:);
    end
    
    % This is the count of elements in label 0 that are ignored and thus by default assumed to be null for stat purposes.
    null_element_base = 0;
    
    label_orig=load_niigz(label_file);
    voxel_vol=label_orig.hdr.dime.pixdim(2)*label_orig.hdr.dime.pixdim(3)*label_orig.hdr.dime.pixdim(4);
    %labelim=label_orig.img(:);
    %clear label_orig; % We got everything we needed so can remove from memory
    %ROI=unique(labelim);
    ROI=unique(label_orig.img);
    
    % Old code begin
    
    %n=length(ROI);
    %edges = ROI-0.5;
    %edges = [edges' (max(edges(:))+1)]';
    %[voxels, ~] =  histcounts(labelim,edges);
    
    % Old code end
    % New code as of 19 February 2019, pre-calculate indices for each ROI
    % Keep them on hand in a cell so we don't need to use FIND each time
    % (this is a surprisingly intensive process)
    ROI_indices=cell(size(ROI));
    voxels=zeros(size(ROI));
    
    fprintf('Begin processing info for %d ROIs in %s:\n',numel(ROI),label_file);
    start_t=tic;
    for ind=1:numel(ROI)
        if ~mod((ind-1),25) %&& isdeployed
            fprintf('Processing ROI %d of %d...\n',ind,numel(ROI));
            % elapsed_time = toc(start_t);
            % fprintf('Processing ROI %d of %d. Elapsed time = %f s...\n',ind,numel(ROI),elapsed_time);
            % start_t=tic;
        end
        if ((ind==1) && use_first_contrast_to_mask)
            null_indices=(label_orig.img(:)==ROI(ind)) & (imnii_i.img(:) == 0);
            null_element_base = nnz(null_indices);
            labelim=label_orig.img(~null_indices(:));
            clear label_orig;
            current_image=imnii_i.img(~null_indices);
            clear imnii_i;
            ROI_indices{ind} = find((labelim==ROI(ind)) & (current_image ~= 0));
        elseif ((ind==1) && ~use_first_contrast_to_mask)
            labelim=label_orig.img(:);
            clear label_orig;
            ROI_indices{ind} = find(labelim==ROI(ind));
        else
            ROI_indices{ind} = find(labelim==ROI(ind));
        end
        
        voxels(ind)= numel(ROI_indices{ind});
    end
    clear labelim; % We got everything we needed so can remove from memory
    %voxels = voxels';
    elapsed_time = toc(start_t);
    fprintf('Done processing info for %d ROIs in %s.\nElapsed time = %f s\n',numel(ROI),label_file,elapsed_time);
    
    % Calculate volume in mm^3
    volume_mm3=voxels*voxel_vol;
    
    
    if ~exist(output_stats,'file')
        working_table = table(ROI,voxels,volume_mm3);
    end
    
    for ii=1:length(contrasts)
        
        if ~previous_work(ii)
            contrast = contrasts{ii};
            if ((ii==1) && use_first_contrast_to_mask && exist('current_image','var'))
                % imnii_i is already in memory, do not load again (do nothing)
            else
                
                % contrast_stats=zeros(size(volume_mm3));
                filenii_i=[image_dir runno '_' contrast '.nii']; % Does not yet support '_RAS' suffix, etc yet.
                if ~exist(filenii_i,'file')
                    filenii_i = [filenii_i '.gz'];
                end
                fprintf('load nii %s\n',filenii_i);
                imnii_i=load_niigz(filenii_i);
                if use_first_contrast_to_mask
                    current_image=imnii_i.img(~null_indices);
                else
                    current_image=imnii_i.img(:);
                end
                clear imnii_i;
            end
            
            for ind=1:numel(ROI)
                
                fprintf('For contrast "%s" (%i/%i), processing region %i of %i (ROI %i)...\n',contrast,ii,length(contrasts),ind,numel(ROI),ROI(ind));
                %regionindex=find(labelim==val1(ind));
                %contrast_stats(ind)=mean(imnii_i.img(labelim==ROI(ind)));
                %%Switched to the code below on 27 Feb 2018, to ignore masked
                %%voxels in the ROI
                data_vector=current_image(ROI_indices{ind});
                
                nulls=numel(data_vector)-nnz(data_vector) + (ind==1)*null_element_base ;
                data_vector(data_vector==0)=[];
                contrast_stats.mean(ind)=mean(data_vector);
                
                if numel(data_vector)>0
                    contrast_stats.std(ind)=std(data_vector,0,1);
                    contrast_stats.min(ind)=min(data_vector);
                    contrast_stats.max(ind)=max(data_vector);
                    
                else
                    contrast_stats.std(ind)=NaN;
                    contrast_stats.min(ind)=NaN;
                    contrast_stats.max(ind)=NaN;
                end
                contrast_stats.CoV(ind)=contrast_stats.std(ind)/contrast_stats.mean(ind);
                contrast_stats.nulls(ind)= nulls;
                % James says maybe we insert code to write out useful
                % histograms here, since we have the relevant data in memory.
            end
            stat_names=fieldnames(contrast_stats);
            for sn=1:numel(stat_names)
                working_table.([contrast '_' stat_names{sn} ])=contrast_stats.(stat_names{sn})';
            end
            %eval_cmd = ['working_table.' contrast '=contrast_stats;'];
            %eval(eval_cmd);
        end
        clear current_image;
    end
    
    
else
    
    fprintf('No extra work to be done; will add structure info if need be (and lookup table is available), and rewrite to original file.\n');
end



if ~strcmp(working_table.Properties.VariableNames{2},'structure')
    %% Process lookup table, if available
    % Implementing lookup table support! 20 February 2019
    
    if exist('lookup_table_path','var') && exist(lookup_table_path,'file')
        try 
            % 20 March 2019:
            % Older lookups are space seperated; the first try will fail on
            % newer tab separated files.  If we were to try the "right"
            % (aka newer) format first, it would still be successful with
            % the space separated file, but not do what we want (RGBA info
            % would be included in the structure name.
            try
                lookup=readtable(lookup_table_path,'Delimiter',' ','ReadVariableNames',false,'Format','%d64%s%d%d%d%d','CommentStyle','#');
            catch
                lookup=readtable(lookup_table_path,'Delimiter','\t','ReadVariableNames',false,'Format','%d64%s%d%d%d%d','CommentStyle','#');
            end
            
            % This code is bona fide because LOOKUPS should/must have the
            % format where first column is ROI number and second is
            % structure/name.  Any columns after this are ignored here.
            final_table=outerjoin(working_table,lookup,'Type','Left','LeftKeys',{'ROI'},'RightKeys',1,...
                'RightVariables',2);
            final_table=[ final_table(:,1) final_table(:,end) final_table(:,2:(end-1))];
            final_table.Properties.VariableNames{2}='structure';
            label_msg=sprintf('Structure names successfully added from lookup table:\n\t%s',lookup_table_path);
        catch
        	label_msg=sprintf('Failure on processing lookup table, no structure names will be added. Offending file:\n\t%s',lookup_table_path);
            final_table=working_table;
        end
    else
        label_msg=['No valid lookup table specified...only ROI number will be reported.'];
        final_table=working_table;
    end
    disp(label_msg);

else
    final_table=working_table;
end

%% Write to file
writetable(final_table,output_stats,'QuoteStrings',true,'Delimiter','\t','WriteVariableNames',true);
total_elapsed_time=toc(start_of_script);
fprintf('WORK COMPLETE! Results written to %s.\nTotal processing time: %f s.',output_stats,total_elapsed_time);
end
