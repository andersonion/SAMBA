function write_individual_stats_exec(runno,label_file,contrast_list,image_dir,output_dir,space,atlas_id) % (contrast,average_mask,inputs_directory,results_directory,group_1_name,group_2_name,group_1_filenames,group_2_filenames)
% New inputs:
% runno: run number of interest
% label_file: Full path to labels
% contrast_list: comma-delimited (no spaces) string of contrasts
% image_dir: Directory containing all the contrast images
% output_dir
% space: 'native','rigid','affine','mdt', or atlas'; used in header
% atlas_id: used in header; may be used for pulling label names in the future.
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
  
expected_output_subfolder='individual_label_statistics';

if ~isdeployed
    % Default test variables:
    if ~exist('runno','var')
        runno='N51406';
    end
    
    if ~exist('label_file','var')
        label_file=['/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/chass_symmetric2/fa_labels_warp_' runno '.nii.gz'];
    end
    
    if ~exist('contrast_list','var')
        contrast_list='adc,dwi,e1,e2,e3,fa,rd';
    end
    
    if ~exist('image_dir','var')
        image_dir='/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/images/';
    end
    
    if ~exist('output_dir','var')
        output_dir='/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/chass_symmetric2/stats/';
    end
    
   if ~exist('space','var')
       space='rigid';
   end
    
   if ~exist('atlas_id','var')
       atlas_id='chass_symmetric2';
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
           atlas_id='chass_symmetric2'; 
        end
    end
end

% Need label_names! label_names=['Exterior',	'Cerebral_cortex	', 'Brainstem	', 'Cerebellum	   '	]; %et cetera, et cetera, et cetera

contrasts = strsplit(contrast_list,',');

output_name=[runno '_' atlas_id '_labels_in_' space '_space'];
output_stats = [output_dir output_name '_stats.txt'];


label_orig=load_untouch_nii(label_file);
voxel_vol=label_orig.hdr.dime.pixdim(2)*label_orig.hdr.dime.pixdim(3)*label_orig.hdr.dime.pixdim(4);
labelim=label_orig.img;
ROI=unique(labelim);
n=length(ROI);
edges = ROI-0.5;
edges = [edges' (max(edges(:))+1)]';
[voxels, ~] =  histcounts(labelim,edges);
voxels = voxels';
% Calculate volume in mm^3
volume_mm3=voxels*voxel_vol;

if exist(output_stats,'file')
   working_table = readtable(output_stats,'HeaderLines',4,'Delimiter','\t'); % Change 3 to 4 before production!
else
   working_table = table(ROI,voxels,volume_mm3);
end


previous_work=zeros(size(contrasts));
contrast_list2=working_table.Properties.VariableNames;

for ii=1:length(contrasts)
    contrast = contrasts{ii};
    previous_work(ii) = ~isempty(find(strcmp(contrast,contrast_list2),1));
    if ~previous_work(ii)
        contrast_list2{length(contrast_list2)+1} = contrast;
    end
end




fprintf('Header on output \n>\t%s\n',strjoin(contrast_list2,',')); % Right place for this?

for ii=1:length(contrasts)
    if ~previous_work(ii)
        contrast = contrasts{ii};
        contrast_stats=zeros(size(volume_mm3));
        filenii_i=[image_dir runno '_' contrast '.nii']; % Does not yet support '_RAS' suffix, etc yet.
        if ~exist(filenii_i,'file')
            filenii_i = [filenii_i '.gz'];
        end
        fprintf('load nii %s\n',filenii_i);
        imnii_i=load_untouch_nii(filenii_i);
        for ind=1:numel(ROI)
            fprintf('For contrast "%s" (%i/%i), processing region %i of %i (ROI %i)...\n',contrast,ii,length(contrasts),ind,numel(ROI),ROI(ind));
            %regionindex=find(labelim==val1(ind));          
            %contrast_stats(ind)=mean(imnii_i.img(labelim==ROI(ind)));
            %%Switched to the code below on 27 Feb 2018, to ignore masked
            %%voxels in the ROI
            data_vector=imnii_i.img(labelim==ROI(ind));
            contrast_stats(ind)=mean(data_vector(data_vector~=0));
        end
        eval_cmd = ['working_table.' contrast '=contrast_stats;'];
        eval(eval_cmd);
    end
end

%% Write to file
headers = working_table.Properties.VariableNames;
final_contrast_list = strjoin(working_table.Properties.VariableNames(2:end),',');
header_info = {final_contrast_list runno atlas_id space};
header_key = {'contrasts' 'runno' 'atlas' 'space'};

fid = fopen(output_stats, 'w');
for LL = 1:length(header_info)
    fprintf(fid, '%s=%s\n', header_key{LL},header_info{LL});
end
fclose (fid);


% Currently not implementing generalized label_names % 13 June 2017
%if strcmp(atlasid,'whs')
%    label_key=['if_using_whs_as_reference_the_label_names_are: ', label_names];
%dlmwrite(output_stats, label_key, 'precision', '%s', 'delimiter', ' ', '-append' ,'roffset', 1);
%else
label_key=['General label key support not implemented yet.'];
disp(label_key);
%end

%mystats = table2array(double(working_table));
%mystats= double(working_table{:,:})
fid = fopen(output_stats, 'a');
fprintf(fid, '%s', headers{:,1});
for row=2:length(headers)
    fprintf(fid, '\t%s', headers{:,row});
end
fprintf(fid, '\n');

for c_row=1:length(ROI)

    fprintf(fid, '%i\t%i', working_table.ROI(c_row),working_table.voxels(c_row));
    for cc=3:length(headers)
        c_contrast = working_table.Properties.VariableNames{cc};
        eval_cmd =  ['working_table.' c_contrast '(c_row)'];
        fprintf(fid, '\t%10.8f',eval(eval_cmd));
    end
    fprintf(fid, '\n');
end

fclose (fid);

end
