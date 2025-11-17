function varargout = plot_cluster_distribution(varargin)
% See ft_cluster_helpers.plot_cluster_distribution for documentation.
% This shim forwards to the consolidated helper implementation.

[varargout{1:nargout}] = ft_cluster_helpers('plot_cluster_distribution', varargin{:});
