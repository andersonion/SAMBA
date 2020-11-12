function compile_command_for_strip_mask()

include_files = {
    '/cm/shared/apps/MATLAB/R2015b/toolbox/curvefit/curvefit/smooth.m'
    '/cm/shared/apps/MATLAB/R2015b/toolbox/images/images/imfill.m'
    };
compile_command__allpurpose('strip_mask_exec',include_files,'')

return