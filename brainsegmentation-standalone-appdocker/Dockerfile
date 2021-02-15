FROM matlabruntime/r2020b/release/update0/c06e080208000000
COPY ./applicationFilesForMATLABCompiler /usr/bin/mlrtapp

# Create directories to store data and write output
RUN mkdir /data
RUN mkdir /model
RUN mkdir /out

ENTRYPOINT ["/usr/bin/mlrtapp/brainSegmentation"]
