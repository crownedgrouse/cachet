%%%-------------------------------------------------------------------
%%% File:      cachet_SUITE.erl
%%% @author    Eric Pailleau <cachet@crownedgrouse.com>
%%% @copyright 2014 crownedgrouse.com
%%% @doc  
%%% Cachet Common Test Suite
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
%%% Created : 2014-11-30
%%%-------------------------------------------------------------------
-module(cachet_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-record(cachet, {id
                ,timestamp
                ,term
                }).

%%--------------------------------------------------------------------
%% Function: suite() -> Info
%% Info = [tuple()]
%%--------------------------------------------------------------------
suite() ->
    [{timetrap,{seconds,30}}].

%%--------------------------------------------------------------------
%% Function: init_per_suite(Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    application:set_env(sasl, errlog_type, error),
    application:start(sasl),
    % cd into priv_dir
    PrivDir = ?config(priv_dir, Config),
    ok = file:set_cwd(PrivDir),
    % Load CT data
    {ok, Data} = file:consult(filename:join(code:priv_dir(cachet), "ct_data.list")),
    Config ++ [{ct_data, lists:flatten(Data)}].

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%% Config0 = Config1 = [tuple()]
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    % Stop mnesia
    application:stop(mnesia),
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_group(GroupName, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%%--------------------------------------------------------------------
init_per_group(set, Config) ->
    % Create a database elsewhere to get rid of already existing table error...
    PrivDir = ?config(priv_dir, Config),
    file:make_dir(filename:join(PrivDir,"set")),
    ok = file:set_cwd(filename:join(PrivDir,"set")),
    ok = mnesia:create_schema([node()]),
    application:start(mnesia),
    % Create typed table
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    {atomic,ok} = mnesia:create_table(test_ram,  [{record_name, cachet},{type, set}, {attributes, record_info(fields, cachet)}]),        
    {atomic,ok} = mnesia:create_table(test_disc, [{record_name, cachet},{type, set},{attributes, record_info(fields, cachet)}]),
    ct_data(set,Config);
init_per_group(bag, Config) ->
    % Create a database elsewhere to get rid of already existing table error...
    PrivDir = ?config(priv_dir, Config),
    file:make_dir(filename:join(PrivDir,"bag")),
    ok = file:set_cwd(filename:join(PrivDir,"bag")),
    ok = mnesia:create_schema([node()]),
    application:start(mnesia),
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    {atomic,ok} = mnesia:create_table(test_ram,  [{record_name, cachet},{type, bag},{attributes, record_info(fields, cachet)}]),        
    {atomic,ok} = mnesia:create_table(test_disc, [{record_name, cachet},{type, bag},{attributes, record_info(fields, cachet)}]),
    ct_data(bag,Config);
init_per_group(ord_set, Config) ->
    % Create a database elsewhere to get rid of already existing table error...
    PrivDir = ?config(priv_dir, Config),
    file:make_dir(filename:join(PrivDir,"ord_set")),
    ok = file:set_cwd(filename:join(PrivDir,"ord_set")),
    ok = mnesia:create_schema([node()]),
    application:start(mnesia),
    % NOTE : currently 'ordered_set' is not supported for 'disc_only_copies'. 
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    {atomic,ok} = mnesia:create_table(test_ram,  [{record_name, cachet},{type, ordered_set},{attributes, record_info(fields, cachet)}]),        
    {atomic,ok} = mnesia:create_table(test_disc, [{record_name, cachet},{type, set},{attributes, record_info(fields, cachet)}]),
    ct_data(ord_set,Config);
init_per_group(cache, Config) ->
    {atomic, ok} = mnesia:change_table_copy_type(test_disc, node(), disc_only_copies),
    case mnesia:table_info(test_ram, storage_type) of
            ram_copies          -> ok ;
            _ -> {atomic, ok} = mnesia:change_table_copy_type(test_ram, node(), ram_copies)
    end,
    ct_data(cache,lists:keydelete(mode, 1, Config) ++ [{mode, cache}]);
init_per_group(split, Config) ->
    case mnesia:table_info(test_disc, storage_type) of
            disc_only_copies    -> ok ;
            _ -> {atomic, ok} = mnesia:change_table_copy_type(test_disc, node(), disc_only_copies)
    end,
    {atomic, ok} = mnesia:change_table_copy_type(test_ram, node(), disc_copies),
    ct_data(split,lists:keydelete(mode, 1, Config) ++ [{mode, split}]);
init_per_group(id, Config) ->
    Mode = ?config(mode, Config),
    % Load cachet application config
    application:set_env(cachet, tables, [{test_ram, test_disc, {id, 'integer'}, Mode, [{records, 10}]}]),
    ok = application:start(cachet),
    ct_data(id,Config);
init_per_group(timestamp, Config) ->
    Mode = ?config(mode, Config),
    % Load cachet application config
    application:set_env(cachet, tables, [{test_ram, test_disc, {timestamp, 'datetime'}, Mode, [{records, 10}]}]),
    ok = application:start(cachet),
    ct_data(timestamp,Config);
init_per_group(term, Config) ->
    Mode = ?config(mode, Config),
    % Load cachet application config
    application:set_env(cachet, tables, [{test_ram, test_disc, {term, 'term'}, Mode, [{records, 10}]}]),
    ok = application:start(cachet),
    ct_data(term,Config);
init_per_group(write, Config) ->
    ct_data(write, Config);
init_per_group(delete, Config) ->
    ct_data(delete, Config);
init_per_group(write_ram, Config) ->
    ct_data(write_ram, Config);
init_per_group(delete_ram, Config) ->
    ct_data(delete_ram, Config);
init_per_group(write_disc, Config) ->
    ct_data(write_disc, Config);
init_per_group(delete_disc, Config) ->
    ct_data(delete_disc, Config);
init_per_group(_GroupName, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%               void() | {save_config,Config1}
%% GroupName = atom()
%% Config0 = Config1 = [tuple()]
%%--------------------------------------------------------------------
end_per_group(id, _Config) ->
    ct:pal(io_lib:format("End id : ~p",[gen_fsm:sync_send_all_state_event(test_ram, state)])),
    {atomic, ok} = mnesia:clear_table(test_ram),
    {atomic, ok} = mnesia:clear_table(test_disc),
    ok = application:stop(cachet),
    ok;
end_per_group(timestamp, _Config) ->
    ct:pal(io_lib:format("End timestamp : ~p",[gen_fsm:sync_send_all_state_event(test_ram, state)])),
    {atomic, ok} = mnesia:clear_table(test_ram),
    {atomic, ok} = mnesia:clear_table(test_disc),
    ok = application:stop(cachet),
    ok;
end_per_group(term, _Config) ->
    ct:pal(io_lib:format("End term : ~p",[gen_fsm:sync_send_all_state_event(test_ram, state)])),
    {atomic, ok} = mnesia:clear_table(test_ram),
    {atomic, ok} = mnesia:clear_table(test_disc),
    ok = application:stop(cachet),
    ok;
end_per_group(write, _Config) ->
    ok;
end_per_group(delete, _Config) ->
    ok;
end_per_group(set, Config) ->
    application:stop(mnesia),
    PrivDir = ?config(priv_dir, Config),
    ok = file:set_cwd(PrivDir),
    ok;
end_per_group(bag, Config) ->
    application:stop(mnesia),
    PrivDir = ?config(priv_dir, Config),
    ok = file:set_cwd(PrivDir),
    ok;
end_per_group(ord_set, Config) ->
    application:stop(mnesia),
    PrivDir = ?config(priv_dir, Config),
    ok = file:set_cwd(PrivDir),
    ok;
end_per_group(_GroupName, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%%--------------------------------------------------------------------
init_per_testcase(write_ram, Config) ->
    Config;
init_per_testcase(write_disc, Config) ->
    Config;
init_per_testcase(TestCase, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%%--------------------------------------------------------------------
end_per_testcase(write_ram, Config) ->
    {write_ram, Assert} = lists:keyfind(write_ram, 1, ?config(ct_data, Config)),
    ct:pal(io_lib:format("end WR : {~p, ~p} / ~p ",[mnesia:table_info(test_ram, size), mnesia:table_info(test_disc, size), Assert])),
    ok;
end_per_testcase(write_disc, Config) ->
    {write_disc, Assert} = lists:keyfind(write_disc, 1, ?config(ct_data, Config)),
    ct:pal(io_lib:format("end WR : {~p, ~p} / ~p ",[mnesia:table_info(test_ram, size), mnesia:table_info(test_disc, size), Assert])),
    ok;
end_per_testcase(TestCase, Config) ->    
    {TestCase, Assert} = lists:keyfind(TestCase, 1, ?config(ct_data, Config)),
    ct:pal(io_lib:format("end WR : {~p, ~p} / ~p ",[mnesia:table_info(test_ram, size), mnesia:table_info(test_disc, size), Assert])),
    ok.

%%--------------------------------------------------------------------
%% Function: groups() -> [Group]
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName = atom()
%% Properties = [parallel | sequence | Shuffle | {RepeatType,N}]
%% GroupsAndTestCases = [Group | {group,GroupName} | TestCase]
%% TestCase = atom()
%% Shuffle = shuffle | {shuffle,{integer(),integer(),integer()}}
%% RepeatType = repeat | repeat_until_all_ok | repeat_until_all_fail |
%%              repeat_until_any_ok | repeat_until_any_fail
%% N = integer() | forever
%%--------------------------------------------------------------------
groups() ->
    [ 
     % Type of table
     {set,     [sequence], [{group, cache}, {group, split}]}
    ,{bag,     [sequence], [{group, cache}, {group, split}]}
    ,{ord_set, [sequence], [{group, cache}, {group, split}]}
    % Mode
    ,{cache, [sequence], [{group, id}, {group, timestamp}, {group, term}]}
    ,{split, [sequence], [{group, id}, {group, timestamp}, {group, term}]}
     % Type of column
    ,{id,        [sequence], [{group, write}, {group, delete}]}
    ,{timestamp, [sequence], [{group, write}, {group, delete}]}
    ,{term,      [sequence], [{group, write}, {group, delete}]}
     % Type of operation
    ,{write,  [sequence], [write_ram, write_disc]}
    ,{delete, [sequence], [delete_ram, delete_disc]}
    ].

%%--------------------------------------------------------------------
%% Function: all() -> GroupsAndTestCases | {skip,Reason}
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%% TestCase = atom()
%% Reason = term()
%%--------------------------------------------------------------------
all() -> 
    [{group, set}, {group, bag}, {group, ord_set}].

%%--------------------------------------------------------------------
%% Function: TestCase() -> Info
%% Info = [tuple()]
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% Function: TestCase(Config0) ->
%%               ok | exit() | {skip,Reason} | {comment,Comment} |
%%               {save_config,Config1} | {skip_and_save,Reason,Config1}
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% Comment = term()
%%--------------------------------------------------------------------


write_ram() ->  List = get_records(20),
                lists:foreach(fun(Record) ->  ok = mnesia:dirty_write(test_ram, Record) end, List),
                [].
write_ram(_Config) -> ok.

write_disc() -> List = get_records(20),
                lists:foreach(fun(Record) -> ok = mnesia:dirty_write(test_disc, Record) end, List),
                [].
write_disc(_Config) -> ok.

delete_ram() -> lists:foreach(fun(Key) -> ok = mnesia:dirty_delete(test_ram, Key) end, lists:seq(1,10)),
                [].
delete_ram(_Config) -> ok.

delete_disc()-> lists:foreach(fun(Key) -> ok = mnesia:dirty_delete(test_disc, Key) end, lists:seq(1,10)),
                [].
delete_disc(_Config) -> ok.


get_records(Int) -> lists:flatmap(fun(Id) -> [#cachet{id=Id, timestamp=calendar:local_time(), term=erlang:memory()}] end, lists:seq(1, Int)).

ct_data(What, Config) -> 
                         % Get ct_data tuple
                         List = ?config(ct_data, Config),
                         % Remove from current config
                         C1 = lists:keydelete(ct_data, 1, Config),
                         % Bring tuples with element 1 = What
                         Pred = fun(X) -> lists:keymember(What, 1, [X]) end, 
                         {OK, _NOK} = lists:partition(Pred, List), 
                         % Shrink tuple length
                         Fun = fun(Z)-> [H | T] = tuple_to_list(Z), [list_to_tuple(T)] end,
                         CT = lists:flatmap(Fun, OK),
                         % New config
                         NewConfig = C1 ++ [{ct_data, CT}],
                         %ct:pal(io_lib:format("~p",[NewConfig])),
                         NewConfig.
                            


