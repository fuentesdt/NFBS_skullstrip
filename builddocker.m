% https://www.mathworks.com/help/compiler/package-matlab-standalone-applications-into-docker-images.html
res = compiler.build.standaloneApplication('brainSegmentation.m', 'TreatInputsAsNumeric', false, 'AdditionalFiles','dicePixelClassification3dLayer.m')
opts = compiler.package.DockerOptions(res,'ImageName','brainsegmentation-standalone-app')
compiler.package.docker(res, 'Options', opts)
% docker build -t brainsegmentation-standalone-app brainsegmentation-standalone-appdocker
% matlab -nodisplay -r "brainSegmentation('/rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/preprocess/imgResized/resized_T1w_A00060372.nii.gz', '/rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/fold_1-trainedDensenet3d.mat', '/rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/segout/seg_T1w_A00060372'); exit"
% brainSegmentationstandaloneApplication/run_brainSegmentation.sh /data/apps/MATLAB/R2020b /rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/preprocess/imgResized/resized_T1w_A00060372.nii.gz /rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/fold_1-trainedDensenet3d.mat ./text
% docker run --rm -e "DISPLAY=:57" -v /tmp/.X11-unix:/tmp/.X11-unix -v /rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/preprocess/imgResized:/data -v /rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation:/model -v /home/fuentes:/out:rw brainsegmentation-standalone-app /data/resized_T1w_A00060372.nii.gz /model/fold_1-trainedDensenet3d.mat /test




