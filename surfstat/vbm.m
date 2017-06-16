path='/Volumes/androsspace/evan/blast_analysis/fa/other_tx/double/*masked.nii';

[wmav volwmav]=SurfStatAvVol({'/Volumes/androsspace/evan/blast_analysis/fa/average_control_fa_masked_smooth.nii'
    '/Volumes/androsspace/evan/blast_analysis/fa/average_control_fa_masked_smooth.nii'});

filenames = SurfStatListDir( path );

[ Y0, vol0 ] = SurfStatReadVol( filenames, [], { [], [], 10 } );

%1 = control, 0 = single,
control=[0 0 0 0 1 1 1 1]; %[1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 0 0];
layout = reshape( [ find(1-control) 0 0 0 0 find(control)], 4, 3);

figure(1); SurfStatViews( Y0, vol0, 0, layout );
title('FA for 4 double blast subjects (left) and 9 controls (right)','FontSize',18);

%[ wmav, volwmav ] = SurfStatAvVol( filenames( find(control) ) );
%caxis([-.001 0.001]);

%figure(2); SurfStatView1( wmav, volwmav );


%SurfStatView1( wmav, volwmav, 'datathresh', 0.4 );

[ Y, vol ] = SurfStatReadVol( filenames, wmav > 0.4);

Group = term( var2fac( control, { 'blast'; 'control' } ) );

slm = SurfStatLinMod( Y, Group, vol );
slm = SurfStatT( slm, Group.control - Group.blast );
figure(3); SurfStatView1( slm.t, vol );
title( 'T-statistic' ,'FontSize',18);

figure(4); SurfStatView1( SurfStatP( slm ), vol );
title( 'P-value<0.05' ,'FontSize',18);

[ pval, peak, clus] = SurfStatP( slm );


figure(5); SurfStatView1( SurfStatQ( slm ), vol );
title('Q-value < 0.05','FontSize',18);

qval=SurfStatQ( slm );
SurfStatWriteVol('/Volumes/androsspace/evan/blast_analysis/qval.nii',qval.Q,vol);
