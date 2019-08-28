function write_individual_stats_exec(runno,label_file,contrast_list,image_dir,output_dir,project_id,species,spec_id,atlas_id,alphabetized,excel_template,excel_range) % (contrast,average_mask,inputs_directory,results_directory,group_1_name,group_2_name,group_1_filenames,group_2_filenames)
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

if ~isdeployed
    genpath('/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/label_stats/20130227_xlwrite/')
end

expected_output_subfolder='individual_label_statistics';
if ~exist('excel_template','var')
    excel_template='/cm/shared/CIVMdata/CIVM_sills_rat_template.xlsx';
end

write_to_excel = 1;

if ~isdeployed
    % Default test variables:
    if ~exist('runno','var')
        runno='S67760';
    end
    
    if ~exist('label_file','var')
        label_file='/glusterspace/SingleSegmentation_17sills02_xmas2015rat_S67760-work/dwi/dwi/dwiMDT_NoNameYet_n1/stats_by_region/labels/pre_rigid_native_space/xmas2015rat/dwi_labels_warp_S67760.nii.gz';
    end
    
    if ~exist('contrast_list','var')
        contrast_list='e1,rd,fa';%adc,dwi,e1,e2,e3,fa,rd';
    end
    
    if ~exist('image_dir','var')
        image_dir='/glusterspace/SingleSegmentation_17sills02_xmas2015rat_S67760-work/dwi/dwi/dwiMDT_NoNameYet_n1/stats_by_region/labels/pre_rigid_native_space/images/';
    end
    
    if ~exist('output_dir','var')
        output_dir='/glusterspace/SingleSegmentation_17sills02_xmas2015rat_S67760-results/connectomics//pre_rigid_native_space//S67760/';
    end
    
   if ~exist('space','var')
       space='rigid';
   end
    
   if ~exist('project_id','var')
       %project_id='17.sills.02';
       project_id = '15rja01';
   end
   
   if ~exist('species','var')
      species = 'Rat'; 
   end
   
   if ~exist('spec_id','var')
      spec_id = '801215-1:1'; 
   end
   
   if ~exist('atlas_id','var')
       atlas_id='xmas2015rat';
   end
    
   if ~exist('alphabetized','var')
        alphabetized = 1;
   end
else

    if ~exist('atlas_id','var')
        if exist('default_atlas_id','var')           
            atlas_id=default_atlas_id;
        else
           atlas_id='chass_symmetric2'; 
        end
    end
    
    if ~exist('alphabetized','var')
        alphabetized = 0;
    end
end


if ~exist('excel_range','var')
    excel_range='E14:K39'
end

structure_name={};

if strfind(atlas_id,'xmas2015rat') || strfind(atlas_id,'ratpnd80avg')
  
alpha_order = [14 17 4 5 22 20 1 16 7 10 15 12 8 11 19 2 21 25 13 26 23 18 6 9 3 24];

alpha_label_names={'Accumbens nucleus' 'Amygdala' 'Anterior Commissure'...		
'Axial Hindbrain' 'Bed Nucleus of the Stria Terminalis' 'Cerebellum' 'Cingulum'...
'Corpus Callosum/Deep Cerebral White Matter' 'Diagonal Domain' 'Diencephalon'...
'Fimbria/Fornix' 'Hippocampal Formation' 'Hypothalamus'...
'Internal Capsule/Cerebral Peduncle/Pyramids' 'Isocortex'...
'Mesencephalon' 'Olfactory Structures' 'Optic Pathways'...
'Pallidum' 'Pineal Gland' 'Pituitary' 'Preoptic Area'...
'Septum' 'Striatum' 'Substantia Nigra' 'Ventricles'};
end
if alphabetized 
    structure_name = alpha_label_names;
else
    [~, alpha_to_numeric_map]=sort(alpha_order);
    structure_name = alpha_label_names(alpha_to_numeric_map);
end
structure_name=structure_name';
contrasts = strsplit(contrast_list,',');

%if write_to_excel
    output_name = [runno '_report.xlsx'];
    output_stats=[output_dir output_name];
%else
%    output_name=[runno '_' atlas_id '_labels_in_' space '_space'];
%    output_stats = [output_dir output_name '_stats_with_stds.txt'];
%end

label_orig=load_untouch_nii(label_file);
voxel_vol=label_orig.hdr.dime.pixdim(2)*label_orig.hdr.dime.pixdim(3)*label_orig.hdr.dime.pixdim(4);
labelim=label_orig.img;

%if (alphabetized)
%    [ROI, numeric_to_alpha_map ]=unique(alpha_order);
%else
    ROI=unique(labelim);
%end

n=length(ROI);
edges = ROI-0.5;
edges = [edges' (max(edges(:))+1)]';
[i_voxels, ~] =  histcounts(labelim,edges);



if alphabetized
    if ~sum(ismember(alpha_order,0)) 
        zero_position = find(ismember(ROI,0));
        if (zero_position(1) ~= 0)
            i_voxels(zero_position) = [];
            ROI(zero_position)=[];
        end
    end
    voxels=i_voxels(alpha_order);
    ROI =alpha_order';
    %ROI_1 = alpha_order;
    %ROI_2 = ROI(numeric_to_alpha_map);
    %ROI_test = sum(ROI_1-ROI_2)
else
    voxels=i_voxels;
end

voxels = voxels';
% Calculate volume in mm^3
volume_mm3=voxels*voxel_vol;

%if exist(output_stats,'file')
%   working_table = readtable(output_stats,'HeaderLines',4,'Delimiter','\t'); % Change 3 to 4 before production!
%else
    if ~isempty(structure_name)
        working_table = table(structure_name,ROI,volume_mm3);
    else
        working_table = table(ROI,voxels,volume_mm3);
    end
%end


previous_work=zeros(size(contrasts));
contrast_list2=working_table.Properties.VariableNames;

for ii=1:length(contrasts)
    contrast = contrasts{ii};
    previous_work(ii) = ~isempty(find(strcmp(contrast,contrast_list2),1));
    if ~previous_work(ii)
        contrast_list2{length(contrast_list2)+1} = contrast;
    end
end




%fprintf('Header on output \n>\t%s\n',strjoin(contrast_list2,',')); % Right place for this?

for ii=1:length(contrasts)
    if ~previous_work(ii)
        contrast = contrasts{ii};
        contrast_string = contrast;
        if strcmp(contrast_string,'e1')
            contrast_string = 'ad';
        end
        
        contrast_strings{ii} = upper(contrast_string);
        
        contrast_stats=zeros(size(volume_mm3));
        contrast_stds=zeros(size(volume_mm3));
       %contrast_tstat=zeros(size(volume_mm3));
        filenii_i=[image_dir runno '_' contrast '.nii']; % Does not yet support '_RAS' suffix, etc yet.
        if ~exist(filenii_i,'file')
            filenii_i = [filenii_i '.gz'];
        end
        fprintf('load nii %s\n',filenii_i);
        imnii_i=load_untouch_nii(filenii_i);
        for ind=1:numel(ROI)
            fprintf('For contrast "%s" (%i/%i), processing region %i of %i (ROI %i)...\n',contrast,ii,length(contrasts),ind,numel(ROI),ROI(ind));
            %regionindex=find(labelim==val1(ind));
            contrast_stats(ind)=mean(imnii_i.img(labelim==ROI(ind)));
            contrast_stds(ind)=std(imnii_i.img(labelim==ROI(ind)));
            %contrast_tstat(ind)=log(contrast_stats(ind)./contrast_stds(ind));
        end
        eval_cmd = ['working_table.mean_' contrast '=contrast_stats;'];
        eval(eval_cmd);
        
        eval_cmd = ['working_table.std_' contrast '=contrast_stds;'];
        eval(eval_cmd);
        
        %eval_cmd = ['working_table.ln_tstat_' contrast '=contrast_tstat;'];
        %eval(eval_cmd);
    end
end

%% Write to file
%headers = working_table.Properties.VariableNames;
%{
final_contrast_list = strjoin(working_table.Properties.VariableNames(2:end),',');
header_info = {final_contrast_list runno atlas_id space};
header_key = {'contrasts' 'runno' 'atlas' 'space'};

fid = fopen(output_stats, 'w');
for LL = 1:length(header_info)
    fprintf(fid, '%s=%s\n', header_key{LL},header_info{LL});
end
fclose (fid);
%}

% Currently not implementing generalized label_names % 13 June 2017
%if strcmp(atlasid,'whs')
%    label_key=['if_using_whs_as_reference_the_label_names_are: ', label_names];
%dlmwrite(output_stats, label_key, 'precision', '%s', 'delimiter', ' ', '-append' ,'roffset', 1);
%else
%label_key=['General label key support not implemented yet.'];
%disp(label_key);
%end

%mystats = table2array(double(working_table));
%mystats= double(working_table{:,:})
%disp(output_stats)

if ~write_to_excel
    %{
fid = fopen(output_stats, 'a');
fprintf(fid, '%s', headers{:,1});
for row=2:length(headers)
    fprintf(fid, '\t%s', headers{:,row});
end
fprintf(fid, '\n');

for c_row=1:length(ROI)

    %fprintf(fid, '%i\t%i', working_table.ROI(c_row),working_table.voxels(c_row));
    if ~isempty(structure_name)
        fprintf(fid, '%s\t%i', working_table.structure_name(c_row),working_table.ROI(c_row));
    else
        fprintf(fid, '%s\t%i', working_table.structure_name(c_row),working_table.ROI(c_row));
    end
    
    for cc=3:length(headers)
        c_contrast = working_table.Properties.VariableNames{cc};
        eval_cmd =  ['working_table.' c_contrast '(c_row)'];
        fprintf(fid, '\t%10.8f',eval(eval_cmd));
    end
    fprintf(fid, '\n');
end

fclose (fid);
%}
else
    cp_cmd = sprintf('cp %s %s', excel_template, output_stats);
    system(cp_cmd);

    [~,c_month] = month(date);
    c_month = upper(c_month);
    c_day_of_month = day(date);
    c_year = year(date);
    
    xlwrite(output_stats,{c_month c_day_of_month, c_year},1,'A6');
    
    if ~exist('project_id','var')
        project_id='';   
    else
       if isempty(strfind(project_id,'.'))
           project_id = [project_id(1:2) '.' project_id(3:(end-2)) '.' project_id((end-1):end)];  
       end 
    end
    xlwrite(output_stats,{project_id},1,'D6');
    
    if ~exist('species','var')
        species='';   
    end
    xlwrite(output_stats,{species},1,'F6');
    
    
    c_user = getenv('USER');
    xlwrite(output_stats,{c_user},1,'A9');
    
    if ~exist('spec_id','var')
        spec_id='';   
    end
    xlwrite(output_stats,{spec_id},1,'D9');
    
    xlwrite(output_stats,{runno},1,'F9');
    
    % Print contrast names
    
    %{ 
    %Implement this later...mostly works, except for superscripts
    contrast_locations = {'F12' 'H12' 'J12' 'L12' 'N12' 'P12' 'R12' 'T12' 'V12' 'X12' 'Z12'};
    
    for cc=1:length(contrasts)
        c_contrast_string = contrast_strings{cc};
        switch c_contrast_string
            case {'ADC', 'AD', 'RD', 'MD', 'E1', 'E2', 'E3'}
                units = 'MM2/s';
            case 'DWI'
                units = 'A.U.';
            otherwise
                units = '';
        end
    
        if ~isempty(units)
            printed_string = sprintf('%s (%s)',c_contrast_string,units);
        else
            printed_string = sprintf('%s',c_contrast_string,units);
        end
   
        xlwrite(output_stats,{printed_string},1,contrast_locations{cc});
    end
    %}
    
    % Format data for printing out to excel
   
   output_cell=table2cell(working_table);
   
   final_cell = output_cell(:,3:end);
   
   %semi_final_cell = output_cell(:,3:end);
   %final_cell=cell(size(semi_final_cell));
   %final_cell(:,1)=cellfun(@(x) sprintf('%3.2f',x),semi_final_cell(:,1),'UniformOutput',false);
   %final_cell(:,2:end)=cellfun(@(x) sprintf('%3.2E',x),semi_final_cell(:,2:end),'UniformOutput',false);
   
   xlwrite(output_stats,final_cell,1,excel_range);
    
   
   

end
end
