function varargout = summarize_cluster_anatomy(varargin)
% See ft_cluster_helpers.summarize_cluster_anatomy for documentation.
% This shim forwards to the consolidated helper implementation.

[varargout{1:nargout}] = ft_cluster_helpers('summarize_cluster_anatomy', varargin{:});
