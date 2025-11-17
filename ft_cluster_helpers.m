function varargout = ft_cluster_helpers(action, varargin)
%FT_CLUSTER_HELPERS Backward-compatible dispatcher for cluster utilities.
%   This function preserves legacy calls of the form
%       ft_cluster_helpers('plot_cluster_distribution', ...)
%   by forwarding the request to the refactored standalone helpers.
%
%   Accepted actions:
%       'plot_cluster_distribution'  -> plot_cluster_distribution(...)
%       'summarize_cluster_anatomy'  -> summarize_cluster_anatomy(...)
%
%   The helpers themselves live in the same folder as this dispatcher.

    if nargin < 1 || ~ischar(action)
        error('ft_cluster_helpers:InvalidInvocation', ...
            'First argument must be a string action name.');
    end

    switch lower(strtrim(action))
        case 'plot_cluster_distribution'
            [varargout{1:nargout}] = plot_cluster_distribution(varargin{:});
        case 'summarize_cluster_anatomy'
            [varargout{1:nargout}] = summarize_cluster_anatomy(varargin{:});
        otherwise
            error('ft_cluster_helpers:UnknownAction', ...
                'Unsupported action "%s".', action);
    end
end
