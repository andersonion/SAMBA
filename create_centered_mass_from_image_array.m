function create_centered_mass_from_image_array(in_file,out_file)
%in_file = '/glusterspace/VBM_14obrien01_DTI101b-work/preprocess/base_images/native_reference_controlSpring2013_4.nii.gz';
%out_file = '/glusterspace/VBM_14obrien01_DTI101b-work/preprocess/base_images/native_reference_controlSpring2013_4_TEST.nii.gz';

nii = load_untouch_nii(in_file);
image = nii.img;

dims=nii.hdr.dime.dim;
dims = dims(2:4)
frac = 4;
starters = ceil(dims*(1/2-1/(frac*2)));
enders = starters + round(dims/frac);

image = image*0;
image(starters(1):enders(1),starters(2):enders(2),starters(3):enders(3))=1;

nii.img = image;


save_untouch_nii(nii,in_file)