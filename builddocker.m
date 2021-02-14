% https://www.mathworks.com/help/compiler/package-matlab-standalone-applications-into-docker-images.html
res = compiler.build.standaloneApplication('brainSegmentation.m', 'TreatInputsAsNumeric', false)
opts = compiler.package.DockerOptions(res,'ImageName','brainSegmentation-standalone-app')
compiler.package.docker(res, 'Options', opts)
% docker run --rm -e "DISPLAY=:0" -v /tmp/.X11-unix:/tmp/.X11-unix mymagic-standalone-app 5
