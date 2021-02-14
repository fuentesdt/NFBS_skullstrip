% https://www.mathworks.com/help/compiler/package-matlab-standalone-applications-into-docker-images.html
res = compiler.build.standaloneApplication('brainSegmentation.m', 'TreatInputsAsNumeric', false)
opts = compiler.package.DockerOptions(res,'ImageName','brainsegmentation-standalone-app')
compiler.package.docker(res, 'Options', opts)
% matlab -nodisplay -r "brainSegmentation('/rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/preprocess/imgResized/resized_T1w_A00060372.nii.gz', '/rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/fold_1-trainedDensenet3d.mat', '/rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/segout/seg_T1w_A00060372'); exit"
% docker run --rm -e "DISPLAY=:57" -v /tmp/.X11-unix:/tmp/.X11-unix brainsegmentation-standalone-app /rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/preprocess/imgResized/resized_T1w_A00060372.nii.gz /rsrch1/ip/rmuthusivarajan/imaging/NFBS/Train_interpolation/fold_1-trainedDensenet3d.mat ./test
