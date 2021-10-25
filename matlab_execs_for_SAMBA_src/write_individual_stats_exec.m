function [statfile_path,stat_table]=write_individual_stats_exec(runno,label_file,...
    contrast_list,image_dir, ...
    output_dir,space,atlas_id,varargin)
% [statfile_path,stat_table]=WRITE_INDIVIDUAL_STATS_EXEC(img_ident,ident_label_file,contrast_list,search_dir,output_dir,measurespace,atlas_id,lookup_table,optimize_mem_bool)
% Loads up a label file and series of image files and does basic measures 
% of each regions. 
% Saves at tab csv file with one line per region measured, 
% columns are min,max,stddev,mean,spread,nulls for each image loaded, 
% + volume_mm3 and region number and structure(abbrev__name). 
% spread is stddev/mean
% Also saves the gotchas disclaimers next to the stats sheet in the hopes 
% of reducing mis-interpretation of the values.
% 
% It supports nrrd(nhdr) and niftis. 
% 
% Input images must be named after their identifier(runno or specid) and the contrast. 
% Ideally IDENTIFIER_CONTRAST.IMGEXT, if your filenames are not the ideal 
% case it will try to find files with the information in that order.
% Auto find is fairly robust (and prefered over renaming), HOWEVER you
% will need to read the output to be sure it loaded the images you expected.
%
% -- Inputs --
% img_ident: identity of the img group, typically run number,
%            could be anything.
% ident_label_file: Full path to labels for this ident
% contrast_list: comma-delimited (NO SPACES) string of contrasts
% search_dir: Directory containing all the contrast images
% output_dir: output stats folder, your file will be autonamed!(sorry)
%             output name format,
%             (img_ident)_(atlas_id)_measured_in_(space)_space_stats.txt
%  The following two are only used in output name.
% space: Preferred values, 'native','rigid','affine','mdt', or atlas'
% atlas_id: Preffered values 'WHS','CCF3CON', or 'CCF3'. 
%      (This should try to capture which label atlas is used, it could be 
%       used for pulling label names in the future if they weren't in your
%       lookup table.)
% Following two are optional, and their order doesn't matter. 
% and THEY ARE STRONGLY RECOMMENDED!
% lookup_table: a lookup table to load to keep our names/details straight
%               (modern label volumes should have a slicer compatabile
%               lookuptable named after them ending in _lookup.txt.)
% optimize_mem_bool: use first contrast to omit bits. Anywhere in the first
%         contrast that is exactly 0 will not be part of your measurements.
%         This is almost always a good idea, AND means you should specify
%         dwi first.
% -- Outputs --
% statfile_path - the path to the stats file we saved.


%% Blank line above to separate help from const warning of gotchas.
%{
_stats.txt sheet gotchas
Voxels is the count of voxels for that value in the label map.
Exterior means "excluded in labels". It is left in the stat sheets as a 
quality metric of masking and missed data. Its non-null volume could be 
seen as a measure of mask error.
Volume is the volume covered by a label (voxels * voxelsize^3).

All undefined regions in the labelset (poorly duplicated LUT) will
duplicate all undefined region in the labelset to Exterior volumes. Sort
remove the "0" to exclude. 

Null columns are voxels with a value of exactly 0. 
The nulls indicate calculation errors OR data which has been masked out.
mean/min/max/std exclude any nulls, if you wish to include nulls, you'll 
need to scale accordingly.
The percent null (per structure) may be an indicator of reliability(and of
course not the whole story).
Dwi and derived data are masked independently, that is why dwi nulls not
fa nulls. DTI and GQI scalars are generated indepenently and have different
"invalid data" constraints, meaning fa,ad,rd,md nulls may not be
qa,gfa,nqa,iso nulls.

Total brain volume isn't readily available from stat sheets due to masking,
and the labelset does not cover 100% of the brain.
Sum of ventricle volume is not reliable due to data masking (any ventricle 
which borders the exterior of the brain is likely to be masked out).
Non Ventricle BrainVolume should be available as the sum of non-ventricle 
structure volumes, or that sum - the sum of nulls.
%}

% do some ugly file read back to avoid the syntatical bleh of changing every
% line of the gotchas text. To the next maintainer, i'm sorry .
% This relies on the first block comment being the gotchas.( %{ -> %} )
% this is nearly function ready as "save first block comment of source" :D !
gotcha_cache=fullfile(fileparts(mfilename('fullpath')),sprintf('%s_gotchas.txt',mfilename()));
if ~exist(gotcha_cache,'file')
    s_cmd=sprintf('sed -e ''1,/^%%{/ d'' -e ''/^%%}/q'' %s.m',mfilename('fullpath'));
    [s,gotchastext]=system(s_cmd);
    if s~=0
        warning('Gotcha text unsucessful.');
    else
        tfid=fopen(gotcha_cache,'w');
        if tfid<1
            tfid=1;
        else
            onCleanup(@() fclose(tfid));
        end
        fprintf(tfid,'%s',gotchastext);
    end
else
    tfid=fopen(gotcha_cache,'r');
    if tfid>2
        onCleanup(@() fclose(tfid));
        gotchastext=fread(tfid,inf,'char=>char',0);
    end
end
if exist('gotchastext','var')
    fprintf('%s',gotchastext);
end
% fomer header info, these headers have been dropped in favor of more
% spreadsheety behavior
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
% this little piece of nasty is used in the sub function sloppy file lookup.
ext_regex='(nhdr|nrrd|nii([.]gz)?)';

start_of_script=tic;
expected_output_subfolder='individual_label_statistics';
if numel(varargin)>0
    error_msg='';
    % using the | instead of || so we can be sloppy with type checking
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
if ~isdeployed &&  exist('iambj','var')
    if exist('iambj','var')
        %% bj test variables:
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
    end
else
    %% Set optional vars to default values if omitted. 
    if (exist(output_dir,'dir') && (~exist('space','var') || ~exist('atlas_id','var')))
        warning('Auto-resolving the "space" and "atlas_identity" is STRONGLY discouraged!');
        %% Guess the space var or atlas_id
        %output_dir='/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/chass_symmetric2/stats/';
        % clean up sloppy multi slashes in path
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
%%
contrasts = strsplit(contrast_list,',');
%output_name=[runno '_' atlas_id '_measured_in_' space '_space'];
%output_stats = [output_dir output_name '_stats.txt'];
output_name=sprintf('%s_%s_measured_in_%s_space_stats.txt',runno,atlas_id,space);
statfile_path = fullfile(output_dir,output_name);
statsheet_gotchas=fullfile(output_dir,sprintf('%s_%s_measured_in_%s_space_stats.txt','gotchas',atlas_id,space));
previous_work=zeros(size(contrasts));
if exist(statfile_path,'file')
    stat_table = readtable(statfile_path,'Delimiter','\t');
    if ~strcmp(stat_table.Properties.VariableNames{1},'ROI')
        % We used to write several lines of header info, but that is replaced
        % with writetable, with no headers.
        stat_table = readtable(statfile_path,'HeaderLines',4,'Delimiter','\t');
    end
    contrast_list2=stat_table.Properties.VariableNames;
else
    contrast_list2={'ROI' 'voxels' 'volume_mm3'};
end

contrasts_to_process=0;
for i_cont=1:length(contrasts)
    contrast = contrasts{i_cont};
    previous_work(i_cont) = ~isempty(find(strcmp([contrast '_mean' ],contrast_list2),1)) ;
    if ~previous_work(i_cont)
        contrast_list2{length(contrast_list2)+1} = [contrast '_mean'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_std'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_min'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_max'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_spread'];
        contrast_list2{length(contrast_list2)+1} = [contrast '_nulls'];
        contrasts_to_process=contrasts_to_process+1;
    end
end

fprintf('Header on output \n>\t%s\n',strjoin(contrast_list2,','));
if contrasts_to_process > 0
    if use_first_contrast_to_mask
        contrast = contrasts{1};
        % contrast_stats=zeros(size(volume_mm3));
        % Does not yet support '_RAS' suffix, etc yet.
        % BLEH Forced file name patterns, how disapointing.
        file_i=fullfile(image_dir,[runno '_' contrast '.nii']); 
        if ~exist(file_i,'file')
            if exist([file_i '.gz'],'file')
                file_i = [file_i '.gz'];
            else
                % didnt find the best cases, now we're going sloppy.
                % Slipping some partial nrrd/nhdr support in there. 
                % Really feels like a job for read_civm_image, except it
                % expects you to know what you're asking for. 
                %regexpdir(rootdir, expstr, recursive)
                file_i=sloppy_file_lookup(image_dir,runno,contrast,ext_regex);
            end 
        end
        fprintf('Loading first contrast, and using it to infer a mask for the first ROI (usually 0): %s\n',file_i);
        try
            [img_struct.img,img_struct.hf]=read_civm_image(file_i,0);
        catch
            warning('load any image via helper unsucessful, falling back to load_niigz.');
            img_struct=load_niigz(file_i);
        end
        dims.img=size(img_struct.img);
        %img_struct.img=img_struct.img(:);
    end
    
    % This is the count of elements in label 0 that are ignored and thus by default assumed to be null for stat purposes.
    null_element_base = 0;
    
    try
        [label_orig.img,label_orig.hf]=read_civm_image(label_file,0);
    catch
        warning('load any image via helper unsucessful, falling back to load_niigz.');
        label_orig=load_niigz(label_file);
        %patching hdr to same place read_civm_image would put it
        label_orig.hf.hdr=label_orig.hdr;
    end
    if ~isfield(label_orig.hf,'hdr')
        voxel_vol=prod(nrrd_vox(label_orig.hf.nhdr));
    else
        voxel_vol=prod(label_orig.hf.hdr.dime.pixdim(2:4));
    end
    dims.label=size(label_orig.img);
    if isfield(dims,'img') && nnz(dims.img-dims.label)
        error('Label to img dimension mis-match! THESE ARE NOT APPROPRIATE LABELS');
    end
    %labelim=label_orig.img(:);1
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
    [~,label_name]=fileparts(label_file);% just pulled for concise feedback
    fprintf('%s\n\tBegin index separation for %d ROIs\n',label_name,numel(ROI));
    start_t=tic;
    % We had volume size here, we could cleverly scale feedback based on
    % roi count and voxels assuming they'll have similar size.
    feedback_interval=25;
    for i_roi=1:numel(ROI)
        if ~mod((i_roi-1),feedback_interval) %&& isdeployed
            fprintf('\tROI %d-%d of %d...\n',i_roi,min(i_roi+feedback_interval-1,numel(ROI)),numel(ROI));
            % elapsed_time = toc(start_t);
            % fprintf('Processing ROI %d of %d. Elapsed time = %f s...\n',ind,numel(ROI),elapsed_time);
            % start_t=tic;
        end
        if ((i_roi==1) && use_first_contrast_to_mask)
            % remove all unlabeled voxels from the label map 
            % we keep this "mask" for later images.
            % --IF-- they are also 0 value in our fist image.
            % WARNING: This assumes the first label found(typically value
            % 0) is "the unlabeled" voxels.
            null_indices=(label_orig.img(:)==ROI(i_roi)) & (img_struct.img(:) == 0);
            null_element_base = nnz(null_indices);
            labelim=label_orig.img(~null_indices(:));
            clear label_orig;
            current_image=img_struct.img(~null_indices);
            clear img_struct;
            ROI_indices{i_roi} = find((labelim==ROI(i_roi)) & (current_image ~= 0));
        elseif ((i_roi==1) && ~use_first_contrast_to_mask)
            labelim=label_orig.img(:);
            clear label_orig;
            ROI_indices{i_roi} = find(labelim==ROI(i_roi));
        else
            ROI_indices{i_roi} = find(labelim==ROI(i_roi));
        end
        % Bad form here where we changed the meaning of "voxels" between
        % the first roi(0) and the rest.
        % Now it always means, the number of voxels labeled like this.
        % Analysis of exterior is always a mistake of process, but we dont
        % want to skip measuring as it could be used as a qa metric.
        voxels(i_roi)= numel(ROI_indices{i_roi}) + (i_roi==1)*null_element_base ;
    end
    clear labelim; % We got everything we needed so can remove from memory
    %voxels = voxels';
    elapsed_time = toc(start_t);
    fprintf('Done index separation for %d ROIs in %s.\nElapsed time = %f s\n',numel(ROI),label_name,elapsed_time);
    
    % Calculate volume in mm^3
    volume_mm3=voxels*voxel_vol;
    if ~exist(statfile_path,'file')
        stat_table = table(ROI,voxels,volume_mm3);
    end
    
    %% measure all things foreach contrast
    for i_cont=1:length(contrasts)
        if ~previous_work(i_cont)
            contrast = contrasts{i_cont};
            if ((i_cont==1) && use_first_contrast_to_mask && exist('current_image','var'))
                % img_struct is already in memory, do not load again (do nothing)
            else
                %% load image
                % TODO: a background load of "the next" image here, 
                % because measuring takes just a little bit of time 
                % ( aproximately load time), sigh *future improvments*.
                % contrast_stats=zeros(size(volume_mm3));
                file_i=[image_dir runno '_' contrast '.nii'];
                if ~exist(file_i,'file')
                    if exist([file_i '.gz'],'file')
                        file_i = [file_i '.gz'];
                    else
                        % didnt find the best cases, now we're going sloppy.
                        % Slipping some partial nrrd/nhdr support in there.
                        % Really feels like a job for read_civm_image, except it
                        % expects you to know what you're asking for.
                        %regexpdir(rootdir, expstr, recursive)
                        file_i=sloppy_file_lookup(image_dir,runno,contrast,ext_regex);
                    end
                end
                fprintf('load image %s\n',file_i);
                try
                    [img_struct.img,img_struct.hf]=read_civm_image(file_i,0);
                catch
                    warning('load any image via helper unsucessful, falling back to load_niigz.');
                    img_struct=load_niigz(file_i);
                end
                dims.img=size(img_struct.img);
                if use_first_contrast_to_mask
                    % remove all unlabeled voxels from the data that were of zero value in the first contrast.
                    % This saves us memory.
                    current_image=img_struct.img(~null_indices);
                else
                    current_image=img_struct.img(:);
                end
                clear img_struct;
            end
            if nnz(dims.img-dims.label)
                error('Label to img dimension mis-match! THESE ARE NOT APPROPRIATE LABELS');
            end
            for i_roi=1:numel(ROI)
                %fprintf('For contrast "%s" (%i/%i), measuring region %i of %i (ROI %i)...\n',contrast,i_cont,length(contrasts),i_roi,numel(ROI),ROI(i_roi));
                if ~mod((i_roi-1),feedback_interval)
                    i_roi_f=min(i_roi+feedback_interval-1,numel(ROI));
                    fprintf('For contrast "%s" (%i/%i), measuring region %i-%i of %i (Value(s) %s)...\n',...
                        contrast,i_cont,length(contrasts),i_roi,i_roi_f,numel(ROI), ...
                        sprintf('%i ',ROI(i_roi:i_roi_f)));
                end
                %regionindex=find(labelim==val1(ind));
                %contrast_stats(ind)=mean(img_struct.img(labelim==ROI(ind)));
                %%Switched to the code below on 27 Feb 2018, to ignore masked
                %%voxels in the ROI
                data_vector=current_image(ROI_indices{i_roi});
                %nulls=numel(data_vector)-nnz(data_vector) + (i_roi==1)*null_element_base ;
                % To be logically consistent (and devoid of qualifiers ) in
                % reading the data, the null_element base was pushed back
                % into the roi it was taken from.
                % nulls=numel(data_vector)-nnz(data_vector);
                nulls=voxels(i_roi)-nnz(data_vector);
                data_vector(data_vector==0)=[];
                if ~isfloat(data_vector) 
                    if i_roi==1
                        warning('non-float, casting all to single precision');
                    end
                    data_vector=single(data_vector);
                end
                contrast_stats.mean(i_roi)=mean(data_vector);
                
                if numel(data_vector)>0
                    contrast_stats.std(i_roi)=std(data_vector,0,1);
                    contrast_stats.min(i_roi)=min(data_vector);
                    contrast_stats.max(i_roi)=max(data_vector);
                else
                    contrast_stats.std(i_roi)=NaN;
                    contrast_stats.min(i_roi)=NaN;
                    contrast_stats.max(i_roi)=NaN;
                end
                try
                catch merr
                    db_inplace(mfilename,'error on stat measure, debug stop now');
                end
                % Spread is the "CoV" calculation we use when checking left
                % vs right, but it'll likly confuse us if we call it CoV
                % here.
                contrast_stats.spread(i_roi)=contrast_stats.std(i_roi)/contrast_stats.mean(i_roi);
                contrast_stats.nulls(i_roi)= nulls;
                % James says maybe we insert code to write out useful
                % histograms here, since we have the relevant data in memory.
            end
            stat_names=fieldnames(contrast_stats);
            for sn=1:numel(stat_names)
                stat_table.([contrast '_' stat_names{sn} ])=contrast_stats.(stat_names{sn})';
            end
            %eval_cmd = ['working_table.' contrast '=contrast_stats;'];
            %eval(eval_cmd);
        end
        clear current_image;
    end
else
    fprintf('No extra work to be done; will add structure info if need be (and lookup table is available), and rewrite to original file.\n');
end
if ~strcmp(stat_table.Properties.VariableNames{2},'structure')
    lookup_used=0;
    %% Process lookup table, if available
    % Implementing lookup table support! 20 February 2019
    if exist('lookup_table_path','var') && exist(lookup_table_path,'file')
        % replicate stat_table incase our try ruins it.
        tmp_table=stat_table;
        try 
            % 20 March 2019:
            % Older lookups are space seperated; the first try will fail on
            % newer tab separated files.  If we were to try the "right"
            % (aka newer) format first, it would still be successful with
            % the space separated file, but not do what we want (RGBA info
            % would be included in the structure name.
            try
                lookup=readtable(lookup_table_path,'Delimiter',' ','ReadVariableNames',false,'Format','%f64%s%d%d%d%d','CommentStyle','#');
            catch
                lookup=readtable(lookup_table_path,'Delimiter','\t','ReadVariableNames',false,'Format','%f64%s%d%d%d%d','CommentStyle','#');
            end
            
            % This code is bona fide because LOOKUPS should/must have the
            % format where first column is ROI number and second is
            % structure/name.  Any columns after this are ignored here.
            lookup_used=1;
            stat_table=outerjoin(stat_table,lookup,'Type','Left','LeftKeys',{'ROI'},'RightKeys',1,...
                'RightVariables',2);
            stat_table=[ stat_table(:,1) stat_table(:,end) stat_table(:,2:(end-1))];
            stat_table.Properties.VariableNames{2}='structure';
            label_msg=sprintf('Structure names successfully added from lookup table:\n\t%s',lookup_table_path);
        catch
        	label_msg=sprintf('Failure on processing lookup table, no structure names will be added. Offending file:\n\t%s',lookup_table_path);
            % little silly here because we may have destroyed the stat_table in our try block
            stat_table=tmp_table;
        end
        clear tmp_table;
    else
        label_msg=['No valid lookup table specified...only ROI number will be reported.'];
    end
    if lookup_used
        disp(label_msg);
    else
        warning(label_msg);
    end
end

%% Write to file
if contrasts_to_process || exist('lookup_used','var')
    try
        writetable(stat_table,statfile_path,'QuoteStrings',true,'Delimiter','\t','WriteVariableNames',true);
    catch merr
        warning(merr.message)
        statfile_path=strrep(statfile_path,'txt','mat');
        [~,n]=fileparts(statfile_path);
        eval(sprintf('%s=final_table;',n));
        warning('Saving table to mat format due to above error. New ouptut: %s. Var will be named same as file.',statfile_path);
        save(statfile_path,n);
    end
end
total_elapsed_time=toc(start_of_script);
if exist(gotcha_cache,'file') && ~exist(statsheet_gotchas,'file')
    [s,sout]=system(sprintf('cp -p %s %s',gotcha_cache,statsheet_gotchas));
    if s~=0 
        warning(sout);
    end
end
fprintf('WORK COMPLETE! Results written to %s.\nTotal processing time: %f s.\n',statfile_path,total_elapsed_time);
end
function the_file=sloppy_file_lookup(the_dir,varargin)
% oh i dont like doing this type of tom foolery guessing filenames, 
% i'm concerned now that i've made this beast it'll escape !
begin=sprintf('.*[._]%s',varargin{1:end-1});
% WARNING if vararin end doesnt have content this second line will need
% adjustment
the_pattern=sprintf('%s[._].*%s$',begin,varargin{end});
the_file=sprintf('MISSING file matching pattern %s\n\tdir: %s',the_pattern,the_dir);
MatchingFiles=regexpdir(the_dir, the_pattern, 0);
if numel(MatchingFiles)>=1
    the_file=MatchingFiles{1};
    if numel(MatchingFiles)>1
        warning('Multiple files would have matched, but we just grabbed the first one.');
    end
end
end
