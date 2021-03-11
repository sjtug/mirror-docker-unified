#!/usr/bin/env julia
# This script builds/pulls all static contents needed by storage server.
#
# Usage:
#  1. make sure you've added StorageMirrorServer.jl
#  2. generate/pull all tarballs: `julia gen_static_full.jl`
#  3. set a cron job to run step 2 regularly
#
# Note:
#   * Initialization would typically take days, depending on the network bandwidth and CPU
#   * set `JULIA_NUM_THREADS` to use multiple threads
#
# Disk space requirements for a complete storage (increases over time):
#   * `STATIC_DIR`: at least 500GB, would be better to have more than 3TB free space

using StorageMirrorServer
using Pkg

# This holds all the data you need to set up a storage server
# For example, my nginx service serves all files in `/mnt/mirrors` as static contents using autoindex
output_dir = ENV["LUG_path"]

# check https://status.julialang.org/ for available public storage servers
upstreams = [
    "https://us-east.pkg.julialang.org"
]

registries = [
    # (name, uuid, original_git_url)
    ("General", "23338594-aafe-5451-b93e-139f81909106", "https://github.com/JuliaRegistries/General")
]

# These are default parameter settings for StorageMirrorServer
# you can modify them accordingly to fit your settings
parameters = Dict(
    # if needed, you can pass custom http parameters
    :http_parameters => Dict{Symbol, Any}(
        :retry => true,
        :retries => 5,
        :readtimeout => 600
        # download data using proxy
        # it also respects `http_proxy`, `https_proxy` and `no_proxy` environment variables
        # :proxy => "http://localhost:1080"
    ),

    # whether to show the progress bar
    :show_progress => true,

    # for how long (hours) you want to skip resources in `/failed_resources.txt` until the next try
    :skip_duration => 12,
)

for reg in registries
    mirror_tarball(reg, upstreams, output_dir; parameters...)
end
