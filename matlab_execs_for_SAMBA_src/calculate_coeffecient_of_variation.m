function CoV_array = calculate_coeffecient_of_variation( individual_stat_file,field, delta )
% CoV_triplets = CALCULATE_COEFFECIENT_OF_VARIATION( stat_file, field, delta )
% Calculate CoV between L/R ROIs  (std/mean)
%   Input:
%   stat file - as produced by write_individual_stats,
%     ( tab separated, loadable by matlab's readtable with a header line) 
%   field -     which column we're comparing
%   delta -     the difference constant to map L-R pairs
% CoV_triplets output are 3xN array of roi,cov,mean for each roi found

isf=individual_stat_file;
if exist(isf, 'file')
    % this line fails when we have header lines... like in the old days : (
    master_T = readtable( isf,'ReadVariableNames',1,'HeaderLines',0,'Delimiter','\t');
    % so we'll read the table twice.... once the new way, and once the old
    % way, if the old way has more columns, we'll use that. 
    master_T_o = readtable( isf,'ReadVariableNames',1,'HeaderLines',4,'Delimiter','\t');
    if size(master_T,2)<size(master_T_o,2)
        warning(sprintf('%s\n\t',...
            'OLD data detected!',...
            'This is probably fine,',...
            'just wanted to leave a mess in your console :D !'));
        master_T=master_T_o;
    end
    clear master_T_o;
else
    error('Missing file %s',isf);
end
existing_fields = master_T.Properties.VariableNames;
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
n_ROIs=size(master_T,1);
if ~ismember('ROI',existing_fields)
    warning('ROI not part of table! YOU HOPE ORDERING WAS PRESERVED ON LOAD!');
    pause(3);
    master_T.ROI=1:1:n_ROIs;
end
roi_data=[master_T.ROI,master_T.(c_field)];

%% trim the exterior out
singular_exterior=mod(n_ROIs,2);
% If the the first entry is '0' (hopefully whole-brain exterior)
if ~roi_data(1,1)
    roi_data(roi_data(1,:)==0,:)=[];
    if ~singular_exterior
        % we had a paired exterior
        roi_data(roi_data(1,:)==0+delta,:)=[];
    end
    n_ROIs=size(roi_data,1);
end
clear singular_exterior;
roi_data=sortrows(roi_data,1);
%% guess delta if need be
if ~exist('delta','var')
    delta=roi_data(end,1)-roi_data(end/2,1);
end
%% connect the low/high roi vals via delta
max_roi=max(roi_data(:,1));
% correlated input will be  num lr rois  x  4  
% element 1 is low  roi num 
% element 2 is low  roi val
% element 3 is high roi val
% element 4 is high roi num 
correlated_input=sparse(max_roi,4);
for i_a_rois=1:n_ROIs
    % roi - delta helps us know when a piece of data is found.
    % Mostly for when delta is not n lr rois
    roi_n1=roi_data(i_a_rois,1)-delta;
    roi_L=roi_data(i_a_rois,1);
    roi_H=roi_data(i_a_rois,1)+delta;
    if correlated_input(roi_L,1)==0 ...
        && ( roi_n1<1 || correlated_input(roi_n1,1)==0 )
        correlated_input(roi_L,1)=roi_L;
        correlated_input(roi_L,2)=roi_data(i_a_rois,2);
        correlated_input(roi_L,3)=roi_data(roi_data(:,1)==roi_H,2);
        correlated_input(roi_L,4)=roi_H;
    end
    %{
    % superfluous print per roi, used in debug
    fprintf('.');
    if ~mod(i_a_rois,80)
        fprintf('\n');
    end
    %}
end
%{
% superfluous print per roi finalizer, used in debug
if mod(i_a_rois,80)
    fprintf('\n');
end
%}
correlated_input=full(correlated_input(correlated_input(:,1)~=0,:));
%% calculate our CoV from elements 2 and 3 of the correlated input.
CoV_array=zeros([3,size(correlated_input,1)]);
CoV_array(1,:)=correlated_input(:,1);
% It is important that the second std option be set to 0 to match what Nian did in Excel.
CoV_array(2,:)=std(correlated_input(:,2:3),0,2)./mean(correlated_input(:,2:3),2);
CoV_array(3,:)=mean(correlated_input(:,2:3),2);
end

