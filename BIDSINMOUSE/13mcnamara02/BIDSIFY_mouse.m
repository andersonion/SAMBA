% BIDS the mouse brain set for SAMBA
mystudy='13mcnamara02'
myinpipeline='tensor_create'
mycontrast={'DWI' , 'FA'}
myatlas='DTI101b'
myspace='CHASSSYM2CIVM'; %myspace='CHASSSYM2RAS'
mystage='preaffine_N4'
myoutpipeline='samba'
inputprefix='DTI'

mystudy = regexprep(mystudy,'[^a-zA-Z0-9-_]','');
myinpipeline=myinpipeline(myinpipeline,'[^a-zA-Z0-9-_]','');


mypath='/Users/alex/AlexBadea_MyPapers/vba/BIDS_SAMBA/dwi/'

mkdir([mypath 'BIDSINMOUSE'])

myparticipants=readtable([mypath, 'participants2.csv'])
nsubj=size(myparticipants)
nsubj=nsubj(1);



for i=1:nsubj
    BJsuffix='dwi'
  myfilename=['Subj'  num2str(i) '_' myparticipants.scanid{i} '_' myspace '_' mystage '_' 'e' '_' mycontrast{1} '.nii.gz' ]
  myrunno=myparticipants.scanid{i};
  myinfile=['/Users/alex/AlexBadea_MyPapers/vba/BIDS_SAMBA/dwi/' myrunno '_BJ_m0_DTI_' BJsuffix '*.nii.gz']
  mydir=[mypath 'BIDSINMOUSE' '/' mystudy '/' 'Subj'  num2str(i) '/' myinpipeline '/' inputprefix '/' ]
  mkdir(mydir)
  copyfile(myinfile, [mydir myfilename] )
end

for i=1:nsubj
    BJsuffix='fa'
  myfilename=['Subj'  num2str(i) '_' myparticipants.scanid{i} '_' myspace '_' mystage '_' 'e' '_' mycontrast{2} '.nii.gz' ]
  myrunno=myparticipants.scanid{i};
  myinfile=['/Users/alex/AlexBadea_MyPapers/vba/BIDS_SAMBA/dwi/' myrunno '_BJ_m0_DTI_' BJsuffix '*.nii.gz']
  mydir=[mypath 'BIDSINMOUSE' '/' mystudy '/' 'Subj'  num2str(i) '/' myinpipeline '/' inputprefix '/' ]
  %mkdir(mydir)
  copyfile(myinfile, [mydir myfilename] )
end

