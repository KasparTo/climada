function entityORassets = climada_assets_encode(entityORassets,hazard,max_distance_to_hazard)
% climada assets encode
% NAME:
%   climada_assets_encode
% PURPOSE:
%   encode an entity (an already read assets file)
%   eoncoding means: map read data points to calculation centroids of
%   hazard event set
%   
%   Accepts both entity or assets as well as hazard or centroids as input,
%   output i therefore either entity (if entity on input) or assets (if
%   assets on input)
%
%   normally called from: climada_entity_read
%   see also: climada_assets_encode_check
% CALLING SEQUENCE:
%   entityORassets=climada_assets_encode(entityORassets,hazard)
% EXAMPLE:
%   assets=climada_assets_encode(climada_entity_load,hazard)
% INPUTS:
%   entityORassets: an assets structure (such as entity.assets), see
%       climada_entity_read. Or just the full entity (with assets in entity.assets)
%       > prompted for if empty (promting for an entity, the assets within
%       are then taken - in this case, instead of assets, the entity is
%       returned in 'assets')
%   hazard: either a hazard set (struct) or a hazard set file (.mat with a
%       struct) or a centroid struct (as returned by climada_centroids_load or
%       climada_centroids_read). hazard needs to have fields hazard.lon and
%       hazard.lat, centroids fields centroids.lon and centroids.lat  
%       > promted for if not given (select either a hazard event set or a
%       centroids .mat file)
%       if set to 'SKIP', do not encode, return original assets (used for
%       special cases, where this way no need for if statements prior to
%       calling climada_assets_encode)
%       SPECIAL: centroids with centroid_ID<0 (in either hazard.centroid_ID
%       or centroids.centroid_ID) are not used in encoding.
%       (this way the user can e.g. temporarily 'disable' centroids prior
%       to passing them to climada_assets_encode by simply setting their
%       centroid_ID=-1)
%       NOTE: if isfield(centroids,'peril_ID') and FL some special rules apply
% OPTIONAL INPUT PARAMETERS:
% OUTPUTS:
%   the encoded assets, means locations mapped to calculation centroids
%       new field assets.centroid_index added
%       NOTE: in case an entity instead of assets was passed on input, the
%       output is also the entity
% MODIFICATION HISTORY:
% David N. Bresch, david.bresch@gmail.com, 20091227
% David N. Bresch, david.bresch@gmail.com, 20100107, revised, changed from entity.assets to assets
% David N. Bresch, david.bresch@gmail.com, 20141127, allows for assets OR entity as input
% David N. Bresch, david.bresch@gmail.com, 20141127, allows for hazard OR centroids as input
% Lea Mueller, muellele@gmail.com, 20150511, only for unique lon/lat values, essential speedup
% David N. Bresch, david.bresch@gmail.com, 20150610, Lea's speedup fixed
% Lea Mueller, muellele@gmail.com, 20150617, speedup works for both dimensions of entity.lats and .lons (1xn and nx1)
% David N. Bresch, david.bresch@gmail.com, 20150618, Lea's speedup fixed 2nd time (line 134)
% Lea Mueller, muellele@gmail.com, 20150805, define a maximum distance to hazard, otherwise centroid_index is set to 0 and no damage wil be calculated (see climada_EDS_calc)             
% David N. Bresch, david.bresch@gmail.com, 20150825, bug-fix to use centroids instead of hazard
% Lea Mueller, muellele@gmail.com, 20150915, set max_distance_to_hazard as input variable
%-

global climada_global
if ~climada_init_vars,return;end % init/import global variables

% poor man's version to check arguments
if ~exist('entityORassets','var'),entityORassets=[];end
if ~exist('hazard','var'),hazard=[];end
if ~exist('min_distance_to_hazard','var'),max_distance_to_hazard=[];end


% PARAMETERS
%
% whether we print all encoded centroids (=1) or not (=0), rather to TEST
verbose=0; % default =0


% set max_distance_to_hazard = 10^6; % 1000 km, in [m]
if isempty(max_distance_to_hazard),max_distance_to_hazard = 10^6; end


% prompt for assets (entity) if not given
if isempty(entityORassets) % local GUI
    entity_file=[climada_global.data_dir filesep 'entities' filesep '*.mat'];
    [filename, pathname] = uigetfile(entity_file, 'Select entity to re-encode:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        entity_file=fullfile(pathname,filename);
        load(entity_file) % loads entity
        entityORassets=entity; % see below, entity_passed_on_input
    end
end

% prompt for hazard if not given
if isempty(hazard) % local GUI
    hazard=[climada_global.data_dir filesep 'hazards' filesep '*.mat'];
    [filename, pathname] = uigetfile(hazard, 'Select hazard event set (or centroids) to encode to:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        hazard=fullfile(pathname,filename);
    end
elseif ischar(hazard)
    if strcmp(hazard,'SKIP'),return;end % special case, see climad_entity_read
end

% load the hazard, if a filename has been passed
if ~isstruct(hazard)
    hazard_file=hazard;hazard=[];
    load(hazard_file);
end

% figure whether we got an entity OR assets as input
if isfield(entityORassets,'assets') % an entity instead of assets passed
    entity_passed_on_input=1;
    entity=entityORassets; % store full entity
    assets=entity.assets; % assign
else
    entity_passed_on_input=0;
    assets=entityORassets;
end
% now, assets contain assets indeed

if isfield(hazard,'intensity')
    % hazard does indeed contain a hazard structure
    % hence we do not need all fields
    centroids.lon=hazard.lon;
    centroids.lat=hazard.lat;
    centroids.peril_ID=hazard.peril_ID;
    if isfield(hazard,'filename'),centroids.filename = hazard.filename;end
    if isfield(hazard,'comment'), centroids.comment  = hazard.comment;end
else
    % hazard does contain centroids
    centroids=hazard; clear hazard
end
% now, centroids are centroids indeed

% omit flagged centroids (those with centroid_ID<0)
if isfield(centroids,'centroid_ID')
    centroids.lon=centroids.lon(centroids.centroid_ID>0);
    centroids.lat=centroids.lat(centroids.centroid_ID>0);
end


% check lat lon dimension (1xn or nx1), now the concatenations works for both dimensions
[lon_i lon_j] = size(assets.lon);
% find unique lat lons
if lon_j == 1 % was lon_i
    [lon_lat,indx, indx2] = unique([assets.lon assets.lat],'rows');
elseif lon_i == 1 % was lon_j
    [lon_lat,indx, indx2] = unique([assets.lon;assets.lat]','rows');
else
    fprintf('Please check the dimensions of assets.lon and assets.lat.\n')
    return
end


% start encoding
n_assets              = length(indx);
% n_assets            = length(assets.Value);
assets.centroid_index = assets.Value*0; % init

% define a minimum distance to hazard position (in m). assets that are too
% far away from hazard, will get centroid_index =0 and no damage will be
% calculated for this asset
% max_distance_to_hazard = 10^6; % 1000 km, in [m]
% if isfield(centroids,'peril_ID') % switched to centroids, david.bresch@gmail.com, 20150825
%     if strcmp(centroids.peril_ID,'FL'),max_distance_to_hazard = 20;end % in [m]
% end
    
    
t0       = clock;
msgstr   = sprintf('Encoding %i assets ... ',n_assets);
mod_step = 10; % first time estimate after 10 assets, then every 100
if climada_global.waitbar
    fprintf('%s (updating waitbar with estimation of time remaining every 100th asset)\n',msgstr);
    h        = waitbar(0,msgstr);
    set(h,'Name','Encoding assets');
else
    fprintf('%s (waitbar suppressed)\n',msgstr);
    format_str='%s';
end

for asset_i=1:n_assets
    if climada_global.waitbar,waitbar(asset_i/n_assets,h);end
    
    dist_m                       = climada_geo_distance(assets.lon(indx(asset_i)),assets.lat(indx(asset_i)),centroids.lon,centroids.lat);
    [min_dist,min_dist_index]    = min(dist_m);
    % set closest hazard position to zero if hazard is too far away from asset (depends on peril ID)
    if min_dist>max_distance_to_hazard 
        min_dist_index = 0;
    end
    indx3                        = find(indx2 == asset_i);
    assets.centroid_index(indx3) = min_dist_index;
    
    %if verbose,fprintf('%f/%f --> %f/%f\n',assets.lon(asset_i),assets.lat(asset_i),centroids.lon(min_dist_index),centroids.lat(min_dist_index));end
    
    % the progress management
    if mod(asset_i,mod_step)==0
        mod_step          = 100;
        t_elapsed_event   = etime(clock,t0)/asset_i;
        events_remaining  = n_assets-asset_i;
        t_projected_sec   = t_elapsed_event*events_remaining;
        if t_projected_sec<60
            msgstr = sprintf('est. %3.0f sec left (%i/%i assets)',t_projected_sec,asset_i,n_assets);
        else
            msgstr = sprintf('est. %3.1f min left (%i/%i assets)',t_projected_sec/60,asset_i,n_assets);
        end
        if climada_global.waitbar
            waitbar(asset_i/n_assets,h,msgstr); % update waitbar
        else
            fprintf(format_str,msgstr); % write progress to stdout
            format_str=[repmat('\b',1,length(msgstr)) '%s']; % back to begin of line
        end
    end
    
end % asset_i
if climada_global.waitbar
    close(h) % dispose waitbar
else
    fprintf(format_str,''); % move carriage to begin of line
end

assets.hazard.filename = 'assets encode'; % default
assets.hazard.comment  = 'assets encode'; % default
if isfield(centroids,'filename'),assets.hazard.filename = centroids.filename;end
if isfield(centroids,'comment' ),assets.hazard.comment  = centroids.comment;end

if entity_passed_on_input
    entity         = rmfield(entity,'assets'); % delete input
    entity.assets  = assets; % assign re-encoded assets
    % and pass on output:
    entityORassets = entity; % return entity as output
else
    entityORassets = assets; % return assets as output
end

return