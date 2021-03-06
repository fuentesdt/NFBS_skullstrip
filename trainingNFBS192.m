%% 3-D Brain Extraction from MRI
% Train and cross validate a 3-D densenet for brain extraction on T1w image
% load nifti data from /rsrch1/ip/egates1/NFBS\ Skull\ Strip/NFBSFilepaths.csv 

% Clear workspace
clearvars; close all; clc;

gpuDevice(1)

%Input filename and pathways
fname = 'inputNFBS192.json';
jsonText = fileread(fname);
jsonData = jsondecode(jsonText);

% Read file pathways into table
fullFileName = jsonData.fullFileName;
delimiter = jsonData.delimiter;

T = readtable(fullFileName, 'Delimiter', delimiter);
A = table2array(T);

volCol = jsonData.volCol;
lblCol = jsonData.lblCol;
volLoc = A(:,volCol);
lblLoc = A(:,lblCol);

stoFoldername = jsonData.stoFoldername;
destination = fullfile(stoFoldername);

% define readers
maskReader = @(x) (niftiread(x) > 0);
volReader = @(x) niftiread(x);
 
%read T1w images data into imageDatastore
volds = imageDatastore(volLoc, ...
     'FileExtensions','.gz','LabelSource','foldernames','ReadFcn',volReader);
 
classNames = ["background","brain"];
pixelLabelID = [0 1];
 
%read Mask images into pixelLabeldatastore
pxds = pixelLabelDatastore(lblLoc,classNames, pixelLabelID, ...
        'FileExtensions','.gz','ReadFcn',maskReader);
    
reset(volds);
reset(pxds);      
  
%create directories to store preprocessed data 
mkdir(fullfile(destination,'images'));
mkdir(fullfile(destination,'labels'));
        
%% Crop relevant region
id = 1;

while hasdata(pxds)
        outL = readNumeric(pxds);
        outV = read(volds);
        temp = outL>0;
        sz = size(outL);
        reg = regionprops3(temp,'BoundingBox');
        tol = 64;
        ROI = ceil(reg.BoundingBox(1,:));
        ROIst = ROI(1:3) - tol;
        ROIend = ROI(1:3) + ROI(4:6) + tol;

        ROIst(ROIst<1)=1;
        ROIend(ROIend>sz)=sz(ROIend>sz);

        tumorRows = ROIst(2):ROIend(2);
        tumorCols = ROIst(1):ROIend(1);
        tumorPlanes = ROIst(3):ROIend(3);

        tcropVol = outV(tumorRows,tumorCols, tumorPlanes);
        tcropLabel = outL(tumorRows,tumorCols, tumorPlanes);

% Data set with a valid size for 3-D U-Net (multiple of 8)
        ind = floor(size(tcropVol)/8)*8;
        incropVol = tcropVol(1:ind(1),1:ind(2),1:ind(3));
        mask = incropVol == 0;

%%%%%%%% channelWisePreProcess
        % As input has 4 channels (modalities), remove the mean and divide by the
        % standard deviation of each modality independently.
        incropVol1=single(incropVol);

        chn_Mean = mean(incropVol1,[1 2 3]);
        chn_Std = std(incropVol1,0,[1 2 3]);
        cropVol1 = (incropVol1 - chn_Mean)./chn_Std;

        rangeMin = -5;
        rangeMax = 5;
    
        % Remove outliers
        cropVol1(cropVol1 > rangeMax) = rangeMax;
        cropVol1(cropVol1 < rangeMin) = rangeMin;
    
        % Rescale the data to the range [0, 1]
        cropVol1 = (cropVol1 - rangeMin) / (rangeMax - rangeMin);
    
        % Set the nonbrain region to 0
        % cropVol1(mask) = 0;
        cropLabel = tcropLabel(1:ind(1),1:ind(2),1:ind(3));
                 
        PId = volds.Labels;
        save('PId.mat', 'PId'); %patientId 
        P = cellstr(PId); %categorical to cell
        patientId = P{id,1};
        
        procImgName = ['preprocessed_T1w_', patientId];
        procLblName = ['preprocessed_T1w_brainmask_', patientId];
        
        imDir = fullfile(destination,'images',procImgName);
        labelDir = fullfile(destination,'labels',procLblName);
        
        resizeCropvol = imresize3(cropVol1,[192 192 192]);
        resizeCropLabel = imresize3(cropLabel, [192 192 192]);
        
        % save preprocessed data to folders
        niftiwrite(resizeCropvol,imDir);
        niftiwrite(uint8(resizeCropLabel),labelDir);
                               
        id = id + 1;
end

%% create datastores for processed labels and images
% Images Datapath % define reader
procVolReader = @(x) niftiread(x);
procVolLoc = fullfile(destination,'images');
procVolDs = imageDatastore(procVolLoc, ...
    'FileExtensions','.nii','LabelSource','foldernames','ReadFcn',procVolReader);

procLblReader =  @(x) niftiread(x);
procLblLoc = fullfile(destination,'labels');
classNames = ["background","tumor"];
pixelLabelID = [0 1];
procLblDs = pixelLabelDatastore(procLblLoc,classNames,pixelLabelID, ...
    'FileExtensions','.nii','ReadFcn',procLblReader);

%kfold partition
num_images = length(procVolDs.Labels); %number of obervations for kfold
c1 = cvpartition(num_images,'kfold',5);
err = zeros(c1.NumTestSets,1);

C = cell(1,5);
[idxTest] = deal(C);

for idxFold = 1:c1.NumTestSets 
    idxTest{idxFold} = test(c1,idxFold); %logical indices for test set
    save('idxTest.mat','idxTest');

    %imdsTest{idxFold} = subset(procVolDs,idxTest{idxFold}); %test imagedatastore
    %save('imdsTest.mat','imdsTest');
    %pxdsTest{idxFold} = subset(procLblDs,idxTest{idxFold}); %test pixelimagedatastore
    %%save('pxdsTest.mat', 'pxdsTest');
    
    idxHold = training(c1,idxFold); %logical indices for training set-holdout partition
    imdsHold = subset(procVolDs,idxHold); %imds for holdout partition
    pxdsHold = subset(procLblDs,idxHold); %imds for holdout partition

    num_imdsHold = length(imdsHold.Labels); %number of obervations for holdout partition
    c2 = cvpartition(num_imdsHold,'holdout',0.25);
    
    idxVal = test(c2); %logical indices for val set
    imdsVal = subset(imdsHold,idxVal); %val imagedatastore
    pxdsVal = subset(pxdsHold,idxVal); %val pixelimagedatastore
   
    idxTrain = training(c2); %logical indices for training set
    imdsTrain = subset(imdsHold,idxTrain); %training imagedatastore
    pxdsTrain = subset(pxdsHold,idxTrain); %training pixelimagedatastore
end

%Need Random Patch Extraction on training and validation Data
    patchSize = [64 64 64];
    patchPerImage = 16;
    miniBatchSize = 8;

%training patch datastore
    trPatchDs = randomPatchExtractionDatastore(imdsTrain,pxdsTrain,patchSize, ...
    'PatchesPerImage',patchPerImage);
    trPatchDs.MiniBatchSize = miniBatchSize;

%validation patch datastore
    valPatchDs = randomPatchExtractionDatastore(imdsVal,pxdsVal,patchSize, ...
    'PatchesPerImage',patchPerImage);
    valPatchDs.MiniBatchSize = miniBatchSize;

%% Create Layer Graph
% Create the layer graph variable to contain the network layers.
%define n as number of channels
n = 1;
lgraph = layerGraph();

%% Add Layer Branches
% Add the branches of the network to the layer graph. Each branch is a linear 
% array of layers.
% Helper function for densenet3d upsample3dLayer.m

tempLayers = [
    image3dInputLayer([64 64 64 n],"Name","input","Normalization","none")
    batchNormalizationLayer("Name","BN_Module1_Level1")
    convolution3dLayer([3 3 3],32,"Name","conv_Module1_Level1","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module1_Level1")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    batchNormalizationLayer("Name","BN_Module1_Level2")
    convolution3dLayer([3 3 3],64,"Name","conv_Module1_Level2","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module1_Level2")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = concatenationLayer(4,2,"Name","concat_1");
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    maxPooling3dLayer([2 2 2],"Name","maxpool_Module1","Padding","same","Stride",[2 2 2])
    batchNormalizationLayer("Name","BN_Module2_Level1")
    convolution3dLayer([3 3 3],64,"Name","conv_Module2_Level1","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module2_Level1")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    batchNormalizationLayer("Name","BN_Module2_Level2")
    convolution3dLayer([3 3 3],128,"Name","conv_Module2_Level2","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module2_Level2")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = concatenationLayer(4,2,"Name","concat_2");
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    maxPooling3dLayer([2 2 2],"Name","maxpool_Module2","Padding","same","Stride",[2 2 2])
    batchNormalizationLayer("Name","BN_Module3_Level1")
    convolution3dLayer([3 3 3],128,"Name","conv_Module3_Level1","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module3_Level1")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    batchNormalizationLayer("Name","BN_Module3_Level2")
    convolution3dLayer([3 3 3],256,"Name","conv_Module3_Level2","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module3_Level2")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = concatenationLayer(4,2,"Name","concat_3");
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    maxPooling3dLayer([2 2 2],"Name","maxpool_Module3","Padding","same","Stride",[2 2 2])
    batchNormalizationLayer("Name","BN_Module4_Level1")
    convolution3dLayer([3 3 3],256,"Name","conv_Module4_Level1","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module4_Level1")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    batchNormalizationLayer("Name","BN_Module4_Level2")
    convolution3dLayer([3 3 3],512,"Name","conv_Module4_Level2","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module4_Level2")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    concatenationLayer(4,2,"Name","concat_4")
    upsample3dLayer([2 2 2],512,"Name","upsample_Module4","Stride",[2 2 2])];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    concatenationLayer(4,2,"Name","concat3")
    batchNormalizationLayer("Name","BN_Module5_Level1")
    convolution3dLayer([3 3 3],256,"Name","conv_Module5_Level1","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module5_Level1")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    batchNormalizationLayer("Name","BN_Module5_Level2")
    convolution3dLayer([3 3 3],256,"Name","conv_Module5_Level2","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module5_Level2")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    concatenationLayer(4,2,"Name","concat_5")
    upsample3dLayer([2 2 2],256,"Name","upsample_Module5","Stride",[2 2 2])];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    concatenationLayer(4,2,"Name","concat2")
    batchNormalizationLayer("Name","BN_Module6_Level1")
    convolution3dLayer([3 3 3],128,"Name","conv_Module6_Level1","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module6_Level1")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    batchNormalizationLayer("Name","BN_Module6_Level2")
    convolution3dLayer([3 3 3],128,"Name","conv_Module6_Level2","Padding","same","WeightsInitializer","narrow-normal")
    reluLayer("Name","relu_Module6_Level2")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    concatenationLayer(4,2,"Name","concat_6")
    upsample3dLayer([2 2 2],128,"Name","upsample_Module6","Stride",[2 2 2])];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    concatenationLayer(4,2,"Name","concat1")
    batchNormalizationLayer("Name","BN_Module7_Level1")
    convolution3dLayer([3 3 3],64,"Name","conv_Module7_Level1","Padding","same")
    reluLayer("Name","relu_Module7_Level1")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    batchNormalizationLayer("Name","BN_Module7_Level2")
    convolution3dLayer([3 3 3],64,"Name","conv_Module7_Level2","Padding","same")
    reluLayer("Name","relu_Module7_Level2")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    concatenationLayer(4,2,"Name","concat")
    batchNormalizationLayer("Name","BN_Module7_Level3")
    convolution3dLayer([1 1 1],2,"Name","ConvLast_Module7")
    softmaxLayer("Name","softmax")
    dicePixelClassification3dLayer("output")];
lgraph = addLayers(lgraph,tempLayers);

% clean up helper variable
clear tempLayers;
%% Connect Layer Branches
% Connect all the branches of the network to create the network graph.

lgraph = connectLayers(lgraph,"relu_Module1_Level1","BN_Module1_Level2");
lgraph = connectLayers(lgraph,"relu_Module1_Level1","concat_1/in1");
lgraph = connectLayers(lgraph,"relu_Module1_Level2","concat_1/in2");
lgraph = connectLayers(lgraph,"concat_1","maxpool_Module1");
lgraph = connectLayers(lgraph,"concat_1","concat1/in1");
lgraph = connectLayers(lgraph,"relu_Module2_Level1","BN_Module2_Level2");
lgraph = connectLayers(lgraph,"relu_Module2_Level1","concat_2/in1");
lgraph = connectLayers(lgraph,"relu_Module2_Level2","concat_2/in2");
lgraph = connectLayers(lgraph,"concat_2","maxpool_Module2");
lgraph = connectLayers(lgraph,"concat_2","concat2/in1");
lgraph = connectLayers(lgraph,"relu_Module3_Level1","BN_Module3_Level2");
lgraph = connectLayers(lgraph,"relu_Module3_Level1","concat_3/in1");
lgraph = connectLayers(lgraph,"relu_Module3_Level2","concat_3/in2");
lgraph = connectLayers(lgraph,"concat_3","maxpool_Module3");
lgraph = connectLayers(lgraph,"concat_3","concat3/in1");
lgraph = connectLayers(lgraph,"relu_Module4_Level1","BN_Module4_Level2");
lgraph = connectLayers(lgraph,"relu_Module4_Level1","concat_4/in1");
lgraph = connectLayers(lgraph,"relu_Module4_Level2","concat_4/in2");
lgraph = connectLayers(lgraph,"upsample_Module4","concat3/in2");
lgraph = connectLayers(lgraph,"relu_Module5_Level1","BN_Module5_Level2");
lgraph = connectLayers(lgraph,"relu_Module5_Level1","concat_5/in1");
lgraph = connectLayers(lgraph,"relu_Module5_Level2","concat_5/in2");
lgraph = connectLayers(lgraph,"upsample_Module5","concat2/in2");
lgraph = connectLayers(lgraph,"relu_Module6_Level1","BN_Module6_Level2");
lgraph = connectLayers(lgraph,"relu_Module6_Level1","concat_6/in1");
lgraph = connectLayers(lgraph,"relu_Module6_Level2","concat_6/in2");
lgraph = connectLayers(lgraph,"upsample_Module6","concat1/in2");
lgraph = connectLayers(lgraph,"relu_Module7_Level1","BN_Module7_Level2");
lgraph = connectLayers(lgraph,"relu_Module7_Level1","concat/in2");
lgraph = connectLayers(lgraph,"relu_Module7_Level2","concat/in1");

%% Plot Layers

plot(lgraph);


%% do the training %%
options = trainingOptions('adam', ...
    'MaxEpochs',50, ...
    'InitialLearnRate',5e-4, ...
    'LearnRateSchedule','piecewise', ...
    'LearnRateDropPeriod',5, ...
    'LearnRateDropFactor',0.95, ...
    'ValidationData',valPatchDs, ...
    'ValidationFrequency',400, ...
    'Plots','training-progress', ...
    'Verbose',false, ...
    'MiniBatchSize',miniBatchSize);

    modelDateTime = datestr(now,'dd-mmm-yyyy-HH-MM-SS');
    [net,info] = trainNetwork(trPatchDs,lgraph,options);
    save(['fold_' num2str(kfold) '-trainedDensenet3d192.mat'],'net');
    infotable = struct2table(info);
    writetable(infotable, ['fold_' num2str(idxFold) '-Densenet3d192-info.txt']);
%end

