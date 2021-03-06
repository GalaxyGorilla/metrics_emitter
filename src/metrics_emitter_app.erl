%%%-------------------------------------------------------------------
%% @doc metrics_emitter public API
%% @end
%%%-------------------------------------------------------------------

-module(metrics_emitter_app).

-behaviour(application).

%% Application callbacks
-export([start/2
        ,start/0
        ,stop/1
        ,fire_control/0
        ,fire_worker/1
        ,loop/1]).

-define(INTERVAL, 1000).
-define(DEFAULT_TIMEOUT, 5000).
-define(DEFAULT_PROCESS_MAX, 1000).
-define(DEFAULT_SLEEP, 10000).
-define(DEFAULT_LOOP_SLEEP, 5).

%%====================================================================
%% API
%%====================================================================

start() ->
    application:ensure_all_started(metrics_emitter).

start(_StartType, _StartArgs) ->
    Reporters = application:get_env(metrics_emitter, reporters, 
                                    [{exometer_report_tty, []}]),
    [setup_metrics(Reporter, ReportOptions) 
     || {Reporter, ReportOptions} <- Reporters],
    Pid = fire(),
    {ok, Pid}.

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

fire() ->
    spawn(?MODULE, fire_control, []).

fire_control() ->
    NumberOfProcesses = trunc(random:uniform() * ?DEFAULT_PROCESS_MAX),
    ProcessWaitTimes = [trunc(random:uniform() * ?DEFAULT_TIMEOUT) 
                        || _ <- lists:seq(1, NumberOfProcesses)],
    [spawn(?MODULE, fire_worker, [Time]) || Time <- ProcessWaitTimes],
    timer:sleep(?DEFAULT_SLEEP),
    fire_control().

fire_worker(Time) ->
    Pid = spawn(?MODULE, loop, [Time]),
    timer:kill_after(Time, Pid).

setup_metrics(Reporter, ReportOptions) ->

    ok = exometer_report:add_reporter(Reporter, ReportOptions),

    % VM memory.
    % total = processes + system.
    % processes = used by Erlang processes, their stacks and heaps.
    % system = used but not directly related to any Erlang process.
    % atom = allocated for atoms (included in system).
    % binary = allocated for binaries (included in system).
    % ets = allocated for ETS tables (included in system).
    ok = exometer:new([erlang, memory],
                      {function, erlang, memory, ['$dp'], value,
                       [total, processes, system, atom, binary, ets]}),
    ok = exometer_report:subscribe(Reporter,
                                   [erlang, memory],
                                   [total, processes, system, atom, binary,
                                    ets], ?INTERVAL),

    % Memory actively used by the VM, allocated (should ~match OS allocation),
    % unused (i.e. allocated - used), and usage (used / allocated).
    ok = exometer:new([recon, alloc],
                      {function, recon_alloc, memory, ['$dp'], value,
                       [used, allocated, unused, usage]}),
    ok = exometer_report:subscribe(Reporter,
                                   [recon, alloc],
                                   [used, allocated, unused, usage], ?INTERVAL),

    % Memory reserved by the VM, grouped into different utility allocators.
    ok = exometer:new([recon, alloc, types],
                      {function, recon_alloc, memory,
                       [allocated_types], proplist,
                       [binary_alloc, driver_alloc, eheap_alloc,
                        ets_alloc, fix_alloc, ll_alloc, sl_alloc,
                        std_alloc, temp_alloc]}),
    ok = exometer_report:subscribe(Reporter,
                                   [recon, alloc, types],
                                   [binary_alloc, driver_alloc, eheap_alloc,
                                    ets_alloc, fix_alloc, ll_alloc, sl_alloc,
                                    std_alloc, temp_alloc], ?INTERVAL),

    % The time percentage each scheduler has been running processes, NIFs,
    % BIFs, garbage collection, etc. versus time spent idling or trying to
    % schedule processes.
    Schedulers = lists:seq(1, erlang:system_info(schedulers)),
    ok = exometer:new([recon, scheduler, usage],
                      {function, recon, scheduler_usage, [1000], proplist, 
                       Schedulers},
                      [{cache, 5000}]),
    ok = exometer_report:subscribe(Reporter,
                                   [recon, scheduler, usage],
                                   Schedulers, ?INTERVAL),

    % process_count = current number of processes.
    % port_count = current number of ports.
    ok = exometer:new([erlang, system],
                      {function, erlang, system_info, ['$dp'], value,
                       [process_count, port_count]}),
    ok = exometer_report:subscribe(Reporter,
                                   [erlang, system],
                                   [process_count, port_count], ?INTERVAL),

    % The number of processes that are ready to run on all available run queues.
    ok = exometer:new([erlang, statistics],
                      {function, erlang, statistics, ['$dp'], value,
                       [run_queue]}),
    ok = exometer_report:subscribe(Reporter,
                                   [erlang, statistics],
                                   [run_queue], ?INTERVAL).

loop(Time) ->
  loop(Time, "").

loop(Time, Akk) ->
    timer:sleep(?DEFAULT_LOOP_SLEEP),
    loop(Time, Akk ++ "XXXXX").
