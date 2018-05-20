%%%-----------------------------------------------------------------------------
%%% File:      cachet_fsm.erl
%%% @author    Eric Pailleau <cachet@crownedgrouse.com>
%%% @copyright 2014 crownedgrouse.com
%%% @doc  
%%% Cachet Finite State Machine
%%% @end  
%%%
%%% Permission to use, copy, modify, and/or distribute this software
%%% for any purpose with or without fee is hereby granted, provided
%%% that the above copyright notice and this permission notice appear
%%% in all copies.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
%%% WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
%%% WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
%%% AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
%%% CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
%%% LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
%%% NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
%%% CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
%%%
%%% Created : 2014-11-10
%%%-----------------------------------------------------------------------------
-module(cachet_fsm).
-behaviour(gen_fsm).

-export([start_link/1]).
-export([init/1, handle_event/3, handle_info/3, handle_sync_event/4, terminate/3]).
-export([cache_under_limit/2, cache_over_limit/2]).
-export([split_under_limit/2, split_over_limit/2]).

-record(cachet,{ init           % Data received at init
                ,ram=undefined  % Ram table name
                ,disc=undefined % Disc table name
                ,mode=undefined % cache / split / detect (default)
                ,r2d_nb=0       % Number of record copy from RAM to DISC
                ,d2r_nb=0       % Number of record copy from DISC to RAM
                ,ram_cnt=0      % Number of record in RAM table (our point of view)
                ,max_cnt=0      % Maximum number of records allowed in RAM table
                ,disc_cnt=0     % Number of record in DISC table (our point of view)
                ,ram_mem=0      % Memory size of RAM table, in words 
                ,max_mem=0      % Maximum memory size of RAM table, in words
                ,max_key=undefined % Max key in RAM table
                ,min_key=undefined % Min key in RAM table
               }).

-define(TIMEOUT, 30).

%-define(DEBUG(X), io:format("~p~n",[X])).   
-define(DEBUG(X), ok).     

-define(STATE(S), do_state(S#cachet.mode, check_limits(S))).


start_link({R, D, C, M, O}) ->
    gen_fsm:start_link({local,R}, cachet_fsm, [{R, D, C, M, O}], []).

init([{R, D, C, M, O}]) ->
    try 
        % Wait for RAM table to be ready
        wait_for_table(D),
        % Wait for Disc table to be ready
        wait_for_table(D),
        % Verify R and D are valid table type for Mode
        verify_ram_table(M, R),
        verify_disc_table(M, D),
        % Verify records are the same
        verify_records_identity(R, D),
        % Verify access rights to both tables
        verify_access(D),
        verify_access(R),
        % Subscribe to receive events
        subscribe(D),
        subscribe(R),
        % Get number of record for both tables
        RamCnt  = get_records_number(R),
        DiscCnt = get_records_number(D),
        % Get current RAM table memory size
        RamMem  = get_table_memsize(R),
        % What is the maximum records allowed for this table
        MaxCnt  = get_max_records_allowed(O, RamCnt, DiscCnt),
        % What is the maximum memory size allowed for this table
        MaxMem  = get_max_memory_allowed(O),

        % If C is [] set first element as key, the usual mnesia table key.
        C2 = case C of
                [] -> lists:nth(1,mnesia:table_info(R, attributes)) ;
                _  -> C
             end,

        % Get the min/max key in RAM table at start, and keep updated for performance
        {MinKey, MaxKey} = get_min_max_key(R, C2),

        StateData = #cachet{init={R, D, C2, M, O}
                           ,ram=R
                           ,disc=D
                           ,mode=M
                           ,r2d_nb=0
                           ,d2r_nb=0
                           ,ram_cnt=RamCnt
                           ,max_cnt=MaxCnt
                           ,disc_cnt=DiscCnt
                           ,ram_mem=RamMem
                           ,max_mem=MaxMem
                           ,max_key=MaxKey
                           ,min_key=MinKey
                           },
        State = check_limits(StateData),

        {ok, do_state(M,State), StateData}
    catch
        throw:Err -> {stop,Err}
    end.

handle_info({mnesia_table_event, Event}, StateName, StateData) ->
    %?DEBUG(Event),
    gen_fsm:send_event(self(),Event),
    {next_state, StateName, StateData};
handle_info({'EXIT', _Pid, _Reason}, StateName, StateData) ->
    {next_state, StateName, StateData};
handle_info(_Other, StateName, StateData) ->
    %?DEBUG(_Other),
    {next_state, StateName, StateData}.

handle_event(stop, _StateName, StateData) ->
    {stop, normal, StateData}.

handle_sync_event(state, From, StateName, StateData) -> {reply, StateData, StateName, StateData}.

terminate(normal, _StateName, _StateData) ->
    ok.


%%------------------------------------------------------------------------------
%% @doc Generic wait state for events
%% @end
%%------------------------------------------------------------------------------
events(_E, S) -> {next_state, events, S}.

%%******************************************************************************
%% MODE : CACHE - Last used data kept in memory and all data on disc.
%%        Table in RAM can be ram_only (volatile) or disc_copy (persistent)
%%        Table on Disc must be disc_only_copy
%%
%%------------------------------------------------------------------------------
%% @doc Event handler when Cache RAM table under records/size limit
%%            user                    cachet
%%    1. Write in RAM table   -> Copy record in DISC table
%%    2. Write in DISC table  -> Copy record in RAM table
%%    3. Delete in RAM table  -> Delete in DISC table
%%    4. Delete in DISC table -> Delete in RAM table
%% @end
%%------------------------------------------------------------------------------
%%    Delete in RAM table  -> Delete in DISC table
cache_under_limit({delete, T, _W, Old, _AcId}, S) when (T =:= S#cachet.ram)   -> 
        %?DEBUG(Old),
        lists:foreach(fun(R)-> 
                      ok = mnesia:dirty_delete(S#cachet.disc, R) end,
                      Old),
        {next_state, ?STATE(S), S};
%%    Delete in DISC table -> Delete in RAM table
cache_under_limit({delete, T, _W, Old, _AcId}, S) when (T =:= S#cachet.disc)  -> 
        %?DEBUG(Old),
        lists:foreach(fun(R)-> 
                      ok = mnesia:dirty_delete(S#cachet.ram, R) end,
                      Old),
        {next_state, ?STATE(S), S};
%%    Write in RAM table   -> Copy in DISC table
cache_under_limit({write, T, New, _Old, _AcId}, S) when (T =:= S#cachet.ram)  -> 
        %?DEBUG(New),
        ok = mnesia:dirty_write(S#cachet.disc, New),
        {next_state, ?STATE(S), S};
%%    Write in DISC table  -> Copy in RAM table
cache_under_limit({write, T, New, _Old, _AcId}, S) when (T =:= S#cachet.disc) -> 
        %?DEBUG(New),
        ok = mnesia:dirty_write(S#cachet.ram, New),
        {next_state, ?STATE(S), S};
cache_under_limit(_Other, S) -> %?DEBUG(_Other),
                                {next_state, ?STATE(S), S}.

%%------------------------------------------------------------------------------
%% @doc Event handler when Cache RAM table over records/size limit
%%            user                    cachet
%%    1. Write in RAM table   -> Copy in DISC table + Delete older in RAM table
%%    2. Write in DISC table  -> Copy in RAM table and Delete older 
%%    3. Delete in RAM table  -> Delete in DISC table
%%    4. Delete in DISC table -> Delete in RAM table
%% @end
%%------------------------------------------------------------------------------
%%    Delete in RAM table  -> Delete in DISC table
cache_over_limit({delete, T, _W, Old, {_, Pid}}, S) when (T =:= S#cachet.ram),
                                                           (Pid =/= self())   -> 
        %?DEBUG(Old),
        lists:foreach(fun(R)-> 
                      ok = mnesia:dirty_delete(S#cachet.disc, R) end,
                      Old),
        US = ram_update(S),
        NS = US#cachet{ram_cnt=(US#cachet.ram_cnt - 1),
                       disc_cnt=(US#cachet.disc_cnt - 1)},
        {next_state, ?STATE(NS), NS};
%%    Delete in DISC table -> Delete in RAM table
cache_over_limit({delete, T, _W, Old, {_, Pid}}, S) when (T =:= S#cachet.disc),
                                                           (Pid =/= self())   -> 
        %?DEBUG(Old),
        lists:foreach(fun(R)-> 
                      ok = mnesia:dirty_delete(S#cachet.ram, R) end,
                      Old),
        US = ram_update(S),
        NS = US#cachet{ram_cnt=(US#cachet.ram_cnt - 1),
                       disc_cnt=(US#cachet.disc_cnt - 1)},
        {next_state, ?STATE(NS), NS};
%%    Write in RAM table   -> Copy in DISC table + Delete older in RAM table
cache_over_limit({write, T, New, _Old, {_, Pid}}, S) when (T =:= S#cachet.ram),
                                                           (Pid =/= self())   -> 
        %?DEBUG(New),
        ok = mnesia:dirty_write(S#cachet.disc, New),
        ok = mnesia:dirty_delete({S#cachet.ram, S#cachet.min_key}),
        US = ram_update(S),
        NS = US#cachet{r2d_nb=(US#cachet.r2d_nb + 1)},
        {next_state, ?STATE(NS), NS};
%%    Write in DISC table  -> Delete min and Copy in RAM table 
cache_over_limit({write, T, New, _Old, {_, Pid}}, S) when (T =:= S#cachet.disc),
                                                           (Pid =/= self())   -> 
        %?DEBUG(New),
        ok = mnesia:dirty_delete({S#cachet.ram, S#cachet.min_key}),
        ok = mnesia:dirty_write(S#cachet.ram, New),
        US = ram_update(S),
        NS = US#cachet{d2r_nb=(US#cachet.d2r_nb + 1),
                       disc_cnt=(US#cachet.disc_cnt + 1) },
        {next_state, ?STATE(NS), NS};
%%    Other events
cache_over_limit(_Other, S) -> %?DEBUG(_Other),
                               {next_state, ?STATE(S), S}.

%%******************************************************************************
%% MODE : SPLIT - Separating data with quick access on active data and 
%%                slow access to unactive data.
%%        Table in RAM  must be disc_copy (persistent)
%%        Table on Disc must be disc_only_copy
%%
%%------------------------------------------------------------------------------
%% @doc Event handler when RAM table under records/size limit
%%      RAM table does not reach records/size limit :
%%         user                    cachet
%%    1. Write in RAM table   -> Do nothing
%%    2. Write in DISC table  -> Do nothing
%%    3. Delete in RAM table  -> Do nothing
%%    4. Delete in DISC table -> Do nothing
%% @end
%%------------------------------------------------------------------------------

split_under_limit({delete, T, _W, _Old, _AcId}, S) when (T =:= S#cachet.ram)  ->         
        %?DEBUG(Old),
        RamCnt = S#cachet.ram_cnt,
        {next_state, ?STATE(S), S#cachet{ram_cnt=(RamCnt - 1)}};

split_under_limit({delete, T, _W, _Old, _AcId}, S) when (T =:= S#cachet.disc) ->         
        %?DEBUG(Old),
        DiscCnt = S#cachet.disc_cnt,
        {next_state, ?STATE(S), S#cachet{disc_cnt=(DiscCnt - 1)}};

split_under_limit({write, T, _New, _Old, _AcId}, S) when (T =:= S#cachet.ram) ->         
        %?DEBUG(New),
        RamCnt = S#cachet.ram_cnt,
        {next_state, ?STATE(S), S#cachet{ram_cnt=(RamCnt + 1)}};

split_under_limit({write, T, _New, _Old, _AcId}, S) when (T =:= S#cachet.disc)->       
        %?DEBUG(New),
        DiscCnt = S#cachet.disc_cnt,
        {next_state, ?STATE(S), S#cachet{disc_cnt=(DiscCnt + 1)}};
split_under_limit(_Other, S) -> %?DEBUG(_Other),
                                {next_state, ?STATE(S), S}.

%%------------------------------------------------------------------------------
%% @doc Event handler when RAM table over records/size limit
%%      RAM table reached records/size limit :
%%         user                    cachet
%%    1. Write in RAM table   -> Move older record in DISC table
%%    2. Write in DISC table  -> Do nothing
%%    3. Delete in RAM table  -> Do nothing
%%    4. Delete in DISC table -> Do nothing
%% @end
%%------------------------------------------------------------------------------

split_over_limit({delete, T, _W, _Old, _AcId}, S) when (T =:= S#cachet.ram)   ->         
        %?DEBUG(Old),
        {next_state, ?STATE(S), S};

split_over_limit({delete, T, _W, _Old, _AcId}, S) when (T =:= S#cachet.disc)  ->         
        %?DEBUG(Old),
        {next_state, ?STATE(S), S};

split_over_limit({write, T, _New, _Old, _AcId}, S) when (T =:= S#cachet.ram)  -> 
        %?DEBUG(New),
        {next_state, ?STATE(S), S};

split_over_limit({write, T, _New, _Old, _AcId}, S) when (T =:= S#cachet.disc) -> 
        %?DEBUG(New),
        {next_state, ?STATE(S), S};
split_over_limit(_Other, S) -> %?DEBUG(_Other),
                               {next_state, ?STATE(S), S}.



%%******************************************************************************

%%------------------------------------------------------------------------------
%% @doc Wait for a Mnesia table to be ready
%% @end
%%------------------------------------------------------------------------------
wait_for_table(T) ->  
        case mnesia:wait_for_tables([T], ?TIMEOUT) of
             ok              -> ok;
             {timeout, _}    -> throw("Error : timeout waiting table " ++ 
                                      atom_to_list(T)),
                                      error;
             {error, Reason} -> throw("Error while waiting table " ++ 
                                      atom_to_list(T) ++ " - " ++ Reason),
                                      error
        end.

%%------------------------------------------------------------------------------
%% @doc Verify that both RAM/DISC table are compatible TODO
%% @end
%%------------------------------------------------------------------------------
verify_records_identity(_R, _D) -> ok.

%%------------------------------------------------------------------------------
%% @doc Verify that read_write access is allowed
%% @end
%%------------------------------------------------------------------------------
-spec verify_access(atom()) -> ok | error.

verify_access(T) -> 
        case mnesia:table_info(T, 'access_mode') of
             read_only  -> throw("Error : read only access mode on table " ++
                                 atom_to_list(T)), 
                           error ;
             read_write -> ok
        end.

%%------------------------------------------------------------------------------
%% @doc Get number of records in table
%% @end
%%------------------------------------------------------------------------------
-spec get_records_number(atom()) -> integer().

get_records_number(T) -> mnesia:table_info(T, 'size').

%%------------------------------------------------------------------------------
%% @doc Get memory size of a table in words
%% @end
%%------------------------------------------------------------------------------
-spec get_table_memsize(atom()) -> integer().

get_table_memsize(T)  -> mnesia:table_info(T, 'memory').

%%------------------------------------------------------------------------------
%% @doc Subscribe to events for a particular table
%% @end
%%------------------------------------------------------------------------------
%-spec subscribe(atom()) -> TODO.

subscribe(T) -> mnesia:subscribe({table, T, detailed}).

%%------------------------------------------------------------------------------
%% @doc Compute the maximum memory size for the RAM table TODO
%% @end
%%------------------------------------------------------------------------------
-spec get_max_ram_allowed(atom()) -> integer().
 
get_max_ram_allowed(_R) -> 0.

%%------------------------------------------------------------------------------
%% @doc Verify R is a RAM table only
%% TODO handle 'unknown'
%% @end
%%------------------------------------------------------------------------------
-spec verify_ram_table(atom()) -> ok | error.

verify_ram_table(R) -> 
        case catch mnesia:table_info(R, 'storage_type') of
             ram_copies -> ok ;
             _          -> throw("Error : table " ++ atom_to_list(R) ++ 
                                 " is not of type ram_copies"), 
                           error 
        end.

%%------------------------------------------------------------------------------
%% @doc Verify D is a Disc table only
%% TODO handle 'unknown'
%% @end
%%------------------------------------------------------------------------------
verify_disc_table(D) -> 
        case mnesia:table_info(D, 'storage_type') of
             ram_copies -> ok ;
             _          -> throw("Error : table " ++ atom_to_list(D) ++ 
                                 " is not of type disc_only_copies"), 
                           error 
        end.

%%------------------------------------------------------------------------------
%% @doc Get the maximum of records allowed
%% if < 1 : percent of records in disc table (may increase at each start !)
%% if > 1 : number of records.
%% if < 0 : difference between number of records in disc table and this value.
%% Max integer on 32bit is 134217728, let's use it as default, enough !
%% @end
%%------------------------------------------------------------------------------
-spec get_max_records_allowed(list(), integer(), integer()) -> integer().

get_max_records_allowed(O, _R, D) -> 
        MaxRec = proplists:get_value(records, O, 134217728),
        case (MaxRec < 1 ) of
             false -> round(MaxRec);
             true  -> case (MaxRec < 0 ) of
                           true  -> (D - round(abs(MaxRec)));
                           false -> round(MaxRec * D)
             end
        end.

%%------------------------------------------------------------------------------
%% @doc Get the maximum of memory allowed
%% if < 1 : percentage of current memory usable by emulator
%% if > 1 : memory in bytes
%% if < 0 : difference between memory usable by emulator and this value.
%% @end
%%------------------------------------------------------------------------------
get_max_memory_allowed(O)-> 
        M      = 0, % TODO
        MaxMem = proplists:get_value(memory, O, M),
        case (MaxMem < 1 ) of
             false -> round(MaxMem);
             true  -> case (MaxMem < 0 ) of
                           true  -> (M - round(abs(MaxMem)));
                           false -> round(MaxMem * M)
                      end
        end.

%%------------------------------------------------------------------------------
%% @doc check whether limits are reached
%% @end
%%------------------------------------------------------------------------------
check_limits(S) -> case ((S#cachet.ram_cnt > S#cachet.max_cnt) or 
                         (S#cachet.ram_mem > S#cachet.max_mem)) of
                        true   -> over_limit ;
                        false  -> under_limit
                   end.

get_tables_mode() -> ok.

verify_ram_table(_,_) -> ok.

verify_disc_table(_,_) -> ok.

%%------------------------------------------------------------------------------
%% @doc Get min and max key on table
%% @end
%%------------------------------------------------------------------------------
get_min_max_key(R, C) -> 
%        {0, 0}.
        Pos = find_first(C, mnesia:table_info(R, attributes)),
        Pivot = 
              fun(Rec, []) when is_tuple(Rec),
                                (size(Rec) > 0) -> ?DEBUG(Rec),
                                                 V=lists:nth((Pos + 1),
                                                 tuple_to_list(Rec)), {V, V};
                 (Rec, {Min, Max}) when is_tuple(Rec),
                                  (size(Rec) > 0)   -> 
                                                 ?DEBUG(Rec),
                                                 V=lists:nth((Pos + 1),
                                                 tuple_to_list(Rec)),                                                 
                                                 {min(V, Min), max(V, Max)};
                 (_Rec, _) -> ?DEBUG(_Rec),
                              {0, 0}
              end,
        Find = fun() -> mnesia:foldl(Pivot, [], R) end,
        mnesia:transaction(Find).



%%------------------------------------------------------------------------------
%% @doc Get first element of a list
%% @end
%%------------------------------------------------------------------------------
find_first(Element, List) when is_list(List) ->
    find_first(Element, List, 0).

find_first(_Element, [], Inc) when is_integer(Inc) ->
    Inc + 1;
find_first(Element, [Element | _Tail], Inc) when is_integer(Inc) ->
    Inc + 1;
find_first(Element, [_ | Tail], Inc) when is_integer(Inc) ->
    find_first(Element, Tail, Inc + 1).

%%------------------------------------------------------------------------------
%% @doc Create the state name
%% @end
%%------------------------------------------------------------------------------
-spec do_state(atom(), atom()) -> atom().

do_state(cache, Limit) when is_atom(Limit)-> 
        list_to_atom(atom_to_list(cache) ++ "_" ++ atom_to_list(Limit)) ;
do_state(split, Limit) when is_atom(Limit)-> 
        list_to_atom(atom_to_list(split) ++ "_" ++ atom_to_list(Limit)) .

%%------------------------------------------------------------------------------
%% @doc Return update state for min and max key in RAM
%% @end
%%------------------------------------------------------------------------------
-spec ram_update(tuple()) -> tuple().

ram_update(S) -> 
                 {_, _, C, _, _} = S#cachet.init,
                 CR = case C of
                        { X, _} -> X;
                        X       -> X 
                      end,
                 % Find the new min/max
                 {Min, Max} = get_min_max_key(S#cachet.ram, CR),
                 S#cachet{min_key=Min,max_key=Max}.

 
