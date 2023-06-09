% Convert intracellular electrophysiology recording data to the NWB format
% in Matlab
%
% Run this script to convert intracellular electrophysiology recording data
% and associated optogenetic stimulation data generated at the University
% of Bristol (UoB) to the Neurodata Without Borders (NWB) file format. This
% script is explained in the accompanying Bristol GIN for Patch Clamp Data
% tutorial available at
% https://dervinism.github.io/bristol-neuroscience-data-guide/tutorials/Bristol%20GIN%20for%20Patch%20Clamp%20Data.html
% 
% You can use this script to get an idea of how to convert your own
% intracellular electrophysiology data to the NWB file format.


%% Record metadata
% Project (experiment) metadata
projectName = 'Inhibitory plasticity experiment in CA1';
experimenter = 'MU';
institution = 'University of Bristol';
publications = 'In preparation';
lab = 'Jack Mellor lab';
brainArea = 'Hippocampus CA1';

% Animal metadata
animalID = '180126';
ageInDays = 34;
age = ['P' num2str(ageInDays) 'D']; % Convert to ISO8601 format: https://en.wikipedia.org/wiki/ISO_8601#Durations
strain = 'Ai32/PVcre';
sex = 'F';
species = 'Mus musculus';
weight = [];
description = '001'; % Animal testing order.

% Session metadata
startYear = 2018;
startMonth = 1;
startDay = 26;
startTime = datetime(startYear, startMonth, startDay);
year = num2str(startYear); year = year(3:4);
month = num2str(startMonth); if numel(month) == 1; month = ['0' month]; end
day = num2str(startDay); if numel(day) == 1; day = ['0' day]; end
sliceNumber = 1;
cellNumber = 1;
sessionID = [year month day '__s' num2str(sliceNumber) ...
  'c' num2str(cellNumber)]; % mouse-id_time_slice-id_cell-id
sessionDescription = 'Current and voltage clamp recordings using electric/optogenetic stimulation plasticity-inducing protocol.';
expDescription = ['Optogenetic and current stim pathways were stimulated in an interleaved fashion with a 5 second interval.' ...
                  'Each stimulation pathway consisted of 2 stimulations at 50ms interval: 2 action potentials or 2 light pulses.' ...
                  'After stable baselines in both pathways, plasticity protocol was induced.' ...
                  'After plasticty protocol induced, optogenetic and current stimulation resumed as before.'];
sessionNotes = ['180126 PV mouse' ...
                'Gender: female' ...
                'DOB: 23/12/17 – 4/5wo' ...
                'genotype: ??' ...
                'ID: 065321 l0 r1' ...
                'in NBQX and AP5' ...
                'NEW  protocol using soph''s' ... 
                '0ms gap single pre 4 post spikes with 0ms interval between the pre and 1st post' ...
                'Slice 1' ...
                'Cell1' ...
                'Ok cell died within around 20 mins'];
 
% Generate Matlab classes from NWB core schema files
generateCore;

% Assign NWB file fields
nwb = NwbFile( ...
  'session_description', sessionDescription, ...
  'identifier', sessionID, ...
  'session_start_time', startTime, ...
  'general_experimenter', experimenter, ... % optional
  'general_session_id', sessionID, ... % optional
  'general_institution', institution, ... % optional
  'general_related_publications', publications, ... % optional
  'general_notes', sessionNotes, ... % optional
  'general_lab', lab, ...
  'general_experiment_description', expDescription); % optional

% Create subject object
subject = types.core.Subject( ...
  'subject_id', animalID, ...
  'age', age, ...
  'description', description, ...
  'species', species, ...
  'sex', sex);
nwb.general_subject = subject;

%% Load data
data = load(['..\' year month day '__s' num2str(sliceNumber) 'c' num2str(cellNumber) '_001_ED.mat']);
data = data.(['V' year month day '__s' num2str(sliceNumber) 'c' num2str(cellNumber) '_001_wave_data']);
data.values = squeeze(data.values)';
vcScaleFactor = 1/10E12;
ccScaleFactor = 2.5/10E5;

% Extract sweep and run data
sweepIDs = int64(arrayfun(@(x)x.number,data.frameinfo,'UniformOutput',true)); % Apply function to each array element
                                                                              % and output in uniform array
sweepDataPoints = double(arrayfun(@(x)x.points,data.frameinfo,'UniformOutput',true));
sweepStartTimes = double(arrayfun(@(x)x.start,data.frameinfo,'UniformOutput',true));
sweepStates = double(arrayfun(@(x)x.state,data.frameinfo,'UniformOutput',true));
sweepLabels = arrayfun(@(x)x.label,data.frameinfo,'UniformOutput',false);
[runs, runInds, runStartTimes, runDataPoints, runUnits] = getRuns(sweepLabels, sweepDataPoints, sweepStartTimes);
nSweeps = numel(sweepIDs); % Total number of sweeps
nRuns = numel(runs); % Total number of runs
runInds = [runInds' [runInds(2:end)'-1; nSweeps]];

%% Convert intracellular electrophysiology data
% Create the recording device object
device = types.core.Device( ...
  'description', 'Amplifier for recording intracellular data.', ...
  'manufacturer', 'Molecular Devices');
nwb.general_devices.set('Amplifier_Multiclamp_700A', device);

electrode = types.core.IntracellularElectrode( ...
  'description', 'A patch clamp electrode', ...
  'location', 'Cell soma in CA1 of hippocampus', ...
  'slice', ['slice #' num2str(sliceNumber)], ...
  'device', types.untyped.SoftLink(device));
nwb.general_intracellular_ephys.set('icephys_electrode', electrode);

% Add current and voltage clamp data
stimulusObjectViews = [];
responseObjectViews = [];
for sweep = 1:nSweeps
  run = find(runInds(:,1) <= sweep & sweep <= runInds(:,2));
  input.data = data.values(sweep,:);
  input.samplingRate = 1/data.interval;
  input.startTime = sweepStartTimes(sweep);
  input.electrode = electrode;
  input.stimState = sweepStates(sweep);
  input.unit = runUnits{run};
  input.condition = runs{run};
  input.sweepOrder = sweepIDs(sweep);
  if strcmpi(runs{run}, 'plasticity')
    input.data = input.data*ccScaleFactor;
    [stimulusObject, responseObject] = setCClampSeries(input);
  else
    input.data = input.data*vcScaleFactor;
    [stimulusObject, responseObject] = setVClampSeries(input);
  end
  if sweep < 10
    prefix = '00';
  elseif sweep < 100
    prefix = '0';
  else
    prefix = '';
  end
  nwb.stimulus_presentation.set(['PatchClampSeries' prefix num2str(sweep)], stimulusObject);
  nwb.acquisition.set(['PatchClampSeries' prefix num2str(sweep)], responseObject);
  stimulusObjectViews = [stimulusObjectViews; types.untyped.ObjectView(stimulusObject)];
  responseObjectViews = [responseObjectViews; types.untyped.ObjectView(responseObject)];
end

% Create intracellular recordings table
icRecTable = types.core.IntracellularRecordingsTable( ...
  'categories', {'electrodes', 'stimuli', 'responses'}, ...
  'colnames', {'order','points','start','state','label','electrode','stimulus','response'}, ...
  'description', [ ...
    'A table to group together a stimulus and response from a single ', ...
    'electrode and a single simultaneous recording and for storing ', ...
    'metadata about the intracellular recording.']);

icRecTable.electrodes = types.core.IntracellularElectrodesTable( ...
  'description', 'Table for storing intracellular electrode related metadata.', ...
  'colnames', {'electrode'}, ...
  'id', types.hdmf_common.ElementIdentifiers( ...
    'data', sweepIDs), ...
  'electrode', types.hdmf_common.VectorData( ...
    'data', repmat(types.untyped.ObjectView(electrode), nSweeps, 1), ...
    'description', 'Column for storing the reference to the intracellular electrode'));

icRecTable.stimuli = types.core.IntracellularStimuliTable( ...
  'description', 'Table for storing intracellular stimulus related data and metadata.', ...
  'colnames', {'stimulus'}, ...
  'id', types.hdmf_common.ElementIdentifiers( ...
    'data', sweepIDs), ...
  'stimulus', types.core.TimeSeriesReferenceVectorData( ...
    'description', 'Column storing the reference to the recorded stimulus for the recording (rows)', ...
    'data', struct( ...
      'idx_start', ones(1,nSweeps).*-1, ... % Start index in time for the timeseries
      'count', ones(1,nSweeps).*-1, ... % Number of timesteps to be selected starting from idx_start
      'timeseries', stimulusObjectViews)));

icRecTable.responses = types.core.IntracellularResponsesTable( ...
  'description', 'Table for storing intracellular response related data and metadata.', ...
  'colnames', {'response'}, ...
  'id', types.hdmf_common.ElementIdentifiers( ...
    'data', sweepIDs), ...
  'response', types.core.TimeSeriesReferenceVectorData( ...
    'description', 'Column storing the reference to the recorded response for the recording (rows)', ...
    'data', struct( ...
      'idx_start', zeros(1,nSweeps), ...
      'count', sweepDataPoints, ...
      'timeseries', responseObjectViews)));

% Add the sweep metadata category to the intracellular recording table
icRecTable.categories = [icRecTable.categories, {'sweeps'}];
icRecTable.dynamictable.set( ...
  'sweeps', types.hdmf_common.DynamicTable( ...
    'description', 'Sweep metadata.', ...
    'colnames', {'order','points','start','state','label'}, ...
    'id', types.hdmf_common.ElementIdentifiers( ...
      'data', sweepIDs), ...
    'order', types.hdmf_common.VectorData( ...
      'data', sweepIDs, ...
      'description', 'Recorded sweep order.'), ...
    'points', types.hdmf_common.VectorData( ...
      'data', sweepDataPoints, ...
      'description', 'The number of data points within the sweep.'), ...
    'start', types.hdmf_common.VectorData( ...
      'data', sweepStartTimes, ...
      'description', 'The sweep recording start time in seconds.'), ...
    'state', types.hdmf_common.VectorData( ...
      'data', sweepStates, ...
      'description', ['The experimental state ID: ', ...
                      '0 - light stimulation during the baseline condition.', ...
                      '1 - current stimulation during the baseline condition.', ...
                      '2 - inhibitory synaptic plasticity induction condition.', ...
                      '9 - break between baseline and plasticity induction conditions.']), ...
    'label', types.hdmf_common.VectorData( ...
      'data', sweepLabels, ...
      'description', 'The experimental state label.')));
 
nwb.general_intracellular_ephys_intracellular_recordings = icRecTable;

%% Group sweep references in tables of increasing hierarchy
% Group simultaneous recordings
% Group indices of simultaneous recordings: There are no simultaneous
% recordings, so each sweep stands on its own
simSweeps = {};
simSweepsTag = {};
for iSweep = 1:nSweeps
  simSweeps{numel(simSweeps)+1} = iSweep; %#ok<*SAGROW>
  simSweepsTag = [simSweepsTag; 'noSimultaneousRecs'];
end

% Create a simultaneous recordings table with a custom column
% 'simultaneous_recording_tag'
[recVectorData, recVectorInd] = util.create_indexed_column( ...
  simSweeps, ...
  'Column with references to one or more rows in the IntracellularRecordingsTable table', ...
  icRecTable);
 
icSimRecsTable = types.core.SimultaneousRecordingsTable( ...
  'description', [ ...
    'A table for grouping different intracellular recordings from ', ...
    'the IntracellularRecordingsTable together that were recorded ', ...
    'simultaneously from different electrodes. As no sweeps were recorded ',...
    'simultaneously, groupings contain only single sweeps.'], ...
  'colnames', {'recordings', 'simultaneous_recording_tag'}, ...
  'id', types.hdmf_common.ElementIdentifiers( ...
    'data', int64(0:nSweeps-1)), ...
  'recordings', recVectorData, ...
  'recordings_index', recVectorInd, ...
  'simultaneous_recording_tag', types.hdmf_common.VectorData( ...
    'description', 'A custom tag for simultaneous_recordings', ...
    'data', simSweepsTag));

nwb.general_intracellular_ephys_simultaneous_recordings = icSimRecsTable;

% Group sequential recordings using the same type of stimulus
% Group indices of sequential recordings
seqSweeps = {};
stimulusType = {};
seqGroupCount = 0;
for iRun = 1:nRuns
  condSweeps = zeros(1,nSweeps);
  condSweeps(runInds(iRun,1):runInds(iRun,end)) = true;
  condStates = sweepStates(logical(condSweeps));
  uniqueSweepStates = unique(condStates);
  for iState = 1:numel(uniqueSweepStates)
    stateSweeps = find(sweepStates' == uniqueSweepStates(iState) ...
      & logical(condSweeps));
    seqSweeps{numel(seqSweeps)+1} = stateSweeps;
    if uniqueSweepStates(iState) == 0
      stimulusType = [stimulusType; 'light'];
    elseif uniqueSweepStates(iState) == 1
      stimulusType = [stimulusType; 'current'];
    elseif uniqueSweepStates(iState) == 2
      stimulusType = [stimulusType; 'combined'];
    elseif uniqueSweepStates(iState) == 9
      stimulusType = [stimulusType; 'noStim'];
    end
    seqGroupCount = seqGroupCount + 1;
  end
end

% Create a sequential recordings table
[recVectorData, recVectorInd] = util.create_indexed_column( ...
  seqSweeps, ...
  'Column with references to one or more rows in the SimultaneousRecordingsTable table', ...
  icSimRecsTable);
 
icSeqRecsTable = types.core.SequentialRecordingsTable( ...
  'description', [ ...
    'A table for grouping different intracellular ', ...
    'simultaneous recordings from the SimultaneousRecordingsTable ', ...
    'together. Individual sweeps are grouped on the basis of the ', ...
    'stimulation type: Light, current, combined, or none. Sweeps are ', ...
    'grouped only if they belong to the same condition.'], ...
  'colnames', {'simultaneous_recordings', 'stimulus_type'}, ...
  'id', types.hdmf_common.ElementIdentifiers( ...
    'data', int64(0:seqGroupCount-1)), ...
  'simultaneous_recordings', recVectorData, ...
  'simultaneous_recordings_index', recVectorInd, ...
  'stimulus_type', types.hdmf_common.VectorData( ...
    'description', 'Column storing the type of stimulus used for the sequential recording', ...
    'data', stimulusType));
 
nwb.general_intracellular_ephys_sequential_recordings = icSeqRecsTable;

% Group recordings into runs
% Group indices of individual runs
runInds = {[1,2], 3, 4, 5, [6,7]};

% Create a repetitions table
[recVectorData, recVectorInd] = util.create_indexed_column( ...
  runInds, ...
  'Column with references to one or more rows in the SequentialRecordingsTable table', ...
  icSeqRecsTable);

icRepetitionsTable = types.core.RepetitionsTable( ...
  'description', [ ...
    'A table for grouping different intracellular sequential ', ...
    'recordings together. With each simultaneous recording ', ...
    'representing a particular type of stimulus, the RepetitionsTable ', ...
    'is used to group sets of stimuli applied in sequence.' ...
  ], ...
  'colnames', {'sequential_recordings'}, ...
  'id', types.hdmf_common.ElementIdentifiers( ...
    'data', int64(0:nRuns-1) ...
  ), ...
  'sequential_recordings', recVectorData, ...
  'sequential_recordings_index', recVectorInd ...
);

nwb.general_intracellular_ephys_repetitions = icRepetitionsTable;

% Group runs into experimental conditions
% Group indices for different conditions
condInds = {[1,5], [2,4], 3};
condTags = {'baselineStim','noStim','plasticityInduction'};

% Create experimental conditions table
[recVectorData, recVectorInd] = util.create_indexed_column( ...
  condInds, ...
  'Column with references to one or more rows in the RepetitionsTable table', ...
  icRepetitionsTable);
 
icExpConditionsTable = types.core.ExperimentalConditionsTable( ...
  'description', [ ...
    'A table for grouping different intracellular recording ', ...
    'repetitions together that belong to the same experimental ', ...
    'conditions.' ...
  ], ...
  'colnames', {'repetitions', 'tag'}, ...
  'id', types.hdmf_common.ElementIdentifiers( ...
    'data', int64(0:numel(condInds)-1) ...
  ), ...
  'repetitions', recVectorData, ...
  'repetitions_index', recVectorInd, ...
  'tag', types.hdmf_common.VectorData( ...
    'description', 'Experimental condition label', ...
    'data', condTags ...
  ) ...
);

nwb.general_intracellular_ephys_experimental_conditions = icExpConditionsTable;

%% Add the slice image
sliceImage = imread(['..\' year month day ' s' num2str(sliceNumber) 'c' num2str(cellNumber) '.jpg']);

sliceImage = types.core.GrayscaleImage( ...
  'data', sliceImage, ...  % required: [height, width]
  'description', 'Grayscale image of the recording slice.' ...
);

imageCollection = types.core.Images( ...
  'description', 'A container for slice images.'...
);
imageCollection.image.set('slice_image', sliceImage);

nwb.acquisition.set('ImageCollection', imageCollection);

%% Write the NWB file
nwbExport(nwb, [sessionID '.nwb']);



%% Local functions
function [runs, inds, startTimes, dataPoints, units] = getRuns(sweepLabels, sweepDataPoints, sweepStartTimes)
% [runs, inds, startTimes, dataPoints, units] = getRuns(sweepLabels, sweepDataPoints, sweepStartTimes)
%
% Function identifies recording runs and their starting indices.
%
% Input: sweepLabels - a character array with sweep labels.
%        dataPoints - a scalar vector with datapoint info for each sweep.
%        sweepStartTimes - a scalar vector with sweep start times.
% Output: runs - a string vector with runs' names.
%         inds - a vector with runs' start sweep indices.
%         startTimes - a vector with runs' start times.
%         dataPoints - a scalar with data points per individual sweep in
%                      each run.
%         units - a character array with data units.

runs{1} = 'baseline';
inds = 1;
dataPoints = sweepDataPoints(1);
startTimes = sweepStartTimes(1);
sweepUnits = 'amperes';
units{1} = sweepUnits;
for sweep = 2:numel(sweepLabels)
  if ~strcmpi(sweepLabels{sweep}(1),sweepLabels{sweep-1}(1))
    if strcmpi(sweepLabels{sweep}(1),'b')
      runs{numel(runs)+1} = 'break'; %#ok<*AGROW>
      units{numel(units)+1} = 'amperes';
    elseif strcmpi(sweepLabels{sweep}(1),'0')
      runs{numel(runs)+1} = 'plasticity';
      units{numel(units)+1} = 'volts';
    elseif strcmpi(sweepLabels{sweep}(1),'1')
      runs{numel(runs)+1} = 'baseline';
      units{numel(units)+1} = 'amperes';
    end
    inds = [inds sweep];
    dataPoints = [dataPoints sweepDataPoints(sweep)];
    startTimes = [startTimes sweepStartTimes(sweep)];
  end
end
end


function [VCSS, VCS] = setVClampSeries(input)
% [VCSS, VCS] = setVClampSeries(input)
%
% Create VoltageClampStimulusSeries and VoltageClampSeries objects.
% 
% Function creates, names, and annotates stimulus and response
% equivalents for a voltage clamp given the data. The response
% data is reused when creating the stimulus as no stimulus data
% exists.
%
% Input: input - a structure variable with the following fields:
%          data - a 2D matrix containing somatic voltage clamp recordings.
%          The first dimension corresponds to individual sweeps and
%          the second dimension is time.
%          samplingRate - a sampling rate scalar.
%          startTime - a starting time scalar.
%          electrode - an electrode object.
%          condition - a string variable with the experimental condition
%            or the run name.
%          stimState - the stimulation state ID (scalar).
%          unit - a data unit string.
%          sweepOrder - the sweep order number.
%
% Output: VCSS - the newly created VoltageClampStimulusSeries object.
%         VCS - the newly created VoltageClampSeries object.

if strcmpi(input.condition, 'baseline')
  if input.stimState == 0
    description = 'Baseline condition: Light stimulation';
    stimDescription = 'Baseline stimulation: Double light pulses.';
  elseif input.stimState == 1
    description = 'Baseline condition: Current stimulation';
    stimDescription = 'Baseline stimulation: Double current pulses.';
  end
elseif strcmpi(input.condition, 'break')
  description = 'Break sweeps are used while switching between two conditions: Nothing happens.';
  stimDescription = 'No stimulation.';
end

VCSS = types.core.VoltageClampStimulusSeries( ...
  'description', description, ...
  'data', input.data', ...
  'data_continuity', 'continuous', ...
  'data_unit', 'volts', ...
  'gain', 1., ...
  'starting_time', input.startTime, ...
  'starting_time_rate', input.samplingRate, ...
  'electrode', types.untyped.SoftLink(input.electrode), ...
  'stimulus_description', stimDescription, ...
  'sweep_number', input.sweepOrder);

VCS = types.core.VoltageClampSeries( ...
  'description', description, ...
  'data', input.data', ...
  'data_continuity', 'continuous', ...
  'data_unit', input.unit, ...
  'gain', 1., ...
  'starting_time', input.startTime, ...
  'starting_time_rate', input.samplingRate, ...
  'electrode', types.untyped.SoftLink(input.electrode), ...
  'stimulus_description', stimDescription, ...
  'sweep_number', input.sweepOrder);
end


function [CCSS, CCS] = setCClampSeries(input)
% [CCSS, CCS] = setCClampSeries(input)
%
% Create CurrentClampStimulusSeries and CurrentClampSeries objects.
%
% Function creates, names, and annotates stimulus and response
% equivalents for a current clamp given the data. The response
% data is reused when creating the stimulus as no stimulus data
% exists.
%
% Input: input - a structure variable with the following fields:
%          data - a 2D matrix containing somatic current clamp recordings.
%            The first dimension corresponds to individual sweeps and
%            the second dimension is time.
%          samplingRate - a sampling rate scalar.
%          startTime - a starting time scalar.
%          electrode - an electrode object.
%          unit - a data unit string.
%          sweepOrder - the sweep order number.
%          
%
% Output: CCSS - the newly created CurrentClampStimulusSeries object.
%         CCS - the newly created CurrentClampSeries object.

CCSS = types.core.CurrentClampStimulusSeries( ...
  'description', 'Plasticity condition', ...
  'data', input.data', ...
  'data_continuity', 'continuous', ...
  'data_unit', 'amperes', ...
  'gain', 1., ...
  'starting_time', input.startTime, ...
  'starting_time_rate', input.samplingRate, ...
  'electrode', types.untyped.SoftLink(input.electrode), ...
  'stimulus_description', 'Plasticity protocol: Simultaneous current and light stimulation', ...
  'sweep_number', input.sweepOrder);

CCS = types.core.CurrentClampSeries( ...
  'description', 'Plasticity condition', ...
  'data', input.data', ...
  'data_continuity', 'continuous', ...
  'data_unit', input.unit, ...
  'gain', 1., ...
  'starting_time', input.startTime, ...
  'starting_time_rate', input.samplingRate, ...
  'electrode', types.untyped.SoftLink(input.electrode), ...
  'stimulus_description', 'Plasticity protocol: Simultaneous current and light stimulation', ...
  'sweep_number', input.sweepOrder);
end