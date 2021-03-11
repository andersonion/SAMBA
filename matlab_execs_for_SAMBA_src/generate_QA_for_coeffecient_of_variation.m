function [report_file,table_path]=generate_QA_for_coeffecient_of_variation(...
    runno_or_id, stat_files, string_of_contrasts, atlas_label_prefix, delta)
% [report_file,table_path]=generate_QA_for_coeffecient_of_variation( ...
%               img_ident, stat_file, contrast_list, atlas_label_prefix, delta)
% Generates L<->R CoV for each label and marks good,concerning,and bad values. 
% 
% Runs on a single stat file.
% Saves CoV lookuptables by color for slicer based on violation of the 5% 
% expected variation.
%  (May switch lookup format to itk-snap in the future so that slicer or 
%   itk snap could be used to spot check concerning values.)
% Generates graph for each requested check(volume_mm3,dwi,etc), and 
% concatenates them into a pdf report.
%
% -- Inputs--
% img_ident: identity of the img group, typically run number,
%            could be anything.
% stat_file: path to the stats file, routinely  ...measured_in_native_space.txt
% contrast_list: comma-delimited (NO SPACES) string of contrasts,
%        (columns in your stat sheet)
% atlas_label_prefix: where to look for a sort order/name list. 
%         Expects a file atlas_label_prefix_volume_sort.txt and/or
%         atlas_label_prefix_lookup.txt
% delta:  constant offset to connect pair's of labels. 
%         A way to connect left and right. 
%
% -- Outputs --
% report_file:  path of saved pdf file
% table_path:   path to saved matlab table(as tab csv) with all our cov and
%               other info in it.


% do we delete our component pdfs when we're done.
cleanup=1;
% Max of how many red/yellow flags we want to annotate
max_annotated_violations = 12; 

% "quality" threholds
% In the future, want to make thresholds dynamic, i.e. account for
% quality (or lack thereof) in input labels and/or label volume
red_thresh=0.1;
yellow_thresh=0.05;
red_RGB=[255 0 0];
yellow_RGB=[255 255 0];
green_RGB=[0 255 0];
% Generate A,B,C,D,E...  used in plotting legend 
alphas={'A':'Z'};
alphas{:}(15)=[]; % Remove 'o'
alphas{:}(9)=[]; % Remove 'i'
graph_label_fontpt=12;
x_axis_fontpt=12;
y_axis_fontpt=x_axis_fontpt*.8;


if ~exist('string_of_contrasts','var')
    string_of_contrasts='volume_mm3,dwi,fa';
end
if ~exist('atlas_label_prefix','var')
    %atlas_label_prefix='/cm/shared/CIVMdata/atlas/chass_symmetric3_RAS/chass_symmetric3_RAS_labels';
    %atlas_label_prefix='/cm/shared/CIVMdata/atlas/xmas2015rat_symmetric_cropped/labels_xmas2015rat_symmetric_cropped/xmas2015rat_symmetric_cropped_20190118/xmas2015rat_symmetric_cropped_20190118_labels';
    error('Need our input variables!');
end
volume_order_file=[atlas_label_prefix '_volume_sort.txt'];
%volume_order_file='/cm/shared/CIVMdata/atlas/xmas2015rat_symmetric_cropped/labels_xmas2015rat_symmetric_cropped/xmas2015rat_symmetric_cropped_20190118/xmas2015rat_symmetric_cropped_xmas2015rat_symmetric_cropped_20190118_labels_volume_sort.txt';
%volume_order_file='DISABLED';
atlas_lookup_table=[atlas_label_prefix '_lookup.txt'];

if ~exist('delta','var')
    delta=1000;
elseif ischar(delta)
    delta=str2num(delta);
end
sort_col='ROI';
if exist(volume_order_file,'file')
    order_T=readtable(volume_order_file,'ReadVariableNames',1,'HeaderLines',0,'Delimiter','\t');
    % logical index for order_T header of col named *sort_order*
    log_idx=~cellfun(@isempty,strfind(order_T.Properties.VariableNames,'sort_order'));
    % index of just that col
    idx=find(log_idx);
    sort_col=order_T.Properties.VariableNames{idx};
    % if our sort column is exactly sort_order, expand it to specify who's
    % sort it is.
    if strcmp(sort_col,'sort_order')
        [~,vo_nam]=fileparts(atlas_label_prefix);
        tmp=regexpi(vo_nam,'^(.*)(_labels|quagmire|mess).*$','tokens');
        if ~isempty(tmp)
            vo_nam=tmp{1}{1};
        end
        sort_col_out=sprintf('%s_volume_%s',sort_col,vo_nam);
        order_T.Properties.VariableNames{idx}=sort_col_out;sort_col=sort_col_out;
        fprintf('Sorting column had identity added, it is now: %s\n',sort_col);
    else
        fprintf('Sorting column(%s) appears to have identity, will not expand\n',sort_col);
    end
    order_T=lowercase_table(order_T,'ROI|(^R|G|B|A$)|(sort_order.*)');
end

%sorted_ROIs=order_T.ROI;
if ~iscell(stat_files)
    files={stat_files};
else
    files=stat_files;
end
[out_dir,~,~]=fileparts(files{1});
out_qa_lookups=fullfile(out_dir,'qa_lookups');
out_dir=fullfile(out_dir,'reports');
out_contrast_string=strrep(string_of_contrasts,',','_');
rep_prefix='Graph_summary';
tab_prefix='raw_data';
dat_prefix='figure_source';
if ~exist(out_dir,'dir')
    mkdir(out_dir);
end
if ~exist(out_qa_lookups,'dir')
    mkdir(out_qa_lookups);
end
report_file = fullfile(out_dir,sprintf('%s_%s_CoVs_%s.pdf',rep_prefix, runno_or_id, out_contrast_string));
table_path= fullfile(out_dir,sprintf('%s_%s_CoVs_%s.txt',tab_prefix, runno_or_id, out_contrast_string));
out_data = fullfile(out_dir,sprintf('%s_%s_CoVs_%s.mat',dat_prefix, runno_or_id, out_contrast_string));
if exist(report_file,'file') ...
        && exist(table_path,'file') ...
        && exist(out_data,'file')
    fprintf('Previously completed %s\n',runno_or_id);
    return;
end
    
%{
% Commented out because the code doesnt actually support cell input
if ~iscell(runno_or_id)
    names={runno_or_id};%{'xmas2015rat_symmetric_cropped'}
else
    names=runno_or_id;
end
%}
% if we have structure, we dont need atlas_lookup_T.
try
    atlas_lookup_T=readtable(atlas_lookup_table,'ReadVariableNames', false,'HeaderLines',0,'Delimiter',' ' ...
        ,'Format','%d64 %s %d %d %d %d %s','CommentStyle','#');
catch merr
    warning(merr.message);
    atlas_lookup_T=readtable(atlas_lookup_table,'ReadVariableNames', true,'Delimiter','\t');
end
atlas_lookup_T=lowercase_table(atlas_lookup_T,'ROI');
% atlas_lookup_T.Properties.VariableNames={'ROI' 'Structure' 'R' 'G' 'B' 'A' 'Comments'};
%atlas_lookup_T.Properties.VariableNames={'ROI' 'structure' 'R' 'G' 'B' 'A' 'Comments'};
atlas_lookup_T.Properties.VariableNames{1}='ROI';
atlas_lookup_T.Properties.VariableNames{2}='structure';
atlas_lookup_T.Properties.VariableNames{3}='R';
atlas_lookup_T.Properties.VariableNames{4}='G';
atlas_lookup_T.Properties.VariableNames{5}='B';
atlas_lookup_T.Properties.VariableNames{6}='A';

% Build a proper sorted master_T to save in the data file
% taking advantage that the first column should be volume 
master_CoV_T=table;
contrasts=strsplit(string_of_contrasts,','); 
out_pdf=cell(size(contrasts));
% for FF=1:numel(files)
% stats=files{FF};
FF=1;
stats=files{FF};
[out_dir,stat_file_name,s_ext]=fileparts(files{FF});
stat_file_name=sprintf('%s%s',stat_file_name,s_ext);
tempdir=fullfile(out_dir,'.qa_work');
if ~exist(tempdir,'dir')
    mkdir(tempdir);
end 
for CC=1:numel(contrasts)
    field=contrasts{CC};
    field_out_name=[lower(field) '_CoV'];
    out_pdf{CC}=[tempdir '/QA_' runno_or_id '_CoV_' field '.pdf'];
    if exist(out_pdf{CC},'file')
        fprintf('%s:%s - %s done\n',runno_or_id,field,out_pdf{CC});
        continue;
    end
    clear CoV_array;
    try
    [ CoV_array,stats ] = calculate_coeffecient_of_variation( stats,field,delta);
    catch
    end
    % due to the nature of this code its okay if we dont have some
    if ~exist('CoV_array','var') || numel(CoV_array)==0
        [~,fn]=fileparts(files{FF});
        warning('%s must be missing from file %s, no CoV returned',field,fn);
        contrasts{CC}=[];
        if cleanup
            warning('Forcing cleanup off due to missing a requested contrast');
            cleanup=0;
        end
        continue;
    end
    CoV_T=table(CoV_array(1,:)',CoV_array(2,:)',CoV_array(3,:)','VariableNames',{'ROI' field_out_name field});
    if ~isempty(regexpi(field,'(vol(ume)?(_?)(mm3)?)|(vox(el)?'))
        % TO SPLIT THE DIFFERENCE of different data handling, the third
        % column(the average) is multipled by 2 for volume measures, 
        % because they're averaged in the function, which is more often
        % correct.
        CoV_T{:,3}=CoV_T{:,3}*2;
    end
    
    if exist(volume_order_file,'file')
        full_T=outerjoin(order_T,CoV_T,'Keys','ROI','Type','left','MergeKeys',true,'LeftVariables',{'ROI','structure',sort_col});
    else
        full_T=outerjoin(atlas_lookup_T,CoV_T,'Keys','ROI','Type','left','MergeKeys',true);
    end
    % if full_T doesnt have volume, but master_CoV_T does, Add it.
    if ~any(strcmp('volume_mm3',full_T.Properties.VariableNames)) ...
            && any(strcmp('volume_mm3',master_CoV_T.Properties.VariableNames))
        full_T=outerjoin( full_T,master_CoV_T,'Keys','ROI','Type','left','MergeKeys',true,'RightVariables',{ 'volume_mm3'});
    end
    if isempty(master_CoV_T)
        master_CoV_T=full_T;
    else
        master_CoV_T=outerjoin(master_CoV_T,full_T,'Keys','ROI','Type','left','MergeKeys',true,'RightVariables',{field_out_name,field});
    end
    full_T=sortrows(full_T,sort_col);
    
    %% Build lookup table for visual QA with green/yellow/red motif
    % In the future, want to make thresholds dynamic, i.e. account for
    % quality (or lack thereof) in input labels and/or label volume
    % I think this replicates the red rois with the yellows.
    % Which is probably cleaned up by table operations forcing unique
    % later.
    red_ROIs=   full_T.ROI(find(full_T.(field_out_name)>=red_thresh));
    yellow_ROIs=full_T.ROI(find(full_T.(field_out_name)>=yellow_thresh));
    green_ROIs= full_T.ROI(find(full_T.(field_out_name)<yellow_thresh));
    
    % We might want to change this to be bright red/yellow for volume
    % outliers and medium red/yellow for other contrast outliers
    % This generates a random color scale value from 0.75-1 to adjust the
    % rgb value by so roi's are mildly shaded
    red_rndm=   rand(size(red_ROIs))*0.25+0.75;
    yellow_rndm=rand(size(yellow_ROIs))*0.25+0.75;
    green_rndm= rand(size(green_ROIs))*0.25+0.75;
    
    reds=   floor([red_ROIs';   (red_rndm*red_RGB)';      255*ones(size(red_ROIs   ))']');
    yellows=floor([yellow_ROIs';(yellow_rndm*yellow_RGB)';255*ones(size(yellow_ROIs))']');
    greens= floor([green_ROIs'; (green_rndm*green_RGB)';   80*ones(size(green_ROIs  ))']');
    RGB_d=[reds;yellows;greens];
    RGB_T=table(RGB_d(:,1),RGB_d(:,2),RGB_d(:,3),RGB_d(:,4),RGB_d(:,5),repmat('#',[1 size(RGB_d,1)])','VariableNames',{'ROI' 'R' 'G' 'B' 'A' 'Comment_break'});
    full_T_fields={field_out_name};
    %  if any(strfind('sort_order',full_T.Properties.VariableNames))
    if exist(volume_order_file,'file')
        full_T_fields=[full_T_fields sort_col];
    end
    lookup_T_left=join(RGB_T,full_T,'Keys','ROI','RightVariables', full_T_fields);
    lookup_T_right=lookup_T_left;
    lookup_T_right.ROI=lookup_T_right.ROI+delta;
    lookup_T=union(lookup_T_left,lookup_T_right);
    
    %%% QA_lookup_T=outerjoin(atlas_lookup_T,lookup_T,'Key','ROI','LeftVariables',{'ROI' 'Structure'},'MergeKeys',true);
    %QA_lookup_T=outerjoin(atlas_lookup_T,lookup_T,'Key','ROI','LeftVariables',{'ROI' 'structure'},'MergeKeys',true);
    QA_lookup_T=outerjoin(atlas_lookup_T,lookup_T,... 'Type','Left',...
        'LeftKeys',{'ROI' },...
        'RightKeys',1,...
        'LeftVariables',{'ROI','structure'},...
        'MergeKeys',true);
    QA_lookup_path=fullfile(out_qa_lookups,regexprep(stat_file_name,'_(labels|measured)_.*txt',...
        ['_labels_lookup_outliers_in_CoV_of_' field '.txt']));
    %writetable(QA_lookup_T,QA_lookup_path,'Delimiter',' ')
    if ~exist(QA_lookup_path,'file')
        % had som errant spaces hiding in structure name,
        % this cleared those out.
        % they should be squashed at the source!
        QA_lookup_T.structure=regexprep(QA_lookup_T.structure,' ','_');
        writetable(QA_lookup_T,QA_lookup_path,'Delimiter','\t','WriteVariableNames',0);
    else
        warning('Existing qa lookup, NOT RE-SAVING! (%s)',QA_lookup_path);
    end
    %% Create Plots
    % Still some errors with this.
    plot_option='log_volume';
    %plot_option='sorted_by_volume'
    if strcmp(plot_option,'log_volume') ...
            && isempty(cell2mat(regexpi(full_T.Properties.VariableNames,'^volume_mm3$')))
        plot_option='OTHER';
    end
    switch plot_option
        case 'sorted_by_volume'
            %plot(full_T.sort_order,full_T.([contrast '_CoV']),'o','LineWidth',1); \
            x_axis=full_T.sort_order;
            y_axis=full_T.(field_out_name);
            min_range=min(x_axis(:));
            max_range=max(x_axis(:));
            rng=round(max_range-min_range)+1;
            step=1;
        case 'log_volume'
            %plot(CoV_array(1,:),CoV_array(2,:),'o','LineWidth',1);
            x_axis= log10(full_T.volume_mm3);
            y_axis=full_T.(field_out_name);
            min_range=floor((min(x_axis(:)))*2)/2;
            max_range=ceil(max(x_axis(:))*2)/2;
            rng=floor((max_range-min_range)*2)+1;
            step=0.5;
        otherwise
            x_axis=CoV_array(1,:);
            y_axis=CoV_array(2,:);
            min_range=min(x_axis(:));
            max_range=max(x_axis(:));
            rng=round(max_range-min_range)+1;
            step=1;
    end
    
    %% Find indicies of structures violating red_threshold
    % and order them by magnitude(high->low)
    red_flags=find(y_axis(:)>=red_thresh);
    if ~exist('ILikeVerbosePrograming','var')
        % mat suggested code
        [sorted_flags,sf_ind]=sort(y_axis(red_flags),1,'descend');
    else
        % initial code
        %red_flags=[];
        %red_flags=find(full_T.([contrast '_CoV'])>=0.1);
        %rf_vals=full_T.([contrast '_CoV'])(red_flags)';%CoV_array(2,red_flags);
        rf_vals=y_axis(red_flags)';%CoV_array(2,red_flags);
        [sorted_flags,sf_ind]=sort(rf_vals,2,'descend');
    end
    red_flags=red_flags(sf_ind);
    
    % reduce the reg_flags to the max limit
    if numel(red_flags)>max_annotated_violations
        red_flags((max_annotated_violations+1):end)=[];
    end
    %% setup figure bits
    % issues in older matlab causes this to fail.
    space_for_legend = 0.1875*numel(red_flags)+1*(numel(red_flags)>0);
    try
        close(CC);
    catch
    end
    c_fig(CC)=figure(CC);
    hold on;
    set(gca,'FontName','Ariel','FontSize',x_axis_fontpt,'FontWeight','Bold')
    try
        % This fails on older matlabs, gonna see if we can just skip
        % through
        c_fig(CC).PaperPositionMode='auto';
        c_fig(CC).Units='Inches';
        % we might want to change this, and set pos_vec(2) to:
        %    screen height - fig height.
        pos_vec=[1 1 8 (2.5+space_for_legend)];
        c_fig(CC).Position=pos_vec;
        c_fig(CC).Color=[1 1 1];
    catch merr
        warning(merr.message);
    end
    plot(x_axis,y_axis,'o','LineWidth',1);
    %% set axes labels
    switch plot_option
        case 'sorted_by_volume'
             [~,n]=fileparts(volume_order_file);
            xlabel(strrep(['ROI rank from ' n],'_','\_'));
        case 'log_volume'
            xlabel('log_1_0(vol mm^3)');
        otherwise
            xlabel('ROI');
    end
    % have to escape _ in labels else they get subscripted.
    if ~strcmp(field,'volume_mm3')
        ylabel(strrep([field ' CoV'],'_','\_'))
    else
        ylabel('vol mm^3 CoV');
    end
    xlim([min_range max_range]);
    y_max=0.25;
    ylim(1*[0 y_max])
    %% plot threshold lines
    plot(min_range:step:max_range,ones([rng 1])*0.05,'--','Color', [0.9290 0.6940 0.1250], 'LineWidth',2)
    plot(min_range:step:max_range,ones([rng 1])*0.1,'--r','LineWidth',1.5)
    %% create legend text lines
    legendary=struct; % structure or cell array?
    % using an array of structures so that we stay sorted.
    for rr=1:numel(red_flags)
        flag_ind=red_flags(rr);
        letter=alphas{:}(rr);
        scalerv=2;
        if strcmp(plot_option,'log_volume')
            scalerv=0.02;end
        if strcmp(plot_option,'sorted_by_volume')||strcmp(plot_option,'log_volume')
            text(x_axis(flag_ind)+scalerv,  min(sorted_flags(rr)*1.05,y_max),letter,...
                'FontName','Ariel','FontSize',graph_label_fontpt,'FontWeight','Bold')
            % ar = annotation('arrow');
            % c = ar.Color;
            % ar.Color = 'red';
            % ar.Position=[ (x_axis(flag_ind)) sorted_flags(rr)*1.05 0.2 0.2];
        else
            text(CoV_array(1,flag_ind)-2,min(CoV_array(2,flag_ind)*1.2,y_max),letter,...
                'FontName','Ariel','FontSize',graph_label_fontpt,'FontWeight','Bold');
        end
        if strcmp(plot_option,'sorted_by_volume')||strcmp(plot_option,'log_volume')
            legendary(rr).string=sprintf('%s:%0.1f%% - (ROI %3i) %s',letter,100*sorted_flags(rr),full_T.ROI(flag_ind), full_T.structure{flag_ind});
        else
            legendary(rr).string=sprintf('%s:%0.1f%% - (ROI %3i)',letter,100*sorted_flags(rr),full_T.ROI(flag_ind));% missing structure in this case?;
        end
        legendary(rr).string=strrep(legendary(rr).string,'_','\_');
        if numel(legendary(rr).string)>85
            legendary(rr).string=legendary(rr).string(1:85);
        end
    end
    %% set up legend
    if isfield(legendary,'string')
        for LL = 1: numel(legendary)
            try
                % Modern matlab
                dummyh(LL) = line(nan, nan, 'Linestyle', 'none', 'Marker', 'none', 'Color', 'none');
            catch merr
                % older matlab
                warning(merr.message);
                dummyh(LL) = line(nan, nan, 'Linestyle', 'none', 'Marker', 'none');
            end
        end
        leg = legend(dummyh(:),legendary(:).string,'Location','SouthOutside');
        leg.Units='inches';
    end
    hold off
    %print -depsc2 correlation.eps;
    %export_fig(['/civmnas4/rja20/BJs_march_test_' contrast '_CoVs.pdf'],'-pdf','-nofontswap','-painters','-nocrop', c_fig(CC))
    export_fig(out_pdf{CC},'-pdf','-painters','-nocrop', c_fig(CC))
end
if exist(report_file,'file')
    delete(report_file);
end
% trim missing contrasts
generated_pdf_bool=~cellfun(@isempty,contrasts);
append_pdfs(report_file ,out_pdf{generated_pdf_bool});
% Selective save will be far better behavior.
vars=strsplit('runno_or_id out_contrast_string master_CoV_T c_fig stat_files plot_option out_data report_file table_path' );
writetable(master_CoV_T,table_path,'Delimiter','\t','WriteVariableNames',1);
try
    if ~exist(out_data,'file')
        save(out_data,vars{:});
    else
        save(out_data,vars{:},'-append');
    end
catch merr
    warning(merr.message);
    warning('Couldn''t save figure source materials for update (see above)');
end
% Cleanup intermediary figures
if cleanup && exist(report_file,'file')
    for cc=1:numel(contrasts)
        %cmd = ['rm ' out_pdf{cc}];
        %system(cmd);
        delete(out_pdf{cc});
    end
    [s,sout]=system(sprintf('rmdir %s',tempdir));
else
    if cleanup
        warning('Error creating:%s\nNot cleaning up component pdfs. Directory of goodies to examin %s',report_file,out_dir);
    end
end
close all;
end
function T=lowercase_table(T,untouch_pat)
    for cn=1:numel(T.Properties.VariableNames)
        if isempty(regexpi(T.Properties.VariableNames{cn},untouch_pat))
             T.Properties.VariableNames{cn}= lower(T.Properties.VariableNames{cn});
        end
    end
end
