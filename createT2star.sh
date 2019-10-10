#!/bin/bash
## This is a code snippet that illustrates the cacluation of T2* and R2*

scan_list="xnat_table.csv"
baseOutputPath="t2starData/"

sed 1d $scan_list |while IFS=, read zbblid zscanid sessionid f4 project f6 scannum f8 f9 desc other; do
(
bblid=$(echo ${zbblid}|sed 's/^0*//')
scanid=$(echo ${zscanid}|sed 's/^0*//')
subjOutputDir="${baseOutputPath}/${bblid}/${scanid}/"
niftidir=${subjOutputDir}/nifti/

# --- Calculate T2* ---
# 1. First get the echo times fom the dicom header
for d in $(ls ${dicomdir}/*dcm*);do 
	echoline=$(dicom_hdr $d |grep -i "echo number");
	echoNum=${echoline##*Number//}; 
	timeline=$(dicom_hdr $d |grep -i "echo time");
	echoTime=${timeline##*Time//};
	if [ $echoNum -eq 1 ]; then 
		te1=$echoTime
	elif [ $echoNum -eq 2 ]; then 
		te2=$echoTime 
	else echo "\nbad echo numbers for $bblid $scanid $d">>$logfile;
	fi
done
dTE=$(echo $te2 - $te1 |bc) #bc does floating point math

# 2. Create the T2* image
### mask: brain mask
### mag1 and mag2 are the aligned magnitude images

mask=${niftidir}/mask_in_mag1.nii.gz
fslmaths $mag1 -s 3 ${subjOutputDir}/mag1sm.nii.gz #light smoothing mag1
fslmaths $mag2 -s 3 ${subjOutputDir}/mag2sm.nii.gz #light smoothing mag2
mag1sm=${subjOutputDir}/mag1sm.nii.gz
mag2sm=${subjOutputDir}/mag2sm.nii.gz
# Calculate T2* from the mag image signal intensity
3dcalc -a $mag1sm -b $mag2sm -expr "-$dTE/(log(b/a))" -prefix ${subjOutputDir}/${bblid}_${scanid}_t2star.nii.gz -overwrite
# Apply the brain mask
3dcalc -a ${subjOutputDir}/${bblid}_${scanid}_t2star.nii.gz -b $mask -expr '(a*b)' -prefix ${subjOutputDir}/${bblid}_${scanid}_t2star.nii.gz -overwrite

# 3. Convert from T2* (msec) to R2* (1/sec)
3dcalc -a ${subjOutputDir}/${bblid}_${scanid}_t2star.nii.gz -expr '(1000/a)' -prefix ${subjOutputDir}/${bblid}_${scanid}_r2star.nii.gz 

# --- Now align to the study template --- #
# 1. Flirt to calculate the rigid alignment to the T1 image
thisT2s="${subjOutputDir}/${bblid}_${scanid}_t2star.nii.gz"

flirt -in $thisT2s -ref $betT1 -omat $subjOutputDir/${bblid}_${scanid}_t2star_to_t1.mat -dof 6 -cost mutualinfo -o $subjOutputDir/${bblid}_${scanid}_t2star_to_t1.nii.gz

# 2. Convert the matrix for ANTs
c3d_affine_tool -ref $betT1 -src $thisT2s $subjOutputDir/${bblid}_${scanid}_t2star_to_t1.mat -fsl2ras -oitk $subjOutputDir/${bblid}_${scanid}_t2star_to_t1.tfm

# 3. Apply the xforms to T2* and R2*
antsApplyTransforms -d 3 -i $thisT2s -r study_template_brain.nii.gz -o $subjOutputDir/${bblid}_${scanid}_t2star_templatespace.nii.gz -t $thisWarp $thisAff $subjOutputDir/${bblid}_${scanid}_t2star_to_t1.tfm -n HammingWindowedSinc

thisR2s="${subjOutputDir}/${bblid}_${scanid}_r2star.nii.gz"
antsApplyTransforms -d 3 -i $thisR2s -r study_template_brain.nii.gz  -o $subjOutputDir/${bblid}_${scanid}_r2star_templatespace.nii.gz -t $thisWarp $thisAff $subjOutputDir/${bblid}_${scanid}_t2star_to_t1.tfm -n HammingWindowedSinc

