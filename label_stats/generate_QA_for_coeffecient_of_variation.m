function [out_file]=proto_wrapper_script_for_calculate_coeffecient_of_variation(runno_or_id,stats_files,string_of_contrasts,atlas_label_prefix,delta)
cleanup=1;

if ~exist('runno_or_id','var')
    %runno_or_id='N57009';
    runno_or_id='S66971';
end
if ~exist('stats_files','var')
    %stats_files='/civmnas4/rja20/N57009_chass_symmetric3_RAS_labels_in_rigid_space_stats.txt';
    stats_files='/civmnas4/rja20/SingleSegmentation_15gaj36_xmas2015rat_symmetric_proto_cropped_S66971-work/dwi/fa/faMDT_NoNameYet_n1/stats_by_region/labels/pre_rigid_native_space/xmas2015rat_symmetric_cropped_20190118/stats/individual_label_statistics/S66971_xmas2015rat_symmetric_cropped_20190118_labels_in_native_space_stats.txt';
    
end
if ~exist('string_of_contrasts','var')
    string_of_contrasts='volume_mm3,dwi,fa';
end

if ~exist('atlas_label_prefix','var')
    %atlas_label_prefix='/cm/shared/CIVMdata/atlas/chass_symmetric3_RAS/chass_symmetric3_RAS_labels';
    atlas_label_prefix='/cm/shared/CIVMdata/atlas/xmas2015rat_symmetric_cropped/labels_xmas2015rat_symmetric_cropped/xmas2015rat_symmetric_cropped_20190118/xmas2015rat_symmetric_cropped_20190118_labels';
end
%volume_order_file=[atlas_label_prefix '_volume_sort.txt'];
volume_order_file='/cm/shared/CIVMdata/atlas/xmas2015rat_symmetric_cropped/labels_xmas2015rat_symmetric_cropped/xmas2015rat_symmetric_cropped_20190118/xmas2015rat_symmetric_cropped_xmas2015rat_symmetric_cropped_20190118_labels_volume_sort.txt';
atlas_lookup_table=[atlas_label_prefix '_lookup.txt'];

if ~exist('delta','var')
    delta=1000;
end


if exist(volume_order_file,'file')
    order_T=readtable(volume_order_file,'ReadVariableNames',1,'HeaderLines',0,'Delimiter','\t');
end

%sorted_ROIs=order_T.ROI;
if ~iscell(stats_files)
    files={stats_files};
    [outdir,~,~]=fileparts(files{1});
else
    files=stats_files;
    [outdir,~,~]=fileparts(files);
end

if ~iscell(runno_or_id)
    names={runno_or_id};%{'xmas2015rat_symmetric_cropped'}
else
    names=runno_or_id;
end


contrasts=strsplit(string_of_contrasts,','); %{'volume_mm3' 'adc' 'dwi' 'e1' 'e2' 'e3' 'fa' 'rd' 'b0'}
for CC=1:numel(contrasts)
    contrast=contrasts{CC};
    
    % Moved to later in loop
    %{
    c_fig(CC)=figure(CC);
    c_fig(CC).Units='Inches';
    c_fig(CC).Position=[1 CC*2 16 4]
    %}
    
    % for FF=1:numel(files)
    % file=files{FF};
    file=files{1};
    field=contrast;
    [ CoV_array ] = calculate_coeffecient_of_variation( file,field,delta);
    CoV_T=table(CoV_array(1,:)',CoV_array(2,:)','VariableNames',{'ROI' [contrast '_CoV']});
    
    if exist(volume_order_file,'file')
        full_T=sortrows(outerjoin(order_T,CoV_T,'Keys','ROI','Type','left','MergeKeys',true),'sort_order');
    else
        full_T=CoV_T;
    end
    %CoV_array(1,(sorted_ROIs==CoV_array(1,:)'));
    
    % Build lookup table for visual QA with green/yellow/red motif
    % In the future, want to make thresholds dynamic, i.e. account for
    % quality (or lack thereof) in input labels and/or label volume
    
    red_thresh=0.1;
    red_RGB=[255 0 0];
    
    yellow_thresh=0.05;
    yellow_RGB=[255 255 0];
    
    green_RGB=[0 255 0];
    
    red_ROIs=full_T.ROI(find(full_T.([contrast '_CoV'])>=red_thresh));
    yellow_ROIs=full_T.ROI(find(full_T.([contrast '_CoV'])>=yellow_thresh));
    green_ROIs=full_T.ROI(find(full_T.([contrast '_CoV'])<yellow_thresh));
    
    % We might want to change this to be bright red/yellow for volume
    % outliers and medium red/yellow for other contrast outliers
    red_rndm=rand(size(red_ROIs))*0.25+0.75;
    yellow_rndm=rand(size(yellow_ROIs))*0.25+0.75;
    green_rndm=rand(size(green_ROIs))*0.25+0.75;
    
    reds=floor([red_ROIs';(red_rndm*red_RGB)';255*ones(size(red_ROIs))']');
    yellows=floor([yellow_ROIs';(yellow_rndm*yellow_RGB)';255*ones(size(yellow_ROIs))']');
    greens=floor([green_ROIs';(green_rndm*green_RGB)';80*ones(size(green_ROIs))']');
    RGB_d=[reds;yellows;greens];
    RGB_T=table(RGB_d(:,1),RGB_d(:,2),RGB_d(:,3),RGB_d(:,4),RGB_d(:,5),repmat('#',[1 size(RGB_d,1)])','VariableNames',{'ROI' 'R' 'G' 'B' 'A' 'Comment_break'});
    
    lookup_T_left=join(RGB_T,full_T,'Keys','ROI','RightVariables', {[contrast '_CoV']});
    lookup_T_right=lookup_T_left;
    lookup_T_right.ROI=lookup_T_right.ROI+delta;
    lookup_T=union(lookup_T_left,lookup_T_right);
    
    atlas_lookup_T=readtable(atlas_lookup_table,'ReadVariableNames', false,'HeaderLines',0,'Delimiter',' ' ...
        ,'Format','%d64 %s %d %d %d %d %s','CommentStyle','#');
    % atlas_lookup_T.Properties.VariableNames={'ROI' 'Structure' 'R' 'G' 'B' 'A' 'Comments'};
    atlas_lookup_T.Properties.VariableNames={'ROI' 'structure' 'R' 'G' 'B' 'A' 'Comments'};
    
    % QA_lookup_T=outerjoin(atlas_lookup_T,lookup_T,'Key','ROI','LeftVariables',{'ROI' 'Structure'},'MergeKeys',true);
    QA_lookup_T=outerjoin(atlas_lookup_T,lookup_T,'Key','ROI','LeftVariables',{'ROI' 'structure'},'MergeKeys',true);
    
    QA_lookup_path=regexprep(file,'_labels_.*txt',['_labels_lookup_outliers_in_CoV_of_' contrast '.txt']);
    %writetable(QA_lookup_T,QA_lookup_path,'Delimiter',' ')
    writetable(QA_lookup_T,QA_lookup_path,'Delimiter','\t');
    %
    %
    
    plot_option='log_volume';
    %plot_option='sorted_by_volume'
    switch plot_option
        case 'sorted_by_volume'
            %plot(full_T.sort_order,full_T.([contrast '_CoV']),'o','LineWidth',1); \
            x_axis=full_T.sort_order;
            y_axis=full_T.([contrast '_CoV']);
            min_range=min(x_axis(:));
            max_range=max(x_axis(:));
            rng=round(max_range-min_range)+1;
            step=1;
        case 'log_volume'
            %plot(CoV_array(1,:),CoV_array(2,:),'o','LineWidth',1);
            x_axis= log10(full_T.volume_mm3);
            y_axis=full_T.([contrast '_CoV']);
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
    % end % Loop over multiple stats files
    
    annotate_up_to = 12; % Max of how many red/yellow flags we want to annotate
    
    % Generate A,B,C,D,E...
    alphas={'A':'Z'};
    alphas{:}(15)=[]; % Remove 'o'
    alphas{:}(9)=[]; % Remove 'i'
    
    red_flags=[];
    %red_flags=find(full_T.([contrast '_CoV'])>=0.1);
    %rf_vals=full_T.([contrast '_CoV'])(red_flags)';%CoV_array(2,red_flags);
    red_flags=find(y_axis(:)>=0.1);
    rf_vals=y_axis(red_flags)';%CoV_array(2,red_flags);
    [sorted_flags,sf_ind]=sort(rf_vals,2,'descend');
    new_ind=red_flags(sf_ind);
    
    % Annotate top N (5 by default) offenders
    if numel(new_ind)>annotate_up_to
        new_ind((annotate_up_to+1):end)=[];
    end
    
    space_for_legend = 0.1875*numel(new_ind)+1*(numel(new_ind)>0);
    
    c_fig(CC)=figure(CC);
    c_fig(CC).PaperPositionMode='auto';
    c_fig(CC).Units='Inches';
    
    %c_fig(CC).OuterPosition=[1 CC*2 8 (2.5+space_for_legend)];
    %c_fig(CC).OuterPosition=[1 1 8 5];
    c_fig(CC).Position=[1 1 8 11];
    c_fig(CC).Color=[1 1 1];
    
    
    plot(x_axis,y_axis,'o','LineWidth',1);
    
    switch plot_option
        case 'sorted_by_volume'
            xlabel('ROI rank small to large')
            
        case 'log_volume'
            xlabel('log(volume mm3)')
            
        otherwise
            xlabel('ROI')
    end
    %xlim([0 max(x_axis(:))])
    xlim([min_range max_range])
    
    
    ylabel(strrep([field ' COV'],'_','\_'))
    
    y_max=0.25;
    ylim(1*[0 y_max])
    %ylim(1*[0 0.25])
    hold on
    
    
    
    legendary=struct; % structure or cell array?
    
    for rr=1:numel(new_ind)
        flag_ind=new_ind(rr);
        %text(CoV_array(1,flag_ind)-2,min(CoV_array(2,flag_ind)*1.2,y_max),num2str(CoV_array(1,flag_ind)),'FontName','Ariel','FontSize',14,'FontWeight','Bold')
        %text(full_T.sort_order(flag_ind)-2,min(sorted_flags(rr)*1.2,y_max),[num2str(full_T.ROI(flag_ind)) ' ' full_T.Structure{flag_ind}],'FontName','Ariel','FontSize',14,'FontWeight','Bold')
        letter=alphas{:}(rr);
        switch  plot_option
            case 'sorted_by_volume'
                text(x_axis(flag_ind)+2,min(sorted_flags(rr)*1.05,y_max),letter,'FontName','Ariel','FontSize',14,'FontWeight','Bold')
                % ar = annotation('arrow');
                % c = ar.Color;
                % ar.Color = 'red';
                % ar.Position=[ (x_axis(flag_ind)) sorted_flags(rr)*1.05 0.2 0.2];
            case 'log_volume'
                text(x_axis(flag_ind)+0.02,min(sorted_flags(rr)*1.05,y_max),letter,'FontName','Ariel','FontSize',14,'FontWeight','Bold')
                % ar = annotation('arrow');
                % c = ar.Color;
                % ar.Color = 'red';
                % ar.Position=[ (x_axis(flag_ind)) sorted_flags(rr)*1.05 -0.2 -0.2];
                % ar.Units='points';
            otherwise
                text(CoV_array(1,flag_ind)-2,min(CoV_array(2,flag_ind)*1.2,y_max),letter,'FontName','Ariel','FontSize',14,'FontWeight','Bold');
        end
        
        switch  plot_option
            case 'sorted_by_volume'
                %legend(rr).string=[num2str(full_T.ROI(flag_ind)) ' ' full_T.Structure{flag_ind}];
                %legendary(rr).string=[letter ': ' num2str(full_T.ROI(flag_ind)) ' ' full_T.structure{flag_ind} ' (' sprintf('%0.1f',100*sorted_flags(rr)) ];
                legendary(rr).string=[letter ': '  full_T.structure{flag_ind} ' (ROI ' num2str(full_T.ROI(flag_ind)) ') - ' sprintf('%0.1f',100*sorted_flags(rr)) '%' ];
            case 'log_volume'
                %legend(rr).string=[num2str(full_T.ROI(flag_ind)) ' ' full_T.Structure{flag_ind}];
                legendary(rr).string=[letter ': '  full_T.structure{flag_ind} ' (ROI ' num2str(full_T.ROI(flag_ind)) ') - ' sprintf('%0.1f',100*sorted_flags(rr)) '%' ];
            otherwise
                legendary(rr).string=[letter ': (ROI' num2str(CoV_array(1,flag_ind)) ') - ' num2str(sCoV_array(2,flag_ind))  '%'];
        end
        legendary(rr).string=strrep(legendary(rr).string,'_','\_');
        hold on
    end
    
    
    
    hold on;plot(min_range:step:max_range,ones([rng 1])*0.05,'--','Color', [0.9290 0.6940 0.1250], 'LineWidth',2)
    hold on;plot(min_range:step:max_range,ones([rng 1])*0.1,'--r','LineWidth',1.5)
    %for LL = 1: numel(legendary)
    %    if isfield(legendary,'string')
    %       text(1,LL*5,legendary(LL).string)
    %    end
    %end
    %legend(names{:})
    if isfield(legendary,'string')
        for LL = 1: numel(legendary)
            dummyh(LL) = line(nan, nan, 'Linestyle', 'none', 'Marker', 'none', 'Color', 'none');
        end
        leg = legend(dummyh(:),legendary(:).string,'Location','SouthOutside');
        leg.Units='inches';
        %leg.Position(1)=1;
    end
    
    
    %c_fig(CC).Position(4)=c_fig(CC).Position(4)+leg.Position(4);
    set(gca,'FontName','Ariel','FontSize',16,'FontWeight','Bold')
    c_fig(CC).Position=[1 1 8 (2.5+space_for_legend)];
    hold off
    %print -depsc2 correlation.eps;
    %export_fig(['/civmnas4/rja20/BJs_march_test_' contrast '_CoVs.pdf'],'-pdf','-nofontswap','-painters','-nocrop', c_fig(CC))
    out_pdf{CC}=[outdir '/QA_' runno_or_id '_CoV_' contrast '.pdf'];
    export_fig(out_pdf{CC},'-pdf','-painters','-nocrop', c_fig(CC))
end
%hold off
contrast_string=strrep(string_of_contrasts,',','_');
final_file = [outdir '/QA_summary_' runno_or_id '_CoVs_' contrast_string '.pdf'];
append_pdfs(final_file ,out_pdf{:});
final_mat_file = [outdir '/QA_data_' runno_or_id '_CoVs_' contrast_string '.mat'];
out_file=final_file;
save(final_mat_file);
% Cleanup?
if cleanup && exist(final_file,'file')
    for cc=1:numel(contrasts)
        cmd = ['rm ' out_pdf{cc}];
        system(cmd);
    end
else 
    if cleanup
        warning(['Error creating ' final_file '; not cleaning up component pdfs.']);
    end
end

end